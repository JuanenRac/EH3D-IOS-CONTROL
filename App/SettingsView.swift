// EH3D-IOS-CONTROL - the page of the settings of the server, drawn from its contract: the groups in the order of the contract and, for each setting, its label, help and warning in the language of the
// app, the value in force, the default with a button to restore it, whether a change applies at once or needs a restart, and the control of its type (a switch, a number with its range and unit, a text,
// a list, a choice). An administrator changes the ones the server changes while it runs (`PUT /auth/policy`); the ones set in server.cfg are shown with their value and say so; a secret never shows its
// value; a risky change is asked a second time. When the live contract cannot be read the copy kept in the app is shown, read-only, with the reason. The rules are in Sources/Eh3dCore/SettingsContract.swift;
// this is the same page as the one of the Android app (SettingsScreens.kt).
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI
import Eh3dCore

/// A change that waits for the second touch: `weak` is true when the server itself asked for `confirm_weak`.
private struct PendingChange: Identifiable {
    let id = UUID()
    let setting: Setting
    let value: SettingValue
    let weak: Bool
}

struct ServerSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var drafts: [String: String] = [:]
    @State private var pending: PendingChange?
    private let known = Set(EmbeddedContract.get().settings.map { $0.key })

    private var role: String { model.login?.role ?? "" }

    /// The text of the page in the language of the app.
    private func st(_ key: String, _ vars: [String: Any] = [:]) -> String { SettingsTexts.text(key, language: model.language, vars: vars) }

    /// A value as the page says it: `on`/`off` for a switch, `-` for nothing.
    private func said(_ value: SettingValue?) -> String {
        if case .bool(let flag)? = value { return st(flag ? "ssc_on" : "ssc_off") }
        let line = shownValue(value)
        return line.isEmpty ? "-" : line
    }

    /// A change a person asked for: a risky setting is asked first (and then sent with the confirmation the server may want); the rest goes straight.
    private func ask(_ setting: Setting, _ value: SettingValue) {
        if isHighRisk(setting) {
            pending = PendingChange(setting: setting, value: value, weak: false)
        } else {
            send(setting, value, confirmWeak: setting.confirmWhenLooser)
        }
    }

    private func send(_ setting: Setting, _ value: SettingValue, confirmWeak: Bool) {
        model.changeSetting(setting, value: value, confirmWeak: confirmWeak) { pending = PendingChange(setting: setting, value: value, weak: true) }
    }

    private func confirmText(_ change: PendingChange) -> String {
        let words = change.weak ? st("ssc_weak_confirm") : st("ssc_confirm_risk", ["key": change.setting.key, "warning": contractText(change.setting.warning, model.language)])
        return words + "\n\n" + change.setting.key + " = " + said(change.value)
    }

    /// The value the Save button would send: what was typed when it is right and not what is already in force.
    private func saveValue(_ typed: Typed?, _ current: SettingValue?) -> SettingValue? {
        if case .ok(let value)? = typed, value != current { return value }
        return nil
    }

    private func problemText(_ problem: SettingProblem, _ s: Setting) -> String {
        switch problem {
        case .number: return st("ssc_bad_number", ["min": s.min.map { String($0) } ?? "", "max": s.max.map { String($0) } ?? ""])
        case .text: return st("ssc_bad_text", ["n": s.maxLength ?? 0])
        case .choice: return st("ssc_bad_choice")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Button("‹ " + model.tr("Volver")) { model.back() }
                HStack {
                    Text(st("ssc_title")).font(.title2).foregroundColor(Forge.text)
                    Spacer()
                    Button(st("ssc_refresh")) { model.loadSettings() }.buttonStyle(.bordered)
                }
                Text(st("ssc_help")).font(.caption).foregroundColor(Forge.dim)
                header
                if let view = model.settingsView {
                    ForEach(groupSettings(view.contract), id: \.id) { group in
                        Title(contractText(group.label, model.language).isEmpty ? group.id : contractText(group.label, model.language))
                        ForEach(group.settings, id: \.key) { s in card(view, s, notInCopy: view.live && !known.contains(s.key)) }
                    }
                    let unlisted = view.live || view.light ? unlistedSettings(view.contract, view.values, kept: view.secretKeys + view.hiddenKeys) : []
                    if !unlisted.isEmpty {
                        Title(st("ssc_other"))
                        ForEach(unlisted, id: \.key) { s in card(view, s, notInCopy: false) }
                    }
                }
            }.padding(16)
        }
        .onAppear { model.loadSettings() }
        .confirmationDialog(pending?.setting.key ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible, presenting: pending) { change in
            Button(st("ssc_confirm"), role: .destructive) {
                pending = nil
                send(change.setting, change.value, confirmWeak: change.weak || change.setting.confirmWhenLooser)
            }
            Button(st("ssc_cancel"), role: .cancel) { pending = nil }
        } message: { change in
            Text(confirmText(change))
        }
    }

    @ViewBuilder private var header: some View {
        if let view = model.settingsView {
            if view.live {
                Text(st("ssc_live", ["v": view.serverVersion ?? "-"])).font(.caption).foregroundColor(Forge.green)
            } else if view.light {
                Text(st("ssc_light", ["v": view.serverVersion ?? "-"])).font(.caption).foregroundColor(Forge.green)
                if view.hash == .differs { Text(st("ssc_hash_differs")).font(.caption).foregroundColor(Forge.orange) }
            } else {
                Text(st(role == "admin" ? "ssc_embedded" : "ssc_embedded_values", ["why": view.why ?? ""])).font(.caption).foregroundColor(Forge.orange)
            }
            if !view.live || role != "admin" { Text(st("ssc_readonly_role")).font(.caption).foregroundColor(Forge.dim) }
        } else {
            Text(st("ssc_loading")).foregroundColor(Forge.dim)
        }
    }

    /// One setting: what it is, what the server holds now, what it was meant to be, when a change takes effect and the control to change it.
    @ViewBuilder private func card(_ view: LoadedContract, _ s: Setting, notInCopy: Bool) -> some View {
        let current = valueOf(s, view.values)
        let kind = controlKind(s)
        let editable = view.live && canWriteSetting(role: role, s)
        let busy = model.settingsBusy == s.key
        let serverSecret = view.secretKeys.contains(s.key)
        let keptBack = view.hiddenKeys.contains(s.key)
        let cut = view.truncatedKeys.contains(s.key)
        let draft = drafts[s.key]
        let typed = draft.map { parseTyped(s, $0) }
        let note = model.settingsNotes[s.key]
        let warning = contractText(s.warning, model.language)
        let help = contractText(s.help, model.language)
        let name = contractText(s.label, model.language)
        Card(accent: isHighRisk(s) ? Forge.orange : Forge.amber) {
            HStack {
                VStack(alignment: .leading) {
                    Text(name.isEmpty ? s.key : name).font(.subheadline.weight(.semibold)).foregroundColor(Forge.text)
                    Text(s.key).font(.caption).foregroundColor(Forge.dim)
                }
                Spacer()
                if s.write.via != "none" {
                    Pill(text: st(s.apply == "restart" ? "ssc_apply_restart" : "ssc_apply_now"), color: s.apply == "restart" ? Forge.orange : Forge.green)
                }
            }
            if !help.isEmpty { Text(help).font(.caption).foregroundColor(Forge.dim) }
            if (isHighRisk(s) || s.apply == "restart") && !warning.isEmpty { Text(warning).font(.caption).foregroundColor(Forge.dim) }
            if isHighRisk(s) { Pill(text: "▲ " + st("ssc_risk_high"), color: Forge.danger) }
            if notInCopy { Pill(text: st("ssc_unknown"), color: Forge.dim) }
            if kind == .number, let low = s.min, let high = s.max {
                Text("\(low)–\(high)" + (unitText(s.unit).isEmpty ? "" : " " + unitText(s.unit))).font(.caption).foregroundColor(Forge.dim)
            }
            if kind == .list { Text(st("ssc_list_hint")).font(.caption).foregroundColor(Forge.dim) }
            if s.secret || serverSecret {
                Text("●●●  " + st("ssc_secret")).font(.caption).foregroundColor(Forge.dim)
            } else if keptBack {
                Text(st("ssc_hidden")).font(.caption).foregroundColor(Forge.dim)
            } else {
                Text(st("ssc_in_force") + ": " + (current == nil ? "-" : said(current) + (cut ? "…" : ""))).foregroundColor(Forge.text)
                if let fallback = s.defaultValue { Text(st("ssc_default") + ": " + said(fallback)).font(.caption).foregroundColor(Forge.dim) }
                if !editable {
                    if s.write.via == "file" { Text(st("ssc_in_file")).font(.caption).foregroundColor(Forge.dim) }
                } else {
                    control(s, kind: kind, current: current, draft: draft, typed: typed, busy: busy)
                    if let fallback = s.defaultValue, canRestore(editable: true, s, current: current) {
                        Button(st("ssc_restore")) { ask(s, fallback) }.buttonStyle(.bordered).disabled(busy)
                    }
                }
            }
            if case .bad(let problem)? = typed { Text(problemText(problem, s)).font(.caption).foregroundColor(Forge.danger) }
            if let note { Text(note.text).font(.caption).foregroundColor(note.ok ? Forge.green : Forge.danger) }
        }
        .onChange(of: note) { changed in if let changed, changed.ok { drafts[s.key] = nil } }
    }

    /// The control of a setting an administrator may change.
    @ViewBuilder private func control(_ s: Setting, kind: ControlKind, current: SettingValue?, draft: String?, typed: Typed?, busy: Bool) -> some View {
        switch kind {
        case .toggle:
            let isOn = (current ?? s.defaultValue) == SettingValue.bool(true)
            Toggle(said(SettingValue.bool(isOn)), isOn: Binding(get: { isOn }, set: { ask(s, .bool($0)) })).foregroundColor(Forge.text).disabled(busy)
        case .number, .text, .list:
            HStack {
                TextField(unitText(s.unit), text: Binding(get: { draft ?? shownValue(kind == .list ? current : (current ?? s.defaultValue)) }, set: { drafts[s.key] = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(kind == .number ? .numbersAndPunctuation : .default)
                    .autocorrectionDisabled()
                if let value = saveValue(typed, current) {
                    Button(st("ssc_save")) { ask(s, value) }.buttonStyle(.borderedProminent).disabled(busy)
                } else {
                    Button(st("ssc_save")) {}.buttonStyle(.borderedProminent).disabled(true)
                }
            }
        case .select:
            let shown = draft ?? shownValue(current ?? s.defaultValue)
            HStack {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(s.choices, id: \.self) { choice in
                            Button(choice) { drafts[s.key] = choice }.buttonStyle(.bordered).tint(shown == choice ? Forge.amber : Forge.dim)
                        }
                    }
                }
                if let value = saveValue(typed, current) {
                    Button(st("ssc_save")) { ask(s, value) }.buttonStyle(.borderedProminent).disabled(busy)
                } else {
                    Button(st("ssc_save")) {}.buttonStyle(.borderedProminent).disabled(true)
                }
            }
        case .generic:
            EmptyView()
        }
    }
}
