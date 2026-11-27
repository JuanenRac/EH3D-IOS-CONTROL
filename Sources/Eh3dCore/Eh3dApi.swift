// EH3D-IOS-CONTROL - the client of the API of EH3D-SERVER (docs/API.md of that project): URLSession with async/await, one request at a time, JSON read by the parsers of Models.swift.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

/// Who is signed in: the token (a login's or a program's), the name and the role (`viewer`, `operator` or `admin`); the id of the login and the seconds it lasts, when the server says them.
public struct Login: Equatable, Sendable {
    public let token: String
    public let name: String
    public let role: String
    public let sessionId: String
    public let expiresS: Int
    public init(token: String, name: String, role: String, sessionId: String = "", expiresS: Int = 0) {
        self.token = token; self.name = name; self.role = role; self.sessionId = sessionId; self.expiresS = expiresS
    }
}

/// The application this app says it logs in for (`POST /auth/login`): the server keeps it with the login and in the audit.
public let loginApp = "ios"

/// The client of the API. It follows the client of the suite (docs/SERVER_CLIENT.md of EH3D-COMMON): every try has `settings.timeoutS` seconds; after a failure on the network it waits 200 ms, 400 ms... and tries
/// again up to `retries` more times, and a POST is never sent twice (only a connection that could not be made is tried again for any method); a login that is in the last quarter of its life is renewed by itself
/// before the next request; a 401 makes it forget the token. `pause` and `clockMs` are the waiting and the clock, so the tests do not wait.
public final class Eh3dApi: @unchecked Sendable {
    private let origin: String
    public var token: String
    /// The time-out, the retries and the search on the network; the app changes them while it runs.
    public var settings: ConnectionSettings
    /// Whether a request renews a login that is in the last quarter of its life; the tests turn it off.
    public var autoRefresh = true
    private let urlSession: URLSession
    private let version: String
    private let pause: @Sendable (Int) async -> Void
    private let clockMs: @Sendable () -> Int64

    // How long the login lasts and when it ends (milliseconds of `clockMs`); 0 while the app does not know. Always touched through `lock`.
    private let lock = NSLock()
    private var lifeTotalS = 0
    private var expiresAtMs: Int64 = 0
    private var renewing = false

    public init(origin: String, token: String = "", settings: ConnectionSettings = ConnectionSettings(), session: URLSession = .shared, version: String = "0.0.1",
                pause: @escaping @Sendable (Int) async -> Void = { ms in _ = try? await Task.sleep(nanoseconds: UInt64(max(ms, 0)) * 1_000_000) },
                clockMs: @escaping @Sendable () -> Int64 = { Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000) }) {
        self.origin = origin.hasSuffix("/") ? String(origin.dropLast()) : origin
        self.token = token
        self.settings = settings
        self.urlSession = session
        self.version = version
        self.pause = pause
        self.clockMs = clockMs
    }

    /// Takes the life of a login the server has just told (`expires_s`), counted from now.
    private func adoptLife(_ expiresS: Int) {
        if expiresS <= 0 { return }
        let now = clockMs()
        lock.lock(); defer { lock.unlock() }
        if lifeTotalS <= 0 || expiresS > lifeTotalS { lifeTotalS = expiresS }
        expiresAtMs = now + Int64(expiresS) * 1000
    }

    private func forgetToken() {
        token = ""
        lock.lock(); defer { lock.unlock() }
        lifeTotalS = 0; expiresAtMs = 0
    }

    /// True when this call took the right to renew (a login in the last quarter of its life that nobody is renewing).
    private func beginRenewal() -> Bool {
        let now = clockMs()
        lock.lock(); defer { lock.unlock() }
        if renewing || !RefreshRule.due(totalS: lifeTotalS, leftS: Int((expiresAtMs - now) / 1000)) { return false }
        renewing = true
        return true
    }

    private func endRenewal() { lock.lock(); defer { lock.unlock() }; renewing = false }

    private func request(_ path: String, method: String, body: String?) throws -> URLRequest {
        guard let url = URL(string: origin + "/api/v1" + path) else { throw ApiError(status: 0, code: "bad_address", detail: path) }
        var r = URLRequest(url: url, timeoutInterval: TimeInterval(settings.timeoutS))
        r.httpMethod = method
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("EH3D-IOS-CONTROL/\(version)", forHTTPHeaderField: "User-Agent")
        if !token.isEmpty { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            r.httpBody = body.data(using: .utf8)
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    /// The failures of the system that say the connection was never made, so nothing of the request went out and any method may be tried again.
    static func neverSent(_ code: URLError.Code) -> Bool {
        switch code {
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet: return true
        default: return false
        }
    }

    /// One try.
    private func once(_ path: String, method: String, body: String?) async throws -> String {
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await urlSession.data(for: request(path, method: method, body: body)) }
        catch let error as ApiError { throw error }
        catch let error as URLError { throw ApiError(status: 0, code: "unreachable", detail: error.localizedDescription, neverSent: Eh3dApi.neverSent(error.code)) }
        catch { throw ApiError(status: 0, code: "unreachable", detail: error.localizedDescription) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8) ?? ""
        if !(200...299).contains(status) {
            let e = describeError(status: status, body: text)
            // the server refused the login: the token is forgotten here, and nothing else asks with it (the person signs in again)
            if status == 401 && !token.isEmpty && !path.hasSuffix("/login") { forgetToken() }
            throw ApiError(status: status, code: e.code, detail: e.detail.isEmpty ? e.code : e.detail)
        }
        return text
    }

    /// One try of the light view of the settings: `If-None-Match` carries the ETag of the last answer, a `304` is `.notModified`, and an answer longer than `lightMaxBytes` is never read to the end (it ends as
    /// the error `download_too_big`). The text is not checked here: the model reads it whole or refuses it. The cache of the system is not used: the tag is kept by the app.
    private func onceLight(etag: String?) async throws -> LightReply {
        var r = try request(lightPath, method: "GET", body: nil)
        r.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag { r.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do { (bytes, response) = try await urlSession.bytes(for: r) }
        catch let error as ApiError { throw error }
        catch let error as URLError { throw ApiError(status: 0, code: "unreachable", detail: error.localizedDescription, neverSent: Eh3dApi.neverSent(error.code)) }
        catch { throw ApiError(status: 0, code: "unreachable", detail: error.localizedDescription) }
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        if status == 304 { return .notModified }
        if !(200...299).contains(status) {
            var body = Data()
            do { for try await byte in bytes { body.append(byte); if body.count >= 4096 { break } } } catch {}
            let e = describeError(status: status, body: String(data: body, encoding: .utf8) ?? "")
            if status == 401 && !token.isEmpty { forgetToken() }
            throw ApiError(status: status, code: e.code, detail: e.detail.isEmpty ? e.code : e.detail)
        }
        if response.expectedContentLength > Int64(lightMaxBytes) { throw ApiError(status: status, code: "download_too_big", detail: "the answer is longer than \(lightMaxBytes) bytes") }
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > lightMaxBytes { throw ApiError(status: status, code: "download_too_big", detail: "the answer is longer than \(lightMaxBytes) bytes") }
            }
        }
        catch let error as ApiError { throw error }
        catch { throw ApiError(status: 0, code: "unreachable", detail: error.localizedDescription) }
        return .fresh(text: String(data: data, encoding: .utf8) ?? "", etag: http?.value(forHTTPHeaderField: "ETag"))
    }

    /// Renews the login first when it is in the last quarter of its life; a failure here is left to the request itself to find out.
    private func renewIfDue(_ path: String) async {
        if !autoRefresh || token.isEmpty || path.hasPrefix("/auth/") || path.hasSuffix("/login") { return }
        if !beginRenewal() { return }
        _ = try? await refresh()
        endRenewal()
    }

    private func call(_ path: String, method: String = "GET", body: String? = nil) async throws -> String {
        await renewIfDue(path)
        var retry = 0
        while true {
            do { return try await once(path, method: method, body: body) }
            catch let error as ApiError {
                if Task.isCancelled || retry >= settings.retries || !RetryRules.mayRepeat(method: method, status: error.status, neverSent: error.neverSent) { throw error }
                await pause(RetryRules.delayMs(retry))
                retry += 1
            }
        }
    }

    private func json(_ pairs: [String: String]) -> String {
        (try? JSONSerialization.data(withJSONObject: pairs)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    private func q(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#/?"))) ?? s }

    public func health() async throws -> String {
        let j = try JSONSerialization.jsonObject(with: Data(try await call("/health").utf8)) as? [String: Any]
        return (j?["version"] as? String) ?? ""
    }

    public func setupNeeded() async throws -> Bool {
        let j = try JSONSerialization.jsonObject(with: Data(try await call("/setup").utf8)) as? [String: Any]
        return (j?["needed"] as? Bool) ?? false
    }

    public func setup(code: String, name: String, password: String) async throws { _ = try await call("/setup", method: "POST", body: json(["code": code, "name": name, "password": password])) }

    public func login(name: String, password: String) async throws -> Login {
        // The single login of the server: the application it is for is kept with the login and in the audit.
        let j = try JSONSerialization.jsonObject(with: Data(try await call("/auth/login", method: "POST", body: json(["name": name, "password": password, "app": loginApp])).utf8)) as? [String: Any]
        let expires = (j?["expires_s"] as? NSNumber)?.intValue ?? 0
        let result = Login(token: (j?["token"] as? String) ?? "", name: (j?["name"] as? String) ?? name, role: (j?["role"] as? String) ?? "viewer", sessionId: (j?["session_id"] as? String) ?? "", expiresS: expires)
        token = result.token
        adoptLife(expires)
        return result
    }

    /// Makes the login last again (`POST /auth/refresh`): the token stays the same; answers the seconds that are left.
    @discardableResult
    public func refresh() async throws -> Int {
        let j = try JSONSerialization.jsonObject(with: Data(try await call("/auth/refresh", method: "POST", body: "{}").utf8)) as? [String: Any]
        let left = (j?["expires_s"] as? NSNumber)?.intValue ?? 0
        adoptLife(left)
        return left
    }

    /// The open logins of the person who asks (`GET /auth/sessions`), the newest first.
    public func sessions() async throws -> [AuthSession] { try parseSessions(try await call("/auth/sessions")) }

    /// Closes one login of the list (a phone that was lost): its token stops working at once.
    public func closeSession(_ id: String) async throws { _ = try await call("/auth/sessions/\(q(id))", method: "DELETE") }

    /// Ends every login of the person, this one too.
    public func logoutAll() async throws { _ = try await call("/auth/logout-all", method: "POST", body: "{}") }

    /// The machines of the plugins of the server (laser, pick-and-place, printer...) with what each says of itself in `detail`; the ones of the drilling and routing machines are in the fleet.
    public func workMachines() async throws -> [WorkMachine] { try parseWorkMachines(try await call("/work/machines")) }

    /// The feeder and head nodes of the pick-and-place machines, with their health as the server last saw it (read only; a server where the nodes are switched off answers 501).
    public func pnpNodes() async throws -> [PnpNode] { try parsePnpNodes(try await call("/pnp/nodes")) }

    /// The 3D printers the server watches, read only: this GET is the only thing the phone asks about them (a server with the list switched off answers 501). An answer that is not the contract
    /// is `bad_json`, never an empty list.
    public func printers() async throws -> [Printer] {
        guard let list = parsePrinters(try await call("/printers")) else { throw ApiError(status: 200, code: "bad_json", detail: "the answer is not the list of printers") }
        return list
    }

    /// The jobs of the generic queue of the server (the newest first, at most 100): the ones that wait, run or are held are the ones the app shows.
    public func workJobs() async throws -> [WorkJob] { try parseWorkJobs(try await call("/work/jobs?limit=100")) }

    /// Starts a job that waits in the queue. Only ever called from a button that a person pressed twice: nothing in the app starts a job by itself. With `hash` the start names the hash the person was
    /// shown, so a job that changed since is refused (`stale_authorization`) and nothing starts; without it the body is empty, as before.
    public func startWorkJob(_ id: String, hash: String = "") async throws {
        _ = try await call("/work/jobs/\(q(id))/start", method: "POST", body: hash.isEmpty ? "{}" : json(["toolpath_sha256": hash]))
    }

    /// Authorizes the hash of a job that waits (scope `jobs:authorize`): the server records who authorised which hash. Only ever called from the second touch of a button.
    public func authorizeWorkJob(_ id: String, hash: String) async throws { _ = try await call("/work/jobs/\(q(id))/authorize", method: "POST", body: json(["toolpath_sha256": hash])) }

    /// Cancels a job of the queue that waits or is held.
    public func cancelWorkJob(_ id: String) async throws { _ = try await call("/work/jobs/\(q(id))/cancel", method: "POST", body: "{}") }

    /// The emergency stop of a machine of a plugin, at once and with no question: the route of its plugin when it has one (CNC and 3D printer: heaters off, motors released, machine latched), else the
    /// cancel of the job that runs on it (a laser: the beam goes off and the machine latches). A machine with neither a route nor a job asks for nothing. A stop that got no answer is sent once more:
    /// the server takes a stop twice without harm, and one that never arrived is worse than one that arrives twice. Answers false when there was nothing to send.
    @discardableResult
    public func emergencyStopWork(_ machine: WorkMachine) async throws -> Bool {
        let path: String
        if let route = MachineSafety.stopRoute(machine.plugin) { path = "/work/machines/\(q(machine.id))/\(route)" }
        else if !machine.job.isEmpty { path = "/work/jobs/\(q(machine.job))/cancel" }
        else { return false }
        do { _ = try await call(path, method: "POST", body: "{}") }
        catch let error as ApiError {
            if error.status != 0 { throw error }
            _ = try await call(path, method: "POST", body: "{}")
        }
        return true
    }

    /// Releases the latch of an emergency stop or of a fault (an administrator); a plugin that does not latch has no such route and nothing is asked. Answers false when there was nothing to send.
    @discardableResult
    public func releaseWork(_ machine: WorkMachine) async throws -> Bool {
        guard let route = MachineSafety.releaseRoute(machine.plugin) else { return false }
        _ = try await call("/work/machines/\(q(machine.id))/\(route)", method: "POST", body: "{}")
        return true
    }

    /// The switches of security of the server that the app explains (administrators only; any other role is refused with 403).
    public func policySwitches() async throws -> [PolicySwitch] { try parsePolicySwitches(try await call("/auth/policy")) }

    /// The contract of the settings of the server with the values in force (`GET /settings/contract`): administrators only, any other role is refused with 403. Answers the text of the reply.
    public func settingsContract() async throws -> String { try await call("/settings/contract") }

    /// The values in force of the settings, light and read only (`GET /settings/values`): any login. `etag` is the tag of the last answer; the server answers `304` when nothing changed. The text of a new answer
    /// is read by the model (`parseLight`), which refuses what it does not trust.
    public func settingsValues(etag: String?) async throws -> LightReply {
        await renewIfDue(lightPath)
        var retry = 0
        while true {
            do { return try await onceLight(etag: etag) }
            catch let error as ApiError {
                if Task.isCancelled || retry >= settings.retries || !RetryRules.mayRepeat(method: "GET", status: error.status, neverSent: error.neverSent) { throw error }
                await pause(RetryRules.delayMs(retry))
                retry += 1
            }
        }
    }

    /// Writes one setting by the method and the route its entry of the contract names (path without `/api/v1`). Answers the text of the reply: the new policy and, in `changed`, what the server did.
    public func writeSetting(method: String, path: String, body: String) async throws -> String { try await call(path, method: method, body: body) }

    public func session() async throws -> Login {
        let j = try JSONSerialization.jsonObject(with: Data(try await call("/session").utf8)) as? [String: Any]
        return Login(token: token, name: (j?["name"] as? String) ?? "", role: (j?["role"] as? String) ?? "viewer")
    }

    public func logout() async { _ = try? await call("/auth/logout", method: "POST", body: "{}") }

    public func fleet() async throws -> Fleet { try parseFleet(try await call("/fleet")) }
    public func jobs(machine: String? = nil) async throws -> [JobSummary] { try parseJobs(try await call("/jobs" + (machine.map { "?machine=\(q($0))" } ?? ""))) }
    public func job(_ id: String) async throws -> Job { try parseJob(try await call("/jobs/\(q(id))")) }
    public func start(_ id: String) async throws { _ = try await call("/jobs/\(q(id))/start", method: "POST", body: "{}") }
    /// `question` is the one on the screen (`pause.question`): the server refuses the answer when the job asks something else by then. A server of an earlier version gives none.
    public func confirm(_ id: String, question: String? = nil) async throws { _ = try await call("/jobs/\(q(id))/confirm", method: "POST", body: answerBody(question)) }
    public func cancel(_ id: String) async throws { _ = try await call("/jobs/\(q(id))/cancel", method: "POST", body: "{}") }
    public func delete(_ id: String) async throws { _ = try await call("/jobs/\(q(id))", method: "DELETE") }
    /// Holds a running G-code job, and lets a held one (or one that goes on after a stop) go on.
    public func pause(_ id: String) async throws { _ = try await call("/jobs/\(q(id))/pause", method: "POST", body: "{}") }
    public func resume(_ id: String, question: String? = nil) async throws { _ = try await call("/jobs/\(q(id))/resume", method: "POST", body: answerBody(question)) }
    private func answerBody(_ question: String?) -> String {
        guard let question, let data = try? JSONSerialization.data(withJSONObject: ["question": question]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Makes a new job, ready and not started, from the request the server kept for a cancelled or failed one, with the work already done left out: the file is not asked for again.
    public func resumeFrom(_ id: String) async throws -> Job { try parseJob(try await call("/jobs/\(q(id))/resume-from", method: "POST", body: "{}")) }

    /// The switch of the machine for the `$` lines of GRBL (read only here: an administrator changes it in Studio).
    public func allowDollar(_ machine: String) async throws -> Bool { try parseAllowDollar(try await call("/machines/\(q(machine))")) }

    /// Plans a job and answers its view, creating nothing: the tools of the file, the holes, the lines of a G-code program.
    public func preview(_ machine: String, body: String) async throws -> JobView { try parsePreview(try await call("/machines/\(q(machine))/preview", method: "POST", body: body)) }

    /// Plans a job and keeps it ready (it never starts by itself); the answer is the job.
    public func createJob(_ machine: String, body: String) async throws -> Job { try parseJob(try await call("/machines/\(q(machine))/jobs", method: "POST", body: body)) }
    /// The spindle of the machine, its limits and the switch that says what happens to a job that asks for more.
    public func spindle(_ machine: String) async throws -> SpindleInfo { try parseSpindle(try await call("/machines/\(q(machine))/spindle")) }

    /// Sets the spindle (`original`, `vfd` or empty for none) and/or the switch (`reject` or `warn`); what is nil stays as it was. Administrator only.
    public func setSpindle(_ machine: String, spindle: String?, guardMode: String?) async throws -> SpindleInfo {
        var body: [String: String] = [:]
        if let spindle { body["spindle"] = spindle }
        if let guardMode { body["guard"] = guardMode }
        return try parseSpindle(try await call("/machines/\(q(machine))/spindle", method: "PUT", body: json(body)))
    }

    public func head(_ machine: String) async throws -> HeadStatus { try parseHead(try await call("/machines/\(q(machine))/head/status")) }
    public func measure(_ machine: String, samples: Int = 7) async throws -> Measure { try parseMeasure(try await call("/machines/\(q(machine))/head/measure?samples=\(samples)", method: "POST", body: "{}")) }

    /// The ring of LEDs around the camera: off (level 0) or on in the white of the camera at a level; the node keeps its own ceiling.
    public func setLight(_ machine: String, level: Int) async throws -> RingLight {
        let path = "/machines/\(q(machine))/head/light"
        return try parseRingLight(try await call(level <= 0 ? "\(path)?on=0" : "\(path)?on=1&level=\(min(level, 100))&tone=white&sectors=all", method: "POST", body: "{}"))
    }

    /// A quality check: the ring is lit at `light` (0: left as it is), the picture is taken, the analyser of the shop judges it and the ring shows how it went. `holeMm` is the width of the hole of the job in the centre (0: none).
    public func inspect(_ machine: String, light: Int, holeMm: Double) async throws -> Quality {
        let holes = holeMm > 0 ? "[{\"x_mm\":0,\"y_mm\":0,\"dia_mm\":\(String(format: "%.3f", holeMm))}]" : "[]"
        let lit = light > 0 ? ",\"light\":\(min(light, 100)),\"restore_light\":true" : ""
        return try parseQuality(try await call("/machines/\(q(machine))/head/inspect", method: "POST", body: "{\"holes\":\(holes)\(lit)}"))
    }

    /// The last check of the machine (made from here or from another program), or nil when there has been none since the server started.
    public func lastInspection(_ machine: String) async throws -> Quality? {
        do { return try parseQuality(try await call("/machines/\(q(machine))/head/inspect")) }
        catch let e as ApiError where e.code == "no_inspection" { return nil }
    }

    /// Makes the profile of the analyser one of the presets: 0 standard, 1 fine pitch, 2 prototype.
    public func inspectPreset(_ machine: String, index: Int) async throws {
        let name = ["standard", "fine_pitch", "prototype"][min(max(index, 0), 2)]
        _ = try await call("/machines/\(q(machine))/head/inspect/profile", method: "PUT", body: "{\"preset\":\"\(name)\"}")
    }

    /// Sets the scale of the picture from the hole that was just measured.
    public func inspectCalibrate(_ machine: String) async throws { _ = try await call("/machines/\(q(machine))/head/inspect/calibrate", method: "POST", body: "{}") }

    /// The address of the camera of the head, as the server hands it on; the token is in the address because a picture cannot carry a header.
    /// The address of the camera without any credential: `withTicket` adds a one-use ticket just before it is opened.
    public func streamURL(_ machine: String) -> URL? { URL(string: origin + "/api/v1/machines/\(q(machine))/head/stream") }

    /// `url` with a new ticket in it (good for one use within half a minute): the token of the session never goes in an address.
    public func withTicket(_ url: URL) async throws -> URL {
        let j = try JSONSerialization.jsonObject(with: Data(try await call("/tickets", method: "POST", body: "{}").utf8)) as? [String: Any]
        let ticket = (j?["ticket"] as? String) ?? ""
        return Eh3dApi.ticketURL(url, ticket: ticket)
    }

    /// `url` with `ticket` as its query.
    public static func ticketURL(_ url: URL, ticket: String) -> URL {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var items = parts?.queryItems ?? []
        items.append(URLQueryItem(name: "ticket", value: ticket))
        parts?.queryItems = items
        return parts?.url ?? url
    }

    /// The stop button of a machine: whatever job is active on it is ended at once (the server reaches the machine without waiting for the line it is sending).
    public func stopMachine(_ machine: String) async throws { _ = try await call("/machines/\(q(machine))/stop", method: "POST", body: "{}") }
}
