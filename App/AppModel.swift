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
    /// The page that prepares a job on a machine: what to do, the file, its tools and where to start.
    case prepare(String)
}

/// What the page that prepares a job holds: the work chosen, the file of each side with what the server planned from it, and the free G-code program.
struct PrepareUi {
    var work: Work = .drill
    var drill = SideState(), route = SideState()
    var gcodeName = "", gcode = "", skip = 0
    /// Start the spindle and the coolant again when a program goes on after a stop: off unless the person turns it on.
    var restoreOutputs = false
    var gcodeView: JobView?
    var gcodeError = ""
    var loading = false, busy = false
    func side(_ side: Side) -> SideState { side == .drill ? drill : route }
    mutating func set(_ side: Side, _ state: SideState) { if side == .drill { drill = state } else { route = state } }
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
    /// The last quality check of the machine on screen, and whether one is running now.
    @Published var quality: Quality?
    @Published var qualityBusy = false
    private var qualityLooked = false
    /// The spindle of the machine on screen (nil until the server has answered).
    @Published var spindle: SpindleInfo?
    private var spindleLooked = false
    /// Whether the machine on screen lets its G-code jobs carry the `$` lines of GRBL (nil until the server has answered).
    @Published var dollarAllowed: Bool?
    /// The job being prepared, and the text of the G-code programs started from here (to go on from the line where one stopped without choosing the file again).
    @Published var prepare = PrepareUi()
    private var gcodeSources: [String: (name: String, text: String)] = [:]
    private var previewing: Task<Void, Never>?
    @Published var stack: [Page] = []
    @Published var language: String

    let translator: Translator
    private let prefs = PreferencesStore()
    private let vault: SessionVault
    private var api: Eh3dApi
    /// The certificate of an https server is judged by the system and by the pin kept the first time (or paired from Studio); plain http to the local network never gets here.
    private let trust: TrustDelegate
    private let pinnedSession: URLSession
    private var poller: Task<Void, Never>?
    private var visible = true
    private var lastStates: [String: String] = [:]

    var page: Page { stack.last ?? .home }
    var canOperate: Bool { Roles.canOperate(login?.role ?? "") }
    var canAdmin: Bool { Roles.canAdmin(login?.role ?? "") }
    func tr(_ s: String) -> String { _ = language; return translator.tr(s) }
    func trf(_ s: String, _ args: Any...) -> String { _ = language; return Translator.fill(translator.tr(s), args) }

    init() {
        let saved = prefs.get("language")
        let chosen = Translator.pick(saved: saved, phone: Locale.current.language.languageCode?.identifier ?? "en")
        translator = Translator(language: chosen)
        language = chosen
        origin = prefs.get("origin") ?? ""
        vault = SessionVault(secrets: KeychainSecrets(), prefs: prefs)
        let delegate = TrustDelegate(pins: PinStore(prefs))
        trust = delegate
        pinnedSession = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        api = Eh3dApi(origin: prefs.get("origin") ?? "", session: pinnedSession)
        rememberMe = vault.rememberedLogin(origin: origin) != nil
        Task { await start() }
    }

    func savedUser() -> String { vault.rememberedLogin(origin: origin)?.username ?? "" }
    func savedPassword() -> String { vault.rememberedLogin(origin: origin)?.password ?? "" }

    private func start() async {
        if origin.isEmpty { phase = .signedOut; return }
        api = Eh3dApi(origin: origin, session: pinnedSession)
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
                let probe = Eh3dApi(origin: endpoint.origin, session: pinnedSession)
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
        if api.token.isEmpty && origin != address { api = Eh3dApi(origin: address, session: pinnedSession); origin = address }
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
        // the call that ends the session goes with the token that is being closed, not with the empty one set just below
        let closing = Eh3dApi(origin: origin, token: api.token, session: pinnedSession)
        Task { await closing.logout() }
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
        job = nil; head = nil; measure = nil; quality = nil; qualityLooked = false; spindle = nil; spindleLooked = false; dollarAllowed = nil; noHead = false
        refreshNow()
    }

    func tab(_ page: Page) { stack = page == .home ? [] : [page]; job = nil; head = nil; refreshNow() }

    func back() { if !stack.isEmpty { stack.removeLast(); job = nil; head = nil; measure = nil; quality = nil; qualityLooked = false; spindle = nil; spindleLooked = false; dollarAllowed = nil; noHead = false; refreshNow() } }

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
                // every answer is kept only if the page is still this machine: a slow refresh of another one must not paint its data here
                let here = page
                if let active = now.machine(id)?.job { let j = try await api.job(active.id); if page == here { job = j } } else if job?.summary.machine != id { job = nil }
                if !noHead && !qualityLooked && !qualityBusy { let q = try? await api.lastInspection(id); if page == here { qualityLooked = true; quality = q } }
                if !spindleLooked {
                    var s: SpindleInfo? = nil
                    var d: Bool? = nil
                    do { s = try await api.spindle(id) } catch let e as ApiError where e.unauthorized { throw e } catch { s = nil }
                    do { d = try await api.allowDollar(id) } catch let e as ApiError where e.unauthorized { throw e } catch { d = nil }
                    if page == here { spindleLooked = true; spindle = s; dollarAllowed = d }
                }
                if !noHead {
                    do { let h = try await api.head(id); if page == here { head = h } } catch let e as ApiError where e.code == "no_head" { if page == here { noHead = true; head = nil } } catch {}
                }
                let list = try await api.jobs(machine: id)
                if page == here { jobs = list }
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
    func pause(_ id: String) { act { try await self.api.pause(id) } }
    func resume(_ id: String) { act { try await self.api.resume(id) } }

    /// Goes on from a job that failed or was cancelled: the server made a new job from the request it kept (no file is asked for again), and it waits ready for a person to start it.
    func goOn(_ summary: JobSummary) {
        Task {
            do {
                let next = try await api.resumeFrom(summary.id)
                message = tr("Se creó un trabajo nuevo a partir de este. Empiécelo cuando la máquina esté lista.")
                await refresh()
                open(.job(next.summary.id))
            } catch let e as ApiError { if e.unauthorized { signOut() } else { message = text(e) } } catch { message = error.localizedDescription }
        }
    }

    // ---- preparing a job
    /// True when the text of the program that `id` ran is still known, so it can go on from its line without choosing the file again.
    func knowsProgram(_ id: String) -> Bool { gcodeSources[id] != nil }

    /// Opens the page that prepares a job on a machine, with the first work its connection takes.
    func openPrepare(_ machineId: String) {
        open(.prepare(machineId))
        prepare = PrepareUi(work: Prepare.works(fleet.machine(machineId)?.connection ?? "").first ?? .drill)
    }

    /// Goes on with a G-code job that failed or was stopped: the same program from the line it says (the text is asked for again when this session does not have it).
    func openResume(_ summary: JobSummary) {
        let source = gcodeSources[summary.id]
        let text = source?.text ?? ""
        open(.prepare(summary.machine))
        prepare = PrepareUi(work: .gcode, gcodeName: source?.name ?? "", gcode: text, skip: Prepare.resumeSkip(line: summary.line, total: text.isEmpty ? summary.line : Prepare.lineCount(text)))
        if !text.isEmpty { previewGcode(summary.machine) }
    }

    func setWork(_ work: Work) { prepare.work = work }
    func setSkip(_ machineId: String, _ skip: Int) { prepare.skip = max(skip, 0); if !prepare.gcode.isEmpty { previewGcode(machineId) } }
    func setRestoreOutputs(_ value: Bool) { prepare.restoreOutputs = value }

    func toggleToolOff(_ side: Side, _ tool: Int) {
        var st = prepare.side(side)
        st.off = Prepare.toggleOff(st.off, tool: tool)
        if st.off.contains(tool) && st.startAt == tool { st.startAt = nil }
        prepare.set(side, st)
    }

    func toggleStartAt(_ side: Side, _ tool: Int) {
        var st = prepare.side(side)
        st.startAt = Prepare.toggleStartAt(current: st.startAt, tool: tool, off: st.off)
        prepare.set(side, st)
    }

    private func read(_ url: URL) throws -> (name: String, text: String) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        if data.count > Prepare.maxFileBytes { throw ApiError(status: 0, code: "too_big", detail: "too_big") }
        return (url.lastPathComponent, String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n"))
    }

    /// The file of drilling (`.NCD`) or routing (`.PLT`): it is read, sent to the server to plan (nothing is created) and the tools it uses come back with their count.
    func pickFile(_ machineId: String, _ side: Side, _ url: URL) {
        Task {
            prepare.loading = true; defer { prepare.loading = false }
            do {
                let picked = try read(url)
                let old = prepare.side(side)
                prepare.set(side, SideState(fileName: picked.name, text: picked.text, tableName: old.tableName, tableText: old.tableText))
                await planSide(machineId, side)
            } catch let e as ApiError { var st = prepare.side(side); st.error = prepareError(e); prepare.set(side, st) }
            catch { var st = prepare.side(side); st.error = tr("No se pudo leer el archivo."); prepare.set(side, st) }
        }
    }

    /// The tool table of a side (`.DTD` or `.RTD`), optional.
    func pickTable(_ machineId: String, _ side: Side, _ url: URL) {
        Task {
            prepare.loading = true; defer { prepare.loading = false }
            do {
                let picked = try read(url)
                var st = prepare.side(side)
                st.tableName = picked.name; st.tableText = picked.text
                prepare.set(side, st)
                if st.hasFile { await planSide(machineId, side) }
            } catch let e as ApiError { var st = prepare.side(side); st.error = prepareError(e); prepare.set(side, st) }
            catch { var st = prepare.side(side); st.error = tr("No se pudo leer el archivo."); prepare.set(side, st) }
        }
    }

    private func planSide(_ machineId: String, _ side: Side) async {
        let st = prepare.side(side)
        do {
            let view = try await api.preview(machineId, body: Prepare.fileBody(side: side, name: Prepare.jobName(st.fileName), text: st.text, tableText: st.tableText, skipTools: []))
            var now = prepare.side(side); now.view = view; now.error = ""; prepare.set(side, now)
        } catch let e as ApiError {
            if e.unauthorized { signOut() }
            var now = prepare.side(side); now.view = nil; now.error = prepareError(e); prepare.set(side, now)
        } catch { var now = prepare.side(side); now.view = nil; now.error = error.localizedDescription; prepare.set(side, now) }
    }

    /// The G-code program: its text is read and planned from the line `prepare.skip`.
    func pickProgram(_ machineId: String, _ url: URL) {
        Task {
            prepare.loading = true; defer { prepare.loading = false }
            do {
                let picked = try read(url)
                prepare.gcodeName = picked.name; prepare.gcode = picked.text; prepare.gcodeView = nil; prepare.gcodeError = ""
                previewGcode(machineId)
            } catch let e as ApiError { prepare.gcodeError = prepareError(e) }
            catch { prepare.gcodeError = tr("No se pudo leer el archivo.") }
        }
    }

    private func previewGcode(_ machineId: String) {
        previewing?.cancel()
        let p = prepare
        previewing = Task {
            do {
                let view = try await api.preview(machineId, body: Prepare.gcodeBody(name: Prepare.jobName(p.gcodeName), gcode: p.gcode, skip: p.skip, restoreOutputs: p.restoreOutputs))
                if Task.isCancelled { return }
                prepare.gcodeView = view; prepare.gcodeError = ""
            } catch let e as ApiError {
                if Task.isCancelled { return }
                if e.unauthorized { signOut() }
                prepare.gcodeView = nil; prepare.gcodeError = prepareError(e)
            } catch {}
        }
    }

    /// Creates the job (or the two of a drilling and routing pair) with the tools switched off and the tool to start at, and starts the first one. The second stays ready: a job never starts by itself.
    func startPrepared(_ machineId: String) {
        let p = prepare
        if p.busy { return }
        Task {
            prepare.busy = true; defer { prepare.busy = false }
            var made = 0
            do {
                var jobs: [Job] = []
                if p.work == .gcode {
                    let job = try await api.createJob(machineId, body: Prepare.gcodeBody(name: Prepare.jobName(p.gcodeName), gcode: p.gcode, skip: p.skip, restoreOutputs: p.restoreOutputs))
                    gcodeSources[job.summary.id] = (p.gcodeName, p.gcode)
                    jobs.append(job); made += 1
                } else {
                    let sides: [Side] = p.work == .drill ? [.drill] : p.work == .route ? [.route] : [.drill, .route]
                    for side in sides {
                        let st = p.side(side)
                        let skipTools = Prepare.skipTools(order: st.view.map { Prepare.toolOrder($0) } ?? [], off: st.off, startAt: st.startAt)
                        jobs.append(try await api.createJob(machineId, body: Prepare.fileBody(side: side, name: Prepare.jobName(st.fileName), text: st.text, tableText: st.tableText, skipTools: skipTools)))
                        made += 1
                    }
                }
                try await api.start(jobs[0].summary.id)
                message = jobs.count > 1 ? tr("El primer trabajo está en marcha. El segundo queda listo: arránquelo desde la pestaña Trabajos cuando termine.") : nil
                if case .prepare = page { back() }
                await refresh()
            } catch let e as ApiError {
                if e.unauthorized { signOut() } else { message = prepareError(e) + (made > 0 ? " " + tr("Lo que ya se creó queda listo en la pestaña Trabajos.") : "") }
            } catch { message = error.localizedDescription }
        }
    }

    private func prepareError(_ e: ApiError) -> String {
        switch e.code {
        case "too_big": return tr("El archivo es demasiado grande.")
        case "bad_gcode": return trf("Hay una línea que no es G-code válido: %s", e.detail)
        case "bad_ncd": return tr("El archivo de taladrado no se entiende.")
        case "unknown_tool": return trf("Una herramienta del archivo no está en la tabla de herramientas de la máquina: %s", e.detail)
        case "bad_tool": return trf("Herramienta no válida: %s", e.detail)
        case "out_of_table": return tr("Un agujero o un punto queda fuera del recorrido de la máquina.")
        case "wrong_machine": return tr("Esta máquina no admite esa clase de trabajo.")
        default: return text(e)
        }
    }

    func measureTable(_ machineId: String) { act { self.measure = try await self.api.measure(machineId) } }
    func streamURL(_ machineId: String) -> URL? { api.streamURL(machineId) }

    /// The ring of LEDs around the camera of the drill head: off (0) or on at a level.
    func setLight(_ machineId: String, level: Int) { act { _ = try await self.api.setLight(machineId, level: level) } }

    /// The quality check of the work through the camera: the verdict comes back and stays on screen until the next one.
    func inspect(_ machineId: String, light: Int, holeMm: Double) {
        if qualityBusy { return }
        qualityBusy = true
        Task {
            do { quality = try await api.inspect(machineId, light: light, holeMm: holeMm); await refresh() }
            catch let e as ApiError { if e.unauthorized { signOut() } else { message = text(e) } } catch { message = error.localizedDescription }
            qualityBusy = false
        }
    }

    func inspectPreset(_ machineId: String, index: Int) { act { try await self.api.inspectPreset(machineId, index: index) } }
    func inspectCalibrate(_ machineId: String) { act { try await self.api.inspectCalibrate(machineId); self.quality = nil; self.qualityLooked = true } }

    /// Chooses the spindle of the machine (`original`, `vfd` or empty for none) and/or what the server does with a job that asks for more (`reject` or `warn`).
    func setSpindle(_ machineId: String, spindle: String?, guardMode: String?) { act { self.spindle = try await self.api.setSpindle(machineId, spindle: spindle, guardMode: guardMode) } }

    func choose(language code: String) { translator.select(code); language = translator.language; prefs.put("language", code) }

    func requestNotices() { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }

    private func text(_ e: ApiError) -> String {
        if e.status == 0 && trust.takeMismatch() { return tr("El certificado del servidor no es el que se guardó la primera vez: no se conecta.") }
        if e.status == 0 { return tr("No se alcanza el servidor. Compruebe la dirección y que el teléfono está en la misma red.") }
        if e.code == "bad_credentials" || e.code == "invalid_credentials" || e.status == 401 { return tr("Usuario o contraseña incorrectos.") }
        if e.code == "bad_setup" { return tr("El código de alta no es correcto.") }
        if e.code == "weak_password" { return tr("La contraseña debe tener de 8 a 128 caracteres.") }
        if e.code == "bad_name" { return tr("El nombre no es válido: letras, dígitos, punto, guion bajo y guion, hasta 32 caracteres.") }
        if e.code == "throttled" { return tr("Demasiados intentos: espere un momento.") }
        if e.code == "machine_busy" { return tr("La máquina ya está trabajando.") }
        if e.code == "no_head" { return tr("Esta máquina no tiene nodo de cabezal.") }
        if e.code == "no_light" { return tr("Este nodo no tiene aro de luz.") }
        if e.code == "no_inspection" { return tr("Verifica primero un agujero: la escala sale de su ancho.") }
        if e.code == "no_hole" { return tr("La última verificación no encontró ningún agujero con el que medir la escala.") }
        if e.code == "spindle_limit" { return tr("El trabajo pide más de lo que da el husillo de la máquina.") }
        if e.code == "bad_spindle" { return tr("Husillo o límites no válidos.") }
        if e.code == "not_pausable" { return tr("Solo se puede pausar un trabajo de G-code.") }
        if e.code == "not_in_state" { return tr("El trabajo ya no está en un estado que permita eso.") }
        if e.code == "not_stopped" { return tr("Solo se puede seguir desde un trabajo cancelado o fallido.") }
        if e.code == "no_work" { return tr("No queda nada por hacer: todas las herramientas están desactivadas o el trabajo ya está hecho.") }
        if e.code == "head_unreachable" { return tr("El nodo del cabezal no responde.") }
        if e.status == 403 { return tr("Su usuario solo puede ver: no puede hacer esto.") }
        return trf("El servidor respondió: %s", e.detail.isEmpty ? e.code : e.detail)
    }
}
