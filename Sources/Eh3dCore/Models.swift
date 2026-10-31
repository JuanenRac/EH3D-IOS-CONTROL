// EH3D-IOS-CONTROL - what EH3D-SERVER says about the machines and their jobs, read from its JSON (the same rules as the Android app, so both show the same).
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

/// What a job waits for: put the tool of this number in (`tool_change`) or confirm that the spindle runs (`spindle_start`).
public struct Pause: Equatable, Sendable {
    public let kind: String
    public let tool: Int?
}

public enum JobStates {
    public static func active(_ state: String) -> Bool { state == "connecting" || state == "running" || state == "waiting_operator" }
    public static func finished(_ state: String) -> Bool { state == "done" || state == "cancelled" || state == "failed" }
}

public struct ActiveJob: Equatable, Sendable {
    public let id: String, name: String, kind: String, state: String, by: String
    public let itemsDone: Int, itemsTotal: Int, holesDone: Int, holesTotal: Int, percent: Int
    public let pause: Pause?
    public let estimateS: Double
    /// What is left of the estimate, in seconds, from how far the job is.
    public var remainingS: Double { estimateS <= 0 ? 0 : estimateS * Double(100 - min(max(percent, 0), 100)) / 100 }
}

public struct FleetMachine: Equatable, Sendable {
    public let id: String, name: String, model: String, station: String, connection: String
    /// `idle`, `busy` or `waiting` (for the operator).
    public let state: String
    public let job: ActiveJob?
    public let ready: Int
}

public struct Fleet: Equatable, Sendable {
    public let machines: [FleetMachine]
    public let idle: Int, busy: Int, waiting: Int
    public static let empty = Fleet(machines: [], idle: 0, busy: 0, waiting: 0)
    public func machine(_ id: String) -> FleetMachine? { machines.first { $0.id == id } }
}

// ---- reading the JSON: tolerant (a member that is missing or of another type is the default, never a crash)
typealias JSON = [String: Any]

private func object(_ text: String) throws -> JSON {
    guard let data = text.data(using: .utf8), let any = try? JSONSerialization.jsonObject(with: data), let json = any as? JSON else { throw ApiError(status: 0, code: "bad_json", detail: "not a JSON object") }
    return json
}

private func str(_ j: JSON, _ k: String, _ d: String = "") -> String { (j[k] as? String) ?? d }
private func int(_ j: JSON, _ k: String, _ d: Int = 0) -> Int { (j[k] as? NSNumber)?.intValue ?? d }
private func dbl(_ j: JSON, _ k: String) -> Double? { (j[k] as? NSNumber)?.doubleValue }
private func pauseOf(_ j: JSON?) -> Pause? { j.map { Pause(kind: str($0, "kind"), tool: ($0["tool"] as? NSNumber)?.intValue) } }

public func parseFleet(_ text: String) throws -> Fleet {
    let root = try object(text)
    let list = (root["machines"] as? [JSON]) ?? []
    let machines = list.map { m -> FleetMachine in
        let job = (m["job"] as? JSON).map { j in
            ActiveJob(id: str(j, "id"), name: str(j, "name"), kind: str(j, "kind"), state: str(j, "state"), by: str(j, "by"), itemsDone: int(j, "items_done"), itemsTotal: int(j, "items_total"),
                      holesDone: int(j, "holes_done"), holesTotal: int(j, "holes_total"), percent: int(j, "percent"), pause: pauseOf(j["pause"] as? JSON), estimateS: dbl(j, "estimate_s") ?? 0)
        }
        return FleetMachine(id: str(m, "id"), name: str(m, "name"), model: str(m, "model"), station: str(m, "station"), connection: str(m, "connection"), state: str(m, "state", "idle"), job: job, ready: int(m, "ready"))
    }
    let s = root["summary"] as? JSON
    return Fleet(machines: machines, idle: s.map { int($0, "idle") } ?? machines.filter { $0.state == "idle" }.count,
                 busy: s.map { int($0, "busy") } ?? machines.filter { $0.state == "busy" }.count, waiting: s.map { int($0, "waiting") } ?? machines.filter { $0.state == "waiting" }.count)
}

public struct JobSummary: Equatable, Sendable {
    public let id: String, machine: String, name: String, kind: String, state: String, by: String
    public let itemsTotal: Int, itemsDone: Int, holesTotal: Int, holesDone: Int
    public let message: String
    public let pause: Pause?
    public let estimateS: Double
    public var percent: Int { itemsTotal <= 0 ? 0 : min(max(itemsDone * 100 / itemsTotal, 0), 100) }
}

private func summaryOf(_ j: JSON) -> JobSummary {
    JobSummary(id: str(j, "id"), machine: str(j, "machine"), name: str(j, "name"), kind: str(j, "kind"), state: str(j, "state"), by: str(j, "by"), itemsTotal: int(j, "items_total"), itemsDone: int(j, "items_done"),
               holesTotal: int(j, "holes_total"), holesDone: int(j, "holes_done"), message: str(j, "message"), pause: pauseOf(j["pause"] as? JSON), estimateS: dbl(j, "estimate_s") ?? 0)
}

public func parseJobs(_ text: String) throws -> [JobSummary] {
    guard let data = text.data(using: .utf8), let any = try? JSONSerialization.jsonObject(with: data), let list = any as? [JSON] else { throw ApiError(status: 0, code: "bad_json", detail: "not a list") }
    return list.map(summaryOf)
}

public struct Hole: Equatable, Sendable { public let tool: Int; public let x: Double; public let y: Double }
public struct PathView: Equatable, Sendable { public let pen: Int; public let points: [Spot] }
public struct ToolView: Equatable, Sendable { public let number: Int; public let spindleRpm: Int; public let count: Int; public let feedMmMin: Int; public let depthMm: Double?; public let iterations: Int? }

/// The work as the machine does it, in mm: what the viewers draw. `bounds` is min x, min y, max x, max y.
public struct JobView: Equatable, Sendable {
    public let kind: String, name: String
    public let tools: [ToolView]
    public let holes: [Hole]
    public let paths: [PathView]
    public let bounds: [Double]?
    public let items: Int
    public let holeEnds: [Int]
    public let estimateS: Double, travelMm: Double
    public static let empty = JobView(kind: "", name: "", tools: [], holes: [], paths: [], bounds: nil, items: 0, holeEnds: [], estimateS: 0, travelMm: 0)
}

public struct Job: Equatable, Sendable { public let summary: JobSummary; public let view: JobView }

public func parseJob(_ text: String) throws -> Job {
    let j = try object(text)
    guard let v = j["view"] as? JSON else { return Job(summary: summaryOf(j), view: .empty) }
    let tools = ((v["tools"] as? [JSON]) ?? []).map { ToolView(number: int($0, "number"), spindleRpm: int($0, "spindle_rpm"), count: int($0, "count"), feedMmMin: int($0, "feed_mm_min"), depthMm: dbl($0, "depth_mm"), iterations: ($0["iterations"] as? NSNumber)?.intValue) }
    let holes = ((v["holes"] as? [JSON]) ?? []).map { Hole(tool: int($0, "tool"), x: dbl($0, "x_mm") ?? 0, y: dbl($0, "y_mm") ?? 0) }
    let paths = ((v["paths"] as? [JSON]) ?? []).map { p -> PathView in
        let pts = ((p["points_mm"] as? [[NSNumber]]) ?? []).filter { $0.count >= 2 }.map { Spot(x: $0[0].doubleValue, y: $0[1].doubleValue) }
        return PathView(pen: int(p, "pen"), points: pts)
    }
    let b = (v["bounds_mm"] as? [NSNumber])?.map { $0.doubleValue }
    let ends = ((v["hole_ends"] as? [NSNumber]) ?? []).map { $0.intValue }
    let view = JobView(kind: str(v, "kind"), name: str(v, "name"), tools: tools, holes: holes, paths: paths, bounds: (b?.count ?? 0) >= 4 ? Array(b!.prefix(4)) : nil, items: int(v, "items"), holeEnds: ends,
                       estimateS: dbl(v, "estimate_s") ?? 0, travelMm: dbl(v, "travel_mm") ?? 0)
    return Job(summary: summaryOf(j), view: view)
}

/// What the node of the drill head says (the server hands it on).
public struct HeadStatus: Equatable, Sendable {
    public let node: String
    public let camera: Bool, laser: Bool, rpmSensor: Bool
    public let cameraModel: String
    public let rpm: Double
    public let tempC: Double?
    public let heat: String
    public let protectOpen: Bool
    public let uptimeS: Int
}

public func parseHead(_ text: String) throws -> HeadStatus {
    let j = try object(text)
    return HeadStatus(node: str(j, "node"), camera: (j["camera"] as? Bool) ?? false, laser: (j["laser"] as? Bool) ?? false, rpmSensor: (j["rpm_sensor"] as? Bool) ?? false, cameraModel: str(j, "camera_model"),
                      rpm: dbl(j, "rpm") ?? 0, tempC: dbl(j, "temp_c"), heat: str(j, "heat", "ok"), protectOpen: (j["protect_open"] as? Bool) ?? false, uptimeS: int(j, "uptime_s"))
}

public struct Measure: Equatable, Sendable { public let ok: Bool; public let why: String; public let distanceMm: Double; public let sigmaMm: Double; public let used: Int; public let asked: Int }

public func parseMeasure(_ text: String) throws -> Measure {
    let j = try object(text)
    return Measure(ok: (j["ok"] as? Bool) ?? false, why: str(j, "why"), distanceMm: dbl(j, "distance_mm") ?? 0, sigmaMm: dbl(j, "sigma_mm") ?? 0, used: int(j, "used"), asked: int(j, "asked"))
}

/// The server refused, or could not be reached: `status` is the HTTP status (0 when there was no answer) and `code` the `error` code of the server, if it sent one.
public struct ApiError: Error, Equatable, Sendable {
    public let status: Int
    public let code: String
    public let detail: String
    public var unauthorized: Bool { status == 401 }
}

/// The pure part of the error of the server: its code and its detail, or what the status says.
public func describeError(status: Int, body: String) -> (code: String, detail: String) {
    let json = (body.data(using: .utf8)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? JSON
    let code = (json?["error"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "http_\(status)"
    return (code, (json?["detail"] as? String) ?? "")
}

/// What a role may do: an operator also plans, starts, confirms and cancels jobs; a viewer only watches.
public enum Roles { public static func canOperate(_ role: String) -> Bool { role == "operator" || role == "admin" } }
