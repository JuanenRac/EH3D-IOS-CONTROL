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
    public func head(_ machine: String) async throws -> HeadStatus { try parseHead(try await call("/machines/\(q(machine))/head/status")) }
    public func measure(_ machine: String, samples: Int = 7) async throws -> Measure { try parseMeasure(try await call("/machines/\(q(machine))/head/measure?samples=\(samples)", method: "POST", body: "{}")) }

    /// The address of the camera of the head, as the server hands it on; the token is in the address because a picture cannot carry a header.
    public func streamURL(_ machine: String) -> URL? { URL(string: origin + "/api/v1/machines/\(q(machine))/head/stream?token=\(q(token))") }
}
