// EH3D-IOS-CONTROL - the safety of the machines of the plugins of the server (laser, pick-and-place, board station, CNC, Gerber, CAM, 3D printer, vision, CAD) as the phone shows it: whether a machine has
// only run against a simulator, which interlock holds it, which safe actions a person has on it, the queue of its jobs and the switches of the server that are off by default.
// Plain logic with no screen or network in it, so it is tested. The SERVER decides in the end: these rules only keep the app from offering what would be refused and from hiding what must be seen.
// The same rules as the Android app (WorkSafety.kt) and as EH3D-STUDIO.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

/// What may keep a machine from starting: a latch (after an emergency stop or a fault), the latch of an emergency stop, or an alarm.
public enum Interlock: Equatable, Sendable { case latched, estopLatched, alarm }

/// One heater of a 3D printer as the plugin reports it: the name, the temperature now and the target, in degrees Celsius.
public struct Heater: Equatable, Sendable {
    public let name: String
    public let currentC: Double
    public let targetC: Double
    public init(name: String, currentC: Double, targetC: Double) { self.name = name; self.currentC = currentC; self.targetC = targetC }
}

/// The hottest each heater of a 3D printer may be asked, in degrees Celsius; 0 is a heater that the printer does not have.
public struct TempLimits: Equatable, Sendable {
    public let hotendC: Double
    public let bedC: Double
    public let chamberC: Double
    public init(hotendC: Double, bedC: Double, chamberC: Double) { self.hotendC = hotendC; self.bedC = bedC; self.chamberC = chamberC }
}

/// Where the authorization of a job stands: nobody authorised it, a person authorised the hash it has now, or the hash that was authorised is not the one it has now.
public enum JobAuth: Equatable, Sendable { case none, authorized, stale }

/// A job of the generic queue of the server (`GET /work/jobs`), as much of it as the phone shows. `toolpathSha256` is the hash of what the job will do (made when it was prepared); `authorizedHash` and
/// `authorizedBy` are what a person authorised (empty when nobody has).
public struct WorkJob: Equatable, Sendable {
    public let id: String
    public let machine: String
    public let plugin: String
    public let name: String
    public let owner: String
    public let state: String
    public let percent: Int
    public let position: Int
    public let toolpathSha256: String
    public let authorizedHash: String
    public let authorizedBy: String
    public init(id: String, machine: String, plugin: String, name: String, owner: String, state: String, percent: Int, position: Int, toolpathSha256: String = "", authorizedHash: String = "", authorizedBy: String = "") {
        self.id = id; self.machine = machine; self.plugin = plugin; self.name = name; self.owner = owner; self.state = state; self.percent = percent; self.position = position
        self.toolpathSha256 = toolpathSha256; self.authorizedHash = authorizedHash; self.authorizedBy = authorizedBy
    }
}

/// A switch of security of the server (`GET /auth/policy`, administrators only): its key, whether it is on and whether the value is as strict as recommended.
public struct PolicySwitch: Equatable, Sendable {
    public let key: String
    public let on: Bool
    public let safe: Bool
    public init(key: String, on: Bool, safe: Bool) { self.key = key; self.on = on; self.safe = safe }
}

private typealias SafetyJson = [String: Any]

/// A JSON `true`, or the text "true" in any case (a number such as 1 is not one).
private func trueValue(_ any: Any?) -> Bool {
    if let word = any as? String { return word.lowercased() == "true" }
    guard let number = any as? NSNumber else { return false }
    return String(cString: number.objCType) == "c" && number.boolValue
}

/// A JSON number (or a text that is one) as a Double; anything else is `fallback`.
private func numberValue(_ any: Any?, _ fallback: Double = 0) -> Double {
    if let number = any as? NSNumber, String(cString: number.objCType) != "c" { return number.doubleValue }
    if let word = any as? String, let value = Double(word.trimmingCharacters(in: .whitespaces)) { return value }
    return fallback
}

/// A JSON number as a whole number; a value that is not one, or is out of any sensible range, is 0.
private func wholeValue(_ any: Any?) -> Int {
    let value = numberValue(any)
    return value.isFinite && abs(value) < 1e9 ? Int(value) : 0
}

private func wordValue(_ json: SafetyJson, _ key: String, _ fallback: String = "") -> String { (json[key] as? String) ?? fallback }

public enum MachineSafety {
    /// The plugins with a route of their own for the emergency stop; the others stop by cancelling the job that runs.
    private static let stopRoutes: [String: String] = ["cnc": "emergency-stop", "printer3d": "emergency-stop"]

    /// The plugins that latch and the route (under `/work/machines/{id}/`) that releases the latch.
    private static let releaseRoutes: [String: String] = ["cnc": "release", "printer3d": "release", "laser": "laser/release"]

    /// The plugins whose queued job waits for a person to start it, and says so on the screen.
    private static let manualStart: Set<String> = ["printer3d"]

    /// The values of `alarm` that say there is none.
    private static let noAlarm: Set<String> = ["", "none", "ok", "false", "0", "idle", "run"]

    /// The switches of the server that the phone explains: all of them are off by default.
    public static let switchKeys = ["mdns_announce", "compat_api", "compat_write", "slice_enabled"]

    /// The plugins that only run against a simulator today (docs/MACHINE_PLUGINS.md of EH3D-SERVER).
    public static let simulatorPlugins = ["laser", "pnp", "pcb", "cnc", "gerber", "cam", "printer3d", "vision", "cad"]

    /// The route of the emergency stop of the plugin under `/work/machines/{id}/`, or nil when the plugin stops by cancelling its job.
    public static func stopRoute(_ plugin: String) -> String? { stopRoutes[plugin] }

    /// The route that releases the latch of the plugin under `/work/machines/{id}/`, or nil when the plugin does not latch.
    public static func releaseRoute(_ plugin: String) -> String? { releaseRoutes[plugin] }

    /// Whether a queued job of this plugin waits for a person: the app never starts a job by itself, and says so for these.
    public static func needsManualStart(_ plugin: String) -> Bool { manualStart.contains(plugin) }

    /// Whether the machine has only run against a simulator: the server says so in `detail` (`simulator_only`, `evidence`) and in the capabilities (`evidence`). Never shown as proven on hardware.
    static func simulatorOnly(detail: [String: Any]?, capabilities: [String: Any]?) -> Bool {
        trueValue(detail?["simulator_only"]) || (detail?["evidence"] as? String) == "simulator" || (capabilities?["evidence"] as? String) == "simulator"
    }

    /// The interlocks that hold the machine, in the order the screen shows them.
    static func interlocks(detail: [String: Any]?) -> [Interlock] {
        guard let detail else { return [] }
        var out: [Interlock] = []
        if trueValue(detail["latched"]) { out.append(.latched) }
        if trueValue(detail["estop_latched"]) { out.append(.estopLatched) }
        var alarmOn = false
        if let flag = detail["alarm"] as? NSNumber { alarmOn = String(cString: flag.objCType) == "c" && flag.boolValue }
        else if let word = detail["alarm"] as? String { alarmOn = !noAlarm.contains(word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
        if let word = detail["state_word"] as? String, word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "alarm" { alarmOn = true }
        if alarmOn { out.append(.alarm) }
        return out
    }

    /// Whether the machine says that its queue starts the next job by itself: shown as a warning, never switched on from the phone.
    static func startsByItself(detail: [String: Any]?) -> Bool { trueValue(detail?["auto_start_queue"]) || trueValue(detail?["auto_start"]) }

    /// The limits of temperature of a 3D printer (`detail.limits_c`), or nil when the plugin does not say them.
    static func limits(detail: [String: Any]?) -> TempLimits? {
        guard let limits = detail?["limits_c"] as? [String: Any] else { return nil }
        return TempLimits(hotendC: numberValue(limits["hotend"]), bedC: numberValue(limits["bed"]), chamberC: numberValue(limits["chamber"]))
    }

    /// The heaters of a 3D printer (`detail.temperatures`); an item without a name is left out.
    static func heaters(detail: [String: Any]?) -> [Heater] {
        let list = (detail?["temperatures"] as? [Any]) ?? []
        return list.compactMap { $0 as? SafetyJson }.filter { !wordValue($0, "name").isEmpty }
            .map { Heater(name: wordValue($0, "name"), currentC: numberValue($0["current_c"]), targetC: numberValue($0["target_c"])) }
    }

    /// A temperature limit as a word of the screen: whole degrees, or `-` for a heater the printer does not have.
    public static func limitText(_ celsius: Double) -> String { celsius > 0 && !celsius.isNaN ? String(format: "%.0f", celsius) : "-" }

    /// A heater as one short line: `hotend 25/200`.
    public static func heaterText(_ heater: Heater) -> String { heater.name + " " + String(format: "%.0f/%.0f", heater.currentC, heater.targetC) }

    /// Whether the emergency stop is offered: to an operator, with no confirmation, when the plugin has a route for it or a job runs on the machine, unless the machine is already held by an interlock
    /// (there is nothing to stop; the latch is released by an administrator).
    public static func canStop(isOperator: Bool, _ machine: WorkMachine) -> Bool {
        isOperator && machine.interlocks.isEmpty && (stopRoute(machine.plugin) != nil || !machine.job.isEmpty)
    }

    /// Whether the release of a latch is offered: to an administrator only, for a machine that is held and whose plugin has a route for it. The screen asks twice.
    public static func canRelease(isAdmin: Bool, _ machine: WorkMachine) -> Bool { isAdmin && !machine.interlocks.isEmpty && releaseRoute(machine.plugin) != nil }

    /// The jobs of the queue that belong to a machine and are not finished, the running ones first, then the held, then the queued in their place.
    public static func activeJobs(_ jobs: [WorkJob], machineId: String) -> [WorkJob] {
        let rank = ["running": 0, "paused": 1, "queued": 2]
        let mine = jobs.enumerated().filter { $0.element.machine == machineId && rank[$0.element.state] != nil }
        return mine.sorted { a, b in
            let ra = rank[a.element.state] ?? 3, rb = rank[b.element.state] ?? 3
            if ra != rb { return ra < rb }
            if a.element.position != b.element.position { return a.element.position < b.element.position }
            return a.offset < b.offset
        }.map { $0.element }
    }

    /// Whether a person may start this job from the phone: an operator, and only a job that waits in the queue.
    public static func canStartJob(isOperator: Bool, _ job: WorkJob) -> Bool { isOperator && job.state == "queued" }

    /// Where the authorization of the job stands (the server decides in the end; this only tells the badge).
    public static func authOf(_ job: WorkJob) -> JobAuth {
        if job.authorizedHash.isEmpty { return .none }
        if !job.toolpathSha256.isEmpty && job.authorizedHash == job.toolpathSha256 { return .authorized }
        return .stale
    }

    /// The first characters of a hash, enough for a person to compare it with the one on the other screen.
    public static func shortHash(_ hash: String) -> String { hash.isEmpty ? "-" : String(hash.prefix(12)) }

    /// Whether the button to authorize is offered: an operator, a job that waits, that has a hash and whose present hash is not authorized yet. The scope `jobs:authorize` is the server's to check.
    public static func canAuthorize(isOperator: Bool, _ job: WorkJob) -> Bool { isOperator && job.state == "queued" && !job.toolpathSha256.isEmpty && authOf(job) != .authorized }

    /// The refusals that say the hash the person saw is not the one the server has (or that none was authorised): the job is read again and shown with its present hash.
    public static func needsReview(_ code: String) -> Bool { code == "stale_authorization" || code == "authorization_required" }

    /// Whether a person may cancel this job from the phone: an operator, and only a job that has not finished.
    public static func canCancelJob(isOperator: Bool, _ job: WorkJob) -> Bool { isOperator && (job.state == "queued" || job.state == "paused") }

    /// The keys of `detail` the screen shows in its own way: they are not repeated in the list of facts.
    private static let shownApart: Set<String> = ["evidence", "simulator_only", "latched", "estop_latched", "alarm", "auto_start_queue", "auto_start", "limits_c", "temperatures"]

    /// What else the plugin says of the machine, as short `key: value` pairs (at most `limit`, in the order of the detail).
    public static func facts(_ machine: WorkMachine, limit: Int = 6) -> [DetailLine] {
        Array(machine.detail.filter { !shownApart.contains($0.key) && !$0.key.hasPrefix("limits_c.") && !$0.key.hasPrefix("temperatures") }.prefix(max(limit, 0)))
    }
}

private func safetyRoot(_ body: String) throws -> SafetyJson {
    guard let data = body.data(using: .utf8), let any = try? JSONSerialization.jsonObject(with: data), let json = any as? SafetyJson else { throw ApiError(status: 0, code: "bad_json", detail: "not a JSON object") }
    return json
}

/// The jobs of the answer `{"items": [...]}` of `GET /work/jobs`; an item without an id is left out and anything else is an empty list.
public func parseWorkJobs(_ body: String) throws -> [WorkJob] {
    let list = (try safetyRoot(body)["items"] as? [Any]) ?? []
    return list.compactMap { $0 as? SafetyJson }.filter { !wordValue($0, "id").isEmpty }.map { item -> WorkJob in
        let authorization = item["authorization"] as? SafetyJson
        return WorkJob(id: wordValue(item, "id"), machine: wordValue(item, "machine"), plugin: wordValue(item, "plugin"), name: wordValue(item, "name"), owner: wordValue(item, "owner"),
                       state: wordValue(item, "state", "queued"), percent: wholeValue(item["percent"]), position: wholeValue(item["position"]),
                       toolpathSha256: wordValue(item, "toolpath_sha256"), authorizedHash: authorization.map { wordValue($0, "toolpath_sha256") } ?? "", authorizedBy: authorization.map { wordValue($0, "by") } ?? "")
    }
}

/// The switches of the answer `{"switches": [...]}` of `GET /auth/policy` that the phone explains (`MachineSafety.switchKeys`), in the order of that list.
public func parsePolicySwitches(_ body: String) throws -> [PolicySwitch] {
    let list = (try safetyRoot(body)["switches"] as? [Any]) ?? []
    var found: [String: PolicySwitch] = [:]
    for item in list.compactMap({ $0 as? SafetyJson }) {
        let key = wordValue(item, "key")
        guard MachineSafety.switchKeys.contains(key) else { continue }
        found[key] = PolicySwitch(key: key, on: trueValue(item["value"]), safe: (item["safe"] == nil || item["safe"] is NSNull) ? true : trueValue(item["safe"]))
    }
    return MachineSafety.switchKeys.compactMap { found[$0] }
}
