// EH3D-IOS-CONTROL - the settings of the server drawn from its contract (`GET /api/v1/settings/contract`, docs/settings-contract.json and docs/CLIENT_SYNC.md of EH3D-SERVER).
// The server lists every key of `server.cfg` with its group, type, range, default, unit, whether a change applies at once or after a restart, the route that writes it, the role it needs,
// whether it is a secret, its risk and its label, help and warning in eight languages. The app keeps a copy of that file (Resources/settings-contract.json, checked by tools/sync_settings_contract.py)
// for when the live one cannot be read; the page then shows it read-only. Nothing here holds a secret: the value of a secret key is never asked for, shown or written. The same rules and the same
// file as the Android app (model/SettingsContract.kt) and as EH3D-STUDIO (src/services/settingscontract.ts).
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

/// The version of the document that the app understands.
public let contractSchema = "eh3d.settings.contract/1"

/// The languages of the texts of the contract; every other language of the app reads the English text (a variant reads its main language).
public let contractLanguages = ["en", "es", "de", "fr", "it", "ja", "zh", "pt"]

/// How a setting is written: `policy` (a route and a method) or `file` (set in server.cfg, no route).
public struct SettingWrite: Equatable, Sendable {
    public let via: String
    public let method: String?
    public let path: String?
    public let file: String?
}

/// A value of a setting as plain data: a boolean, a whole number, a number, a text or a list of them.
public enum SettingValue: Equatable, Sendable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case text(String)
    case list([SettingValue])

    /// The value as JSON data, for the body of a write.
    var json: Any {
        switch self {
        case .bool(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .text(let value): return value
        case .list(let items): return items.map { $0.json }
        }
    }
}

/// One setting of the server as its contract describes it.
public struct Setting: Equatable, Sendable {
    public let key: String
    public let group: String
    public let type: String
    public let defaultValue: SettingValue?
    public let apply: String
    public let write: SettingWrite
    public let role: String?
    public let scope: String?
    public let confirmWhenLooser: Bool
    public let secret: Bool
    public let risk: String
    public let min: Int?
    public let max: Int?
    public let unit: String?
    public let maxLength: Int?
    public let format: String?
    public let choices: [String]
    public let label: [String: String]
    public let help: [String: String]
    public let warning: [String: String]
}

public struct ContractGroup: Equatable, Sendable {
    public let id: String
    public let label: [String: String]
}

public struct SettingsContract: Equatable, Sendable {
    public let schema: String
    public let languages: [String]
    public let groups: [ContractGroup]
    public let settings: [Setting]
}

/// The contract as the page holds it: where it came from, the values in force (none for the copy) and why the live one was not used (a code of the server, `unreachable`, `shape`); nil for a live one.
public struct LoadedContract: Equatable, Sendable {
    public let contract: SettingsContract
    public let live: Bool
    public let values: [String: SettingValue]
    public let serverVersion: String?
    public let why: String?
}

/// One group of the page: its id, its label and its settings in the order of the contract.
public struct SettingsGroup: Equatable, Sendable {
    public let id: String
    public let label: [String: String]
    public let settings: [Setting]
}

/// The kind of control a setting is drawn with. Everything the page does not know how to edit is `generic`: a read-only line with the value as the server gives it.
public enum ControlKind: Equatable, Sendable { case toggle, number, text, select, list, generic }

/// What is wrong with what a person typed, before anything is sent.
public enum SettingProblem: Equatable, Sendable { case number, text, choice }

/// What a person typed for a setting: the value to send, or what the app found wrong.
public enum Typed: Equatable, Sendable {
    case ok(SettingValue)
    case bad(SettingProblem)
}

/// What became of a change that was sent.
public enum SaveResult: Equatable, Sendable {
    /// The server took it; `restartRequired` says it is read when the server starts.
    case saved(restartRequired: Bool)
    /// The value is looser than recommended: ask the person again and send it with `confirm_weak`.
    case needsWeakConfirm
    /// The server refused or could not be reached.
    case refused(ApiError)
}

private func word(_ json: [String: Any], _ key: String) -> String? { json[key] as? String }

private func whole(_ json: [String: Any], _ key: String) -> Int? {
    guard let number = json[key] as? NSNumber, String(cString: number.objCType) != "c" else { return nil }
    return number.intValue
}

private func texts(_ any: Any?) -> [String: String] { ((any as? [String: Any]) ?? [:]).compactMapValues { $0 as? String } }

/// A JSON value as plain data; nil for null.
func plainValue(_ any: Any?) -> SettingValue? {
    guard let any, !(any is NSNull) else { return nil }
    if let text = any as? String { return .text(text) }
    if let number = any as? NSNumber {
        if String(cString: number.objCType) == "c" { return .bool(number.boolValue) }
        let value = number.doubleValue
        if value == value.rounded(), abs(value) < 1e15 { return .int(Int(value)) }
        return .double(value)
    }
    if let items = any as? [Any] { return .list(items.compactMap { plainValue($0) }) }
    return .text(String(describing: any))
}

private func parseSetting(_ o: [String: Any]) -> Setting? {
    guard let key = word(o, "key"), !key.isEmpty, let write = o["write"] as? [String: Any] else { return nil }
    let choices = ((o["values"] as? [Any]) ?? []).map { String(describing: $0) }
    return Setting(
        key: key, group: word(o, "group") ?? "", type: word(o, "type") ?? "", defaultValue: plainValue(o["default"]), apply: word(o, "apply") ?? "restart",
        write: SettingWrite(via: word(write, "via") ?? "", method: word(write, "method"), path: word(write, "path"), file: word(write, "file")),
        role: word(o, "role"), scope: word(o, "scope"), confirmWhenLooser: (o["confirm_when_looser"] as? Bool) ?? false, secret: (o["secret"] as? Bool) ?? false,
        risk: word(o, "risk") ?? "none", min: whole(o, "min"), max: whole(o, "max"), unit: word(o, "unit"), maxLength: whole(o, "max_length"), format: word(o, "format"), choices: choices,
        label: texts(o["label"]), help: texts(o["help"]), warning: texts(o["warning"]))
}

private func rootOf(_ text: String) -> [String: Any]? {
    guard let data = text.data(using: .utf8), let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
    return root
}

/// The contract in a JSON text, or nil when it is not a contract the app can draw: another schema, no groups or settings, or a setting with no key or no `write`.
public func parseContract(_ text: String) -> SettingsContract? {
    guard let root = rootOf(text), word(root, "schema") == contractSchema, let groups = root["groups"] as? [Any], let settings = root["settings"] as? [Any] else { return nil }
    var parsed: [Setting] = []
    for item in settings {
        guard let object = item as? [String: Any], let setting = parseSetting(object) else { return nil }
        parsed.append(setting)
    }
    let listed: [ContractGroup] = groups.compactMap { item in
        guard let object = item as? [String: Any], let id = word(object, "id") else { return nil }
        return ContractGroup(id: id, label: texts(object["label"]))
    }
    return SettingsContract(schema: contractSchema, languages: (root["languages"] as? [String]) ?? [], groups: listed, settings: parsed)
}

/// The answer of `GET /api/v1/settings/contract`: the contract with the values in force and the version of the server; nil when it is not a contract.
public func parseLiveContract(_ text: String) -> LoadedContract? {
    guard let contract = parseContract(text), let root = rootOf(text) else { return nil }
    var values: [String: SettingValue] = [:]
    for (key, value) in (root["values"] as? [String: Any]) ?? [:] { if let plain = plainValue(value) { values[key] = plain } }
    return LoadedContract(contract: contract, live: true, values: values, serverVersion: word(root, "server_version"), why: nil)
}

/// The contract the page uses: the live one when the server gives it and the app understands it; otherwise the copy kept in the app (read-only, without values) and the reason.
/// `read` is the request, so a test can stand in for the server.
public func loadContract(read: () async throws -> String, embedded: SettingsContract) async -> LoadedContract {
    do {
        if let live = parseLiveContract(try await read()) { return live }
        return LoadedContract(contract: embedded, live: false, values: [:], serverVersion: nil, why: "shape")
    } catch let error as ApiError {
        return LoadedContract(contract: embedded, live: false, values: [:], serverVersion: nil, why: error.code)
    } catch {
        return LoadedContract(contract: embedded, live: false, values: [:], serverVersion: nil, why: "unreachable")
    }
}

private func filled(_ text: String?) -> String? {
    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return text
}

/// The text of a field of the contract in the language of the person: the language itself, its main language (`pt-br` reads `pt`), English, then any text there is.
public func contractText(_ map: [String: String], _ language: String) -> String {
    let full = language.lowercased()
    let base = full.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? full
    for key in [full, base, "en"] { if let text = filled(map[key]) { return text } }
    return map.keys.sorted().compactMap { filled(map[$0]) }.first ?? ""
}

/// The groups of the page, in the order of the contract. A setting whose group the contract does not list (a newer server) goes into a group made from its id, after the others: nothing is hidden.
public func groupSettings(_ contract: SettingsContract) -> [SettingsGroup] {
    var order = contract.groups.map { $0.id }
    var labels = Dictionary(contract.groups.map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
    for setting in contract.settings where !order.contains(setting.group) {
        order.append(setting.group)
        labels[setting.group] = ["en": setting.group]
    }
    return order.map { id in SettingsGroup(id: id, label: labels[id] ?? [:], settings: contract.settings.filter { $0.group == id }) }.filter { !$0.settings.isEmpty }
}

/// A setting made for a key nobody described: no label but its name, nothing the person may change.
public func genericSetting(_ key: String, _ value: SettingValue?) -> Setting {
    var type = "unknown"
    switch value {
    case .bool?: type = "boolean"
    case .int?: type = "integer"
    default: break
    }
    return Setting(
        key: key, group: "other", type: type, defaultValue: nil, apply: "restart", write: SettingWrite(via: "none", method: nil, path: nil, file: nil), role: nil, scope: nil,
        confirmWhenLooser: false, secret: false, risk: "none", min: nil, max: nil, unit: nil, maxLength: nil, format: nil, choices: [], label: ["en": key], help: [:], warning: [:])
}

/// The keys the server reports a value for and the contract does not list (a key newer than both the contract and the copy of the app): drawn read-only, so nothing the server holds is hidden.
public func unlistedSettings(_ contract: SettingsContract, _ values: [String: SettingValue]) -> [Setting] {
    let known = Set(contract.settings.map { $0.key })
    return values.keys.filter { !known.contains($0) }.sorted().map { genericSetting($0, values[$0]) }
}

public func controlKind(_ s: Setting) -> ControlKind {
    switch s.type {
    case "boolean": return .toggle
    case "integer": return s.min != nil && s.max != nil ? .number : .text
    case "string": return .text
    case "enum": return s.choices.isEmpty ? .text : .select
    case "list": return .list
    default: return .generic
    }
}

/// Whether a change of this setting needs the second touch: its risk is one that can open the server, weaken the security or touch a machine or data.
public func isHighRisk(_ s: Setting) -> Bool { s.risk == "security" || s.risk == "exposure" || s.risk == "machine" || s.risk == "data" }

private let roleRank = ["viewer": 0, "operator": 1, "admin": 2]

/// Whether a role is at least the one the contract asks for (an unknown role asked for is never reached).
public func roleAtLeast(_ have: String, _ need: String) -> Bool { (roleRank[have] ?? -1) >= (roleRank[need] ?? Int.max) }

/// Whether this role may change the setting through the API: the contract names a route for it, it is no secret and the role is enough. The scope of a token is the server's to check.
public func canWriteSetting(role: String, _ s: Setting) -> Bool {
    if s.secret || s.write.via != "policy" || (s.write.method ?? "").isEmpty || (s.write.path ?? "").isEmpty { return false }
    if let needed = s.role, !roleAtLeast(role, needed) { return false }
    return controlKind(s) != .generic
}

/// The route of the contract without the `/api/v1` that the client adds.
public func writePath(_ s: Setting) -> String {
    let path = s.write.path ?? ""
    return path.hasPrefix("/api/v1") ? String(path.dropFirst("/api/v1".count)) : path
}

/// The value of a setting as it is in force: the live value, else nothing (a copy of the contract knows no values). A secret has none.
public func valueOf(_ s: Setting, _ values: [String: SettingValue]) -> SettingValue? { s.secret ? nil : values[s.key] }

/// A value as a line of text: empty for nothing, `a, b` for a list and the plain text otherwise.
public func shownValue(_ v: SettingValue?) -> String {
    guard let v else { return "" }
    switch v {
    case .bool(let value): return value ? "true" : "false"
    case .int(let value): return String(value)
    case .double(let value): return String(value)
    case .text(let value): return value
    case .list(let items): return items.map { shownValue($0) }.joined(separator: ", ")
    }
}

/// Whether the person can bring the setting back to its default: it is editable, has a value that is not the default and the contract gives a default.
public func canRestore(editable: Bool, _ s: Setting, current: SettingValue?) -> Bool {
    guard editable, !s.secret, let current, let fallback = s.defaultValue else { return false }
    return current != fallback
}

private func wholeNumber(_ input: String) -> Int? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let digits = trimmed.hasPrefix("-") ? String(trimmed.dropFirst()) : trimmed
    guard (1...15).contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
    return Int(trimmed)
}

/// Checks what was typed against the contract before anything is sent: the type, the range of a number, the length of a text and the choices of an enum.
public func parseTyped(_ s: Setting, _ input: String) -> Typed {
    switch controlKind(s) {
    case .number:
        guard let n = wholeNumber(input), n >= (s.min ?? Int.min), n <= (s.max ?? Int.max) else { return .bad(.number) }
        return .ok(.int(n))
    case .text:
        if s.type == "integer" {
            guard let n = wholeNumber(input) else { return .bad(.number) }
            return .ok(.int(n))
        }
        if let limit = s.maxLength, input.utf16.count > limit { return .bad(.text) }
        return .ok(.text(input))
    case .select:
        guard let choice = s.choices.first(where: { $0 == input }) else { return .bad(.choice) }
        return .ok(.text(choice))
    case .list:
        let items = input.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return .ok(.list(items.map { .text($0) }))
    default:
        return .bad(.text)
    }
}

/// The body of the write of a setting (`PUT /auth/policy`); a value looser than recommended is sent with `confirm_weak`. The members are in alphabetical order.
public func writeBody(_ s: Setting, _ value: SettingValue, confirmWeak: Bool) -> String {
    var body: [String: Any] = ["key": s.key, "value": value.json]
    if confirmWeak { body["confirm_weak"] = true }
    let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
    return String(decoding: data, as: UTF8.self)
}

/// Whether the answer of a write says the key is read when the server starts; without a `changed` the contract's own `apply` decides.
public func restartRequired(_ answer: String, _ s: Setting) -> Bool {
    if let changed = rootOf(answer)?["changed"] as? [String: Any], let flag = changed["restart_required"] as? NSNumber { return flag.boolValue }
    return s.apply == "restart"
}

/// Sends one change by the method and the route that the entry of the contract names. `send` makes the request (method, path without `/api/v1`, body) and answers the text of the reply.
/// The server asking for `confirm_weak` is `.needsWeakConfirm`; any other refusal is `.refused` with the error as it came. A setting the API does not write is a mistake of the caller and throws.
public func saveSetting(send: (String, String, String) async throws -> String, _ s: Setting, value: SettingValue, confirmWeak: Bool) async throws -> SaveResult {
    guard canWriteSetting(role: "admin", s) else { throw ApiError(status: 0, code: "not_writable", detail: "\(s.key) is not written through the API") }
    do {
        let answer = try await send((s.write.method ?? "PUT").uppercased(), writePath(s), writeBody(s, value, confirmWeak: confirmWeak))
        return .saved(restartRequired: restartRequired(answer, s))
    } catch let error as ApiError {
        return error.code == "weak_confirm_required" ? .needsWeakConfirm : .refused(error)
    }
}

/// The texts of the page of the settings in the eight languages (Resources/settings-texts.json): `{"key": {"en": "...", "es": "...", ...}}`. A language the table does not have shows the English text.
public enum SettingsTexts {
    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var rows: [String: [String: String]] = [:]
        func get() -> [String: [String: String]] { lock.lock(); defer { lock.unlock() }; return rows }
        func set(_ value: [String: [String: String]]) { lock.lock(); defer { lock.unlock() }; rows = value }
    }

    private static let store = Store()

    /// True once a table has been installed.
    public static var loaded: Bool { !store.get().isEmpty }

    public static func parse(_ json: String) throws -> [String: [String: String]] {
        guard let root = rootOf(json) else { throw ApiError(status: 0, code: "bad_json", detail: "not a JSON object") }
        return root.mapValues { texts($0) }
    }

    /// Puts a table in place (the tests do it without a bundle); a text that is not a table throws and leaves the one that was there.
    public static func install(_ json: String) throws { store.set(try parse(json)) }

    /// Loads the table once with `read`; a table that cannot be read leaves the page with the key as its text.
    public static func ensureLoaded(_ read: () throws -> String) {
        if loaded { return }
        if let text = try? read() { try? install(text) }
    }

    /// The table shipped inside the package.
    public static func bundledText() throws -> String {
        guard let url = Bundle.module.url(forResource: "settings-texts", withExtension: "json") else { throw ApiError(status: 0, code: "missing_table", detail: "settings-texts.json") }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Loads the table of the package once.
    public static func ensureBundled() { ensureLoaded(bundledText) }

    public static func keys() -> Set<String> { Set(store.get().keys) }

    /// The text of `key` in `language`, with `{name}` holes filled from `vars`; the key itself when the table does not have it.
    public static func text(_ key: String, language: String, vars: [String: Any] = [:]) -> String {
        var out = store.get()[key].map { contractText($0, language) } ?? ""
        if out.isEmpty { out = key }
        for (name, value) in vars { out = out.replacingOccurrences(of: "{\(name)}", with: String(describing: value)) }
        return out
    }
}

/// The copy of the contract that the app carries (Resources/settings-contract.json); the page uses it when the live one cannot be read.
public enum EmbeddedContract {
    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var copy: SettingsContract?
        func get() -> SettingsContract? { lock.lock(); defer { lock.unlock() }; return copy }
        func set(_ value: SettingsContract?) { lock.lock(); defer { lock.unlock() }; copy = value }
    }

    private static let store = Store()

    public static var loaded: Bool { store.get() != nil }

    public static func install(_ json: String) { store.set(parseContract(json)) }

    public static func ensureLoaded(_ read: () throws -> String) {
        if loaded { return }
        if let text = try? read() { install(text) }
    }

    /// The copy shipped inside the package.
    public static func bundledText() throws -> String {
        guard let url = Bundle.module.url(forResource: "settings-contract", withExtension: "json") else { throw ApiError(status: 0, code: "missing_table", detail: "settings-contract.json") }
        return try String(contentsOf: url, encoding: .utf8)
    }

    public static func ensureBundled() { ensureLoaded(bundledText) }

    /// The copy, or an empty contract when it could not be read: the page then shows nothing but says why.
    public static func get() -> SettingsContract { store.get() ?? SettingsContract(schema: contractSchema, languages: contractLanguages, groups: [], settings: []) }
}
