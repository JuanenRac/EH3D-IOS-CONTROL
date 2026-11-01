// EH3D-IOS-CONTROL - the client of the API of EH3D-SERVER (docs/API.md of that project): URLSession with async/await, one request at a time, JSON read by the parsers of Models.swift.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

public struct Login: Equatable, Sendable {
    public let token: String
    public let name: String
    public let role: String
}

public final class Eh3dApi: @unchecked Sendable {
    private let origin: String
    public var token: String
    private let urlSession: URLSession
    private let version: String

    public init(origin: String, token: String = "", session: URLSession = .shared, version: String = "0.0.1") {
        self.origin = origin.hasSuffix("/") ? String(origin.dropLast()) : origin
        self.token = token
        self.urlSession = session
        self.version = version
    }

    private func request(_ path: String, method: String, body: String?) throws -> URLRequest {
        guard let url = URL(string: origin + "/api/v1" + path) else { throw ApiError(status: 0, code: "bad_address", detail: path) }
        var r = URLRequest(url: url, timeoutInterval: 12)
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

    private func call(_ path: String, method: String = "GET", body: String? = nil) async throws -> String {
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await urlSession.data(for: request(path, method: method, body: body)) }
        catch let error as ApiError { throw error }
        catch { throw ApiError(status: 0, code: "unreachable", detail: error.localizedDescription) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8) ?? ""
        if !(200...299).contains(status) {
            let e = describeError(status: status, body: text)
            throw ApiError(status: status, code: e.code, detail: e.detail.isEmpty ? e.code : e.detail)
        }
        return text
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
        let j = try JSONSerialization.jsonObject(with: Data(try await call("/login", method: "POST", body: json(["name": name, "password": password])).utf8)) as? [String: Any]
        return Login(token: (j?["token"] as? String) ?? "", name: (j?["name"] as? String) ?? name, role: (j?["role"] as? String) ?? "viewer")
    }

    public func session() async throws -> Login {
        let j = try JSONSerialization.jsonObject(with: Data(try await call("/session").utf8)) as? [String: Any]
        return Login(token: token, name: (j?["name"] as? String) ?? "", role: (j?["role"] as? String) ?? "viewer")
    }

    public func logout() async { _ = try? await call("/logout", method: "POST", body: "{}") }

    public func fleet() async throws -> Fleet { try parseFleet(try await call("/fleet")) }
    public func jobs(machine: String? = nil) async throws -> [JobSummary] { try parseJobs(try await call("/jobs" + (machine.map { "?machine=\(q($0))" } ?? ""))) }
    public func job(_ id: String) async throws -> Job { try parseJob(try await call("/jobs/\(q(id))")) }
    public func start(_ id: String) async throws { _ = try await call("/jobs/\(q(id))/start", method: "POST", body: "{}") }
    public func confirm(_ id: String) async throws { _ = try await call("/jobs/\(q(id))/confirm", method: "POST", body: "{}") }
    public func cancel(_ id: String) async throws { _ = try await call("/jobs/\(q(id))/cancel", method: "POST", body: "{}") }
    public func delete(_ id: String) async throws { _ = try await call("/jobs/\(q(id))", method: "DELETE") }
    /// Holds a running G-code job, and lets a held one (or one that goes on after a stop) go on.
    public func pause(_ id: String) async throws { _ = try await call("/jobs/\(q(id))/pause", method: "POST", body: "{}") }
    public func resume(_ id: String) async throws { _ = try await call("/jobs/\(q(id))/resume", method: "POST", body: "{}") }

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
