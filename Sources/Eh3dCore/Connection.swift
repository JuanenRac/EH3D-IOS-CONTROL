// EH3D-IOS-CONTROL - how the app talks to the server: the settings of the connection (time-out, retries, search on the local network) and the rules of the client of the suite that the app follows, as plain logic
// with no clock or network in it so it is tested: the pauses between tries, which requests may be sent again, when a login is renewed, the sessions that the server lists, the machines of the plugins and the
// servers found on the local network. The same rules as the Android app (Connection.kt).
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

/// The three settings of the connection that a phone can change. The ranges and the defaults are the ones of the client of the suite (`server_timeout_s`, `server_retries`, `server_mdns`);
/// a value out of its range is brought to the nearest end. The search for the server on the local network (Bonjour) is off by default.
public struct ConnectionSettings: Equatable, Sendable {
    public static let keyTimeout = "server_timeout_s"
    public static let keyRetries = "server_retries"
    public static let keyMdns = "server_mdns"
    public static let defaultTimeoutS = 15
    public static let defaultRetries = 2
    public static let timeoutRange = 1...120
    public static let retriesRange = 0...5

    public let timeoutS: Int
    public let retries: Int
    public let mdns: Bool

    /// The settings with every value inside its range.
    public init(timeoutS: Int = ConnectionSettings.defaultTimeoutS, retries: Int = ConnectionSettings.defaultRetries, mdns: Bool = false) {
        self.timeoutS = min(max(timeoutS, ConnectionSettings.timeoutRange.lowerBound), ConnectionSettings.timeoutRange.upperBound)
        self.retries = min(max(retries, ConnectionSettings.retriesRange.lowerBound), ConnectionSettings.retriesRange.upperBound)
        self.mdns = mdns
    }

    /// The saved settings, read with the two readers of a preferences store (each answers the saved value or the one it is given); what is not saved is the default, and what is out of its range is brought into it.
    public static func read(int: (String, Int) -> Int, bool: (String, Bool) -> Bool) -> ConnectionSettings {
        ConnectionSettings(timeoutS: int(keyTimeout, defaultTimeoutS), retries: int(keyRetries, defaultRetries), mdns: bool(keyMdns, false))
    }

    public func withTimeout(_ value: Int) -> ConnectionSettings { ConnectionSettings(timeoutS: value, retries: retries, mdns: mdns) }
    public func withRetries(_ value: Int) -> ConnectionSettings { ConnectionSettings(timeoutS: timeoutS, retries: value, mdns: mdns) }
    public func withMdns(_ value: Bool) -> ConnectionSettings { ConnectionSettings(timeoutS: timeoutS, retries: retries, mdns: value) }
}

/// The rules for sending a request again after a failure.
public enum RetryRules {
    private static let repeatable: Set<String> = ["GET", "HEAD", "PUT", "DELETE", "OPTIONS"]

    /// The pause in milliseconds before the retry number `retry` (0 is the first retry): 200 ms, 400 ms, 800 ms... up to 2 s.
    public static func delayMs(_ retry: Int) -> Int { min(200 << min(max(retry, 0), 4), 2_000) }

    /// True when a request that failed may be sent again. `status` is 0 when there was no answer; `neverSent` is true when the connection could not even be made (nothing went out, so any method
    /// is safe). A time-out or a broken connection, and a 502, 503 or 504, are tried again only for the requests that do no harm twice: a POST (a job, a login) is never sent twice.
    public static func mayRepeat(method: String, status: Int, neverSent: Bool) -> Bool {
        let safe = repeatable.contains(method.uppercased())
        switch status {
        case 0: return neverSent || safe
        case 502, 503, 504: return safe
        default: return false
        }
    }
}

/// When a login is renewed: in the last quarter of its life, by itself, before the next request.
public enum RefreshRule {
    /// `totalS` is how long a login lasts, `leftS` what is left; a login of unknown life, or one that is over, is not renewed here.
    public static func due(totalS: Int, leftS: Int) -> Bool { totalS > 0 && leftS > 0 && leftS <= totalS / 4 }
}

/// One open login of the caller, as `GET /auth/sessions` lists it (the id is not the token).
public struct AuthSession: Equatable, Sendable {
    public let id: String
    public let name: String
    public let role: String
    public let app: String
    public let ip: String
    public let current: Bool
    public init(id: String, name: String, role: String, app: String, ip: String, current: Bool) {
        self.id = id; self.name = name; self.role = role; self.app = app; self.ip = ip; self.current = current
    }
}

private typealias Json = [String: Any]

private func rootObject(_ text: String) throws -> Json {
    guard let data = text.data(using: .utf8), let any = try? JSONSerialization.jsonObject(with: data), let json = any as? Json else { throw ApiError(status: 0, code: "bad_json", detail: "not a JSON object") }
    return json
}

private func text(_ json: Json, _ key: String, _ fallback: String = "") -> String { (json[key] as? String) ?? fallback }

/// A JSON `true`, or the text "true" in any case (a number such as 1 is not one).
private func isTrue(_ any: Any?) -> Bool {
    if let word = any as? String { return word.lowercased() == "true" }
    guard let number = any as? NSNumber else { return false }
    return String(cString: number.objCType) == "c" && number.boolValue
}

/// The sessions of the answer `{"sessions": [...]}`; an item without an id is left out, and anything that is not a list is an empty list.
public func parseSessions(_ body: String) throws -> [AuthSession] {
    let list = (try rootObject(body)["sessions"] as? [Any]) ?? []
    return list.compactMap { $0 as? Json }.filter { !text($0, "id").isEmpty }
        .map { AuthSession(id: text($0, "id"), name: text($0, "name"), role: text($0, "role", "viewer"), app: text($0, "app"), ip: text($0, "ip"), current: isTrue($0["current"])) }
}

/// A machine of a plugin of the server (`GET /work/machines`) with what the plugin says of it in `detail`, flattened to lines of text. `latched` is true when an interlock holds it (`interlocks`);
/// `simulatorOnly` says it has only run against a simulator; `job` is the id of the job that runs on it, or empty; `autoStart` says its queue starts jobs by itself (a warning, never set from the phone);
/// `limits` and `heaters` are the limits of temperature and the heaters of a 3D printer.
public struct WorkMachine: Equatable, Sendable {
    public let id: String
    public let name: String
    public let plugin: String
    public let state: String
    public let latched: Bool
    public let detail: [DetailLine]
    public let job: String
    public let simulatorOnly: Bool
    public let interlocks: [Interlock]
    public let autoStart: Bool
    public let limits: TempLimits?
    public let heaters: [Heater]
    public init(id: String, name: String, plugin: String, state: String, latched: Bool, detail: [DetailLine], job: String = "", simulatorOnly: Bool = false,
                interlocks: [Interlock] = [], autoStart: Bool = false, limits: TempLimits? = nil, heaters: [Heater] = []) {
        self.id = id; self.name = name; self.plugin = plugin; self.state = state; self.latched = latched; self.detail = detail
        self.job = job; self.simulatorOnly = simulatorOnly; self.interlocks = interlocks; self.autoStart = autoStart; self.limits = limits; self.heaters = heaters
    }
}

/// One line of the detail of a machine of a plugin: the key (`a.b` for a nested object) and its value as text.
public struct DetailLine: Equatable, Sendable {
    public let key: String
    public let value: String
    public init(_ key: String, _ value: String) { self.key = key; self.value = value }
}

/// The most lines of a detail that are kept (a screen shows the first 8 of them).
private let maxDetailLines = 24

/// The machines of the answer `{"machines": [...]}` that are not of the `bungard` plugin (those are the fleet the app already shows). Nested objects are shown as `a.b`, lists by their size.
public func parseWorkMachines(_ body: String) throws -> [WorkMachine] {
    let list = (try rootObject(body)["machines"] as? [Any]) ?? []
    return list.compactMap { $0 as? Json }.filter { !text($0, "id").isEmpty && text($0, "plugin") != "bungard" }.map { m in
        let detail = m["detail"] as? Json
        var lines: [DetailLine] = []
        if let detail { flatten(prefix: "", detail, into: &lines, depth: 0) }
        let held = MachineSafety.interlocks(detail: detail)
        return WorkMachine(id: text(m, "id"), name: text(m, "name", text(m, "id")), plugin: text(m, "plugin"), state: text(m, "state", "idle"), latched: !held.isEmpty, detail: lines,
                           job: text(m, "job"), simulatorOnly: MachineSafety.simulatorOnly(detail: detail, capabilities: m["capabilities"] as? Json), interlocks: held,
                           autoStart: MachineSafety.startsByItself(detail: detail), limits: MachineSafety.limits(detail: detail), heaters: MachineSafety.heaters(detail: detail))
    }
}

private func flatten(prefix: String, _ json: Json, into out: inout [DetailLine], depth: Int) {
    for key in json.keys.sorted() {
        if out.count >= maxDetailLines { return }
        let name = prefix.isEmpty ? key : "\(prefix).\(key)"
        guard let value = json[key], !(value is NSNull) else { continue }
        if let object = value as? Json {
            if depth < 2 { flatten(prefix: name, object, into: &out, depth: depth + 1) } else { out.append(DetailLine(name, "{…}")) }
        } else if let array = value as? [Any] {
            out.append(DetailLine(name, "[\(array.count)]"))
        } else if let number = value as? NSNumber {
            out.append(DetailLine(name, numberText(number)))
        } else {
            out.append(DetailLine(name, String(describing: value)))
        }
    }
}

/// A JSON number or boolean as text: `true`, `5`, `1.5`.
private func numberText(_ number: NSNumber) -> String {
    if String(cString: number.objCType) == "c" { return number.boolValue ? "true" : "false" }
    let value = number.doubleValue
    if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
    return "\(value)"
}

/// A feeder or head node of a pick-and-place machine as `GET /pnp/nodes` lists it. The phone only reads them (EH3D-STUDIO registers, changes and removes them). `ready` is the verdict of the server:
/// only the healths `ok` and `warn` are ready and every other one is not, so an answer that does not say is not ready. The token of a node never comes in the answer (the server sends `********`) and is
/// not read here. `facts` are the few numbers the node said last, as lines of text.
public struct PnpNode: Equatable, Sendable {
    public let id: String
    public let kind: String
    public let name: String
    public let address: String
    public let machine: String
    public let enabled: Bool
    public let health: String
    public let ready: Bool
    public let lastError: String
    public let simulatorOnly: Bool
    public let facts: [DetailLine]
    public init(id: String, kind: String, name: String, address: String, machine: String, enabled: Bool, health: String, ready: Bool, lastError: String, simulatorOnly: Bool, facts: [DetailLine]) {
        self.id = id; self.kind = kind; self.name = name; self.address = address; self.machine = machine; self.enabled = enabled
        self.health = health; self.ready = ready; self.lastError = lastError; self.simulatorOnly = simulatorOnly; self.facts = facts
    }
}

/// The keys of what a node said last that the phone lists, in this order.
private let pnpFactKeys = ["safe", "selfcheck", "online", "slots", "low", "empty", "faulted", "nozzle_count", "pump"]

/// The nodes of the answer `{"nodes": [...]}`; an item without an id is left out, and anything that is not a list is an empty list.
public func parsePnpNodes(_ body: String) throws -> [PnpNode] {
    let list = (try rootObject(body)["nodes"] as? [Any]) ?? []
    return list.compactMap { $0 as? Json }.filter { !text($0, "id").isEmpty }.map { n in
        var facts: [DetailLine] = []
        if let status = n["status"] as? Json {
            for key in pnpFactKeys {
                guard let value = status[key], !(value is NSNull) else { continue }
                if let number = value as? NSNumber { facts.append(DetailLine(key, numberText(number))) } else { facts.append(DetailLine(key, String(describing: value))) }
            }
        }
        let enabled = (n["enabled"] as? NSNumber).map { $0.boolValue } ?? true
        return PnpNode(id: text(n, "id"), kind: text(n, "kind"), name: text(n, "name", text(n, "id")), address: text(n, "address"), machine: text(n, "machine"), enabled: enabled,
                       health: text(n, "health", "unknown"), ready: isTrue(n["ready"]), lastError: text(n, "last_error"),
                       simulatorOnly: text(n, "evidence") == "simulator" || isTrue(n["simulator_only"]), facts: facts)
    }
}

/// A server found on the local network: shown to the person, who chooses; nothing connects by itself.
public struct Candidate: Equatable, Sendable {
    public let host: String
    public let port: Int
    public init(host: String, port: Int) { self.host = host; self.port = port }
    public var label: String { "\(host):\(port)" }
}

/// The most servers found on the network that are listed (any device of the network can answer, so the list is short).
public let maxCandidates = 8

/// The candidates found so far with one more: no repeats, no more than `maxCandidates`, and nothing that is not a host and a port.
public func addCandidate(_ found: [Candidate], host: String?, port: Int) -> [Candidate] {
    var clean = (host ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    while clean.hasSuffix(".") { clean.removeLast() }
    if clean.isEmpty || !(1...65535).contains(port) || clean.contains(where: { $0.isWhitespace || $0 == "/" }) { return found }
    let item = Candidate(host: clean, port: port)
    return found.contains(item) || found.count >= maxCandidates ? found : found + [item]
}

/// The service type the server announces (Bonjour / mDNS).
public let serviceType = "_eh3d._tcp"
