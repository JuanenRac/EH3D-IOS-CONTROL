// EH3D-IOS-CONTROL - the state of the app: who is signed in, the fleet as the server reports it, the job and the head of the machine that is open, and what the buttons do (the same as the Android app).
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation
import SwiftUI
import UserNotifications
import Eh3dCore

enum Page: Hashable {
    case home, jobs, more, help, about, languages
    case machine(String)
    case job(String)
}

enum Phase { case booting, signedOut, firstSetup, signedIn }

@MainActor
final class AppModel: ObservableObject {
    @Published var phase: Phase = .booting
    @Published var busy = false
    @Published var origin: String
    @Published var login: Login?
    @Published var fleet: Fleet = .empty
    @Published var offline = false
    @Published var message: String?
    @Published var rememberMe = false
    @Published var jobs: [JobSummary] = []
    @Published var job: Job?
    @Published var head: HeadStatus?
    @Published var noHead = false
    @Published var measure: Measure?
    @Published var stack: [Page] = []
    @Published var language: String

    let translator: Translator
    private let prefs = PreferencesStore()
    private let vault: SessionVault
    private var api: Eh3dApi
    private var poller: Task<Void, Never>?
    private var visible = true
    private var lastStates: [String: String] = [:]

    var page: Page { stack.last ?? .home }
    var canOperate: Bool { Roles.canOperate(login?.role ?? "") }
    func tr(_ s: String) -> String { _ = language; return translator.tr(s) }
    func trf(_ s: String, _ args: Any...) -> String { _ = language; return Translator.fill(translator.tr(s), args) }

    init() {
        let saved = prefs.get("language")
        let chosen = Translator.pick(saved: saved, phone: Locale.current.language.languageCode?.identifier ?? "en")
        translator = Translator(language: chosen)
        language = chosen
        origin = prefs.get("origin") ?? ""
        vault = SessionVault(secrets: KeychainSecrets(), prefs: prefs)
        api = Eh3dApi(origin: prefs.get("origin") ?? "")
        rememberMe = vault.rememberedLogin(origin: origin) != nil
        Task { await start() }
    }

    func savedUser() -> String { vault.rememberedLogin(origin: origin)?.username ?? "" }
    func savedPassword() -> String { vault.rememberedLogin(origin: origin)?.password ?? "" }

    private func start() async {
        if origin.isEmpty { phase = .signedOut; return }
        api = Eh3dApi(origin: origin)
        if let kept = vault.loadSession(origin: origin) {
            api.token = kept.value
            if let me = try? await api.session() { login = me; phase = .signedIn; poll(); return }
            vault.dropSession(); api.token = ""
        }
        if let saved = vault.rememberedLogin(origin: origin) {
            if (try? await doSignIn(origin: origin, name: saved.username, password: saved.password, remember: true)) != nil { return }
        }
        phase = .signedOut
    }

    func connect(host: String, port: String) {
        guard let endpoint = ServerEndpoint.fromHostAndPort(host, port) else { message = tr("La dirección del servidor no es válida (use una dirección de la red local o https://)."); return }
        Task {
            busy = true; defer { busy = false }
            do {
                let probe = Eh3dApi(origin: endpoint.origin)
                let needed = try await probe.setupNeeded()
                api = probe; origin = endpoint.origin; prefs.put("origin", origin)
                phase = needed ? .firstSetup : .signedOut
                message = nil
            } catch let e as ApiError { message = text(e) } catch { message = error.localizedDescription }
        }
    }

    func firstSetup(code: String, name: String, password: String) {
        Task {
            busy = true; defer { busy = false }
            do { try await api.setup(code: code.trimmingCharacters(in: .whitespaces), name: name.trimmingCharacters(in: .whitespaces), password: password); _ = try await doSignIn(origin: origin, name: name, password: password, remember: false) }
            catch let e as ApiError { message = text(e) } catch { message = error.localizedDescription }
        }
    }

    func signIn(origin address: String, name: String, password: String, remember: Bool) {
        Task {
            busy = true; defer { busy = false }
            do { _ = try await doSignIn(origin: address, name: name, password: password, remember: remember) }
            catch let e as ApiError { message = text(e) } catch { message = error.localizedDescription }
        }
    }

    private func doSignIn(origin address: String, name: String, password: String, remember: Bool) async throws -> Login {
        if api.token.isEmpty && origin != address { api = Eh3dApi(origin: address); origin = address }
        let result = try await api.login(name: name.trimmingCharacters(in: .whitespaces), password: password)
        api.token = result.token
        login = result
        vault.saveSession(SessionCookie(name: "token", value: result.token), origin: origin)
        if remember { vault.rememberLogin(origin: origin, username: name, password: password) } else { vault.forgetLogin() }
        rememberMe = remember
        prefs.put("origin", origin)
        message = nil
        stack = []
        phase = .signedIn
        poll()
        return result
    }

    func signOut() {
        poller?.cancel()
        let a = api
        Task { await a.logout() }
        vault.forgetAll()
        rememberMe = false
        api.token = ""
        login = nil; fleet = .empty; job = nil; head = nil; jobs = []; stack = []
        phase = .signedOut
    }

    func dismissMessage() { message = nil }
    func setVisible(_ value: Bool) { visible = value; if value && phase == .signedIn { poll() } }

    // ---- the pages
    func open(_ page: Page) {
        if page == self.page { return }
        stack.append(page)
        job = nil; head = nil; measure = nil; noHead = false
        refreshNow()
    }

    func tab(_ page: Page) { stack = page == .home ? [] : [page]; job = nil; head = nil; refreshNow() }

    func back() { if !stack.isEmpty { stack.removeLast(); job = nil; head = nil; measure = nil; noHead = false; refreshNow() } }

    // ---- the watch: the fleet every second and a half while the app is in sight
    private func poll() {
        poller?.cancel()
        poller = Task { [weak self] in
            while let self, self.phase == .signedIn, !Task.isCancelled {
                if self.visible { await self.refresh() }
                try? await Task.sleep(nanoseconds: self.visible ? 1_500_000_000 : 10_000_000_000)
            }
        }
    }

    private func refreshNow() { if phase == .signedIn { Task { await refresh() } } }

    private func refresh() async {
        do {
            let now = try await api.fleet()
            raise(now)
            fleet = now
            offline = false
            switch page {
            case .machine(let id):
                if let active = now.machine(id)?.job { job = try await api.job(active.id) } else if job?.summary.machine != id { job = nil }
                if !noHead {
                    do { head = try await api.head(id) } catch let e as ApiError where e.code == "no_head" { noHead = true; head = nil } catch {}
                }
                jobs = try await api.jobs(machine: id)
            case .job(let id): job = try await api.job(id)
            case .jobs: jobs = try await api.jobs()
            default: break
            }
        } catch let e as ApiError {
            if e.unauthorized { vault.dropSession(); api.token = ""; login = nil; phase = .signedOut; poller?.cancel() } else { offline = true }
        } catch { offline = true }
    }

    /// A machine that stops, finishes or waits for the operator is told in a notice, once.
    private func raise(_ now: Fleet) {
        var current: [String: String] = [:]
        for m in now.machines { current[m.id] = m.job?.state ?? m.state }
        if !lastStates.isEmpty {
            for m in now.machines {
                guard let before = lastStates[m.id], let after = current[m.id], before != after else { continue }
                if after == "waiting_operator" { notify(m.name, tr("Espera al operario: confirme el paso en la máquina.")) }
                if m.job == nil && JobStates.active(before) { notify(m.name, tr("El trabajo ha terminado o se ha detenido.")) }
            }
        }
        lastStates = current
    }

    private func notify(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // ---- what the buttons do
    private func act(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work(); await refresh() }
            catch let e as ApiError { if e.unauthorized { signOut() } else { message = text(e) } } catch { message = error.localizedDescription }
        }
    }

    func start(_ id: String) { act { try await self.api.start(id) } }
    func confirm(_ id: String) { act { try await self.api.confirm(id) } }
    func cancel(_ id: String) { act { try await self.api.cancel(id) } }
    func delete(_ id: String) { act { try await self.api.delete(id); if case .job = self.page { self.back() } } }

    /// The emergency stop of one machine: its running job is cancelled, which stops the machine and switches the drivers off.
    func emergencyStop(_ machineId: String) { if let id = fleet.machine(machineId)?.job?.id { cancel(id) } }
    func emergencyStopAll() { for id in fleet.machines.compactMap({ $0.job?.id }) { cancel(id) } }
    func measureTable(_ machineId: String) { act { self.measure = try await self.api.measure(machineId) } }
    func streamURL(_ machineId: String) -> URL? { api.streamURL(machineId) }

    func choose(language code: String) { translator.select(code); language = translator.language; prefs.put("language", code) }

    func requestNotices() { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }

    private func text(_ e: ApiError) -> String {
        if e.status == 0 { return tr("No se alcanza el servidor. Compruebe la dirección y que el teléfono está en la misma red.") }
        if e.code == "invalid_credentials" || e.status == 401 { return tr("Usuario o contraseña incorrectos.") }
        if e.code == "throttled" { return tr("Demasiados intentos: espere un momento.") }
        if e.code == "machine_busy" { return tr("La máquina ya está trabajando.") }
        if e.code == "no_head" { return tr("Esta máquina no tiene nodo de cabezal.") }
        if e.status == 403 { return tr("Su usuario solo puede ver: no puede hacer esto.") }
        return trf("El servidor respondió: %s", e.detail.isEmpty ? e.code : e.detail)
    }
}
