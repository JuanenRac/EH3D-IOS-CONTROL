// EH3D-IOS-CONTROL - the 3D printers the server watches (GET /printers of EH3D-SERVER, contract `eh3d.printers.status/1`), read only: the phone asks with GET and has no way to ask a printer to do
// anything. The answer is read field by field: what is missing, of another type or not a number a printer can mean is unknown (nil), never zero, and an answer that is not the contract is refused. The
// access code of a printer, its address and its serial number are never read. The Android app has the same rules (model/Printers.kt) and both walk the same file of cases.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

public let printersSchema = "eh3d.printers.status/1"

/// The most printers and alerts that are read, and the longest text kept (in characters).
public let maxPrinters = 64
public let maxPrinterAlerts = 32
public let maxPrinterText = 128

public let printerHealths = ["disabled", "off", "unknown", "online", "stale", "offline", "refused", "untrusted", "bad_report"]
public let printerStates = ["unknown", "idle", "preparing", "printing", "paused", "finished", "failed", "cancelled", "error", "emergency"]
public let printerTemperatureNames = ["nozzle", "bed", "chamber"]
private let alertSeverities = ["error", "warning", "info"]

private let minC = -100.0
private let maxC = 1000.0
private let maxLayer = 1_000_000.0
private let maxRemainingS = 366.0 * 24 * 3600
private let maxAgeS = 1_000_000_000_000.0

public struct PrinterTemperature: Equatable, Sendable {
    public let name: String
    public let currentC: Double?
    public let targetC: Double?
}

public struct PrinterAlert: Equatable, Sendable {
    public let severity: String
    public let code: String
    public let message: String
}

/// One printer. `state` is nil when the server shows nothing of what the printer said, and then `alerts` is nil too (unknown, not "none"). Every number is nil when the printer did not say it.
public struct Printer: Equatable, Sendable {
    public let id: String
    public let name: String
    public let family: String
    public let health: String
    /// Whether what is shown is what the printer is now.
    public let current: Bool
    public let state: String?
    public let temperatures: [PrinterTemperature]
    public let progressPct: Double?
    public let remainingS: Int?
    public let remainingEstimated: Bool
    public let layer: Int?
    public let layers: Int?
    public let jobName: String
    public let alerts: [PrinterAlert]?
    public let ageS: Int?
    public let simulated: Bool
}

/// What the page shows of the printers: nothing, the list, or that the answer cannot be read.
public enum PrinterView: Equatable, Sendable { case hidden, listed, unreadable }

/// `old` is true when the list is the last one that was read and the server did not answer the last time.
public struct PrinterListing: Equatable, Sendable {
    public let view: PrinterView
    public let printers: [Printer]
    public let old: Bool
    public init(_ view: PrinterView, printers: [Printer] = [], old: Bool = false) { self.view = view; self.printers = printers; self.old = old }
    public static let hidden = PrinterListing(.hidden)
    public static let unreadable = PrinterListing(.unreadable)
}

/// What the page shows after the list could not be read. A server with the list switched off (501 `printers_off`), without it (404) or that does not let this login see it (403) shows nothing; an answer
/// that is not the list says so; a server that did not answer, is busy or failed keeps the last list, marked as old. A login that ended (401) is for the caller.
public func printersAfterFailure(_ previous: PrinterListing, status: Int, code: String) -> PrinterListing {
    if code == "bad_json" { return .unreadable }
    if status == 501 { return .hidden }
    if status == 0 || status == 429 || status >= 500 {
        return previous.view == .listed ? PrinterListing(.listed, printers: previous.printers, old: true) : previous
    }
    return .hidden
}

/// A text of a printer: no control characters nor the ones that turn the reading order around, and not longer than `maxPrinterText` characters.
public func cleanPrinterText(_ text: String) -> String {
    var out = String.UnicodeScalarView()
    var kept = 0
    for scalar in text.unicodeScalars {
        if kept >= maxPrinterText { break }
        let c = scalar.value
        if c < 0x20 || (0x7F...0x9F).contains(c) || (0x200B...0x200F).contains(c) || (0x202A...0x202E).contains(c) || (0x2066...0x2069).contains(c) { continue }
        out.append(scalar)
        kept += 1
    }
    return String(out)
}

private typealias PrinterJson = [String: Any]

private func words(_ json: PrinterJson, _ key: String) -> String { (json[key] as? String).map { cleanPrinterText($0) } ?? "" }

private func isBoolean(_ number: NSNumber) -> Bool { String(cString: number.objCType) == "c" }

/// A number that is a JSON number (not a text, not a boolean), finite and within the range; nil for anything else.
private func within(_ json: PrinterJson?, _ key: String, _ low: Double, _ high: Double) -> Double? {
    guard let number = json?[key] as? NSNumber, !isBoolean(number) else { return nil }
    let value = number.doubleValue
    return value.isFinite && value >= low && value <= high ? value : nil
}

private func count(_ json: PrinterJson?, _ key: String, _ low: Double, _ high: Double) -> Int? {
    guard let value = within(json, key, low, high), value == value.rounded(.down) else { return nil }
    return Int(value)
}

private func yes(_ json: PrinterJson?, _ key: String) -> Bool {
    guard let number = json?[key] as? NSNumber else { return false }
    return isBoolean(number) && number.boolValue
}

private func oneOf(_ value: String, _ list: [String], _ otherwise: String) -> String { list.contains(value) ? value : otherwise }

private func objects(_ any: Any?, _ limit: Int) -> [PrinterJson] { ((any as? [Any]) ?? []).prefix(limit).compactMap { $0 as? PrinterJson } }

private func temperatures(_ any: Any?) -> [PrinterTemperature] {
    var out: [PrinterTemperature] = []
    for t in objects(any, 16) {
        guard let name = t["name"] as? String, printerTemperatureNames.contains(name), !out.contains(where: { $0.name == name }) else { continue }
        out.append(PrinterTemperature(name: name, currentC: within(t, "current_c", minC, maxC), targetC: within(t, "target_c", minC, maxC)))
    }
    return out
}

// an alert whose severity is not known is taken as a warning, never dropped
private func alerts(_ any: Any?) -> [PrinterAlert]? {
    guard any is [Any] else { return nil }
    return objects(any, maxPrinterAlerts).map { PrinterAlert(severity: oneOf(words($0, "severity"), alertSeverities, "warning"), code: words($0, "code"), message: words($0, "message")) }
}

private func printer(_ p: PrinterJson) -> Printer? {
    let id = words(p, "id")
    if id.isEmpty { return nil }
    // a health this version does not know is not taken as online
    let health = oneOf(words(p, "health"), printerHealths, "unknown")
    let s = health == "online" || health == "stale" ? p["status"] as? PrinterJson : nil
    let name = words(p, "name")
    return Printer(
        id: id, name: name.isEmpty ? id : name, family: words(p, "family"), health: health,
        current: health == "online" && yes(p, "current"),
        state: s.map { oneOf(words($0, "state"), printerStates, "unknown") },
        temperatures: temperatures(s?["temperatures"]),
        progressPct: within(s, "progress_pct", 0, 100),
        remainingS: count(s, "remaining_s", 0, maxRemainingS),
        remainingEstimated: yes(s, "remaining_estimated"),
        layer: count(s, "layer", 0, maxLayer),
        layers: count(s, "layers", 1, maxLayer),
        jobName: s.map { words($0, "job_name") } ?? "",
        alerts: alerts(s?["alerts"]),
        ageS: count(p, "age_s", 0, maxAgeS),
        simulated: yes(p, "simulator_only"))
}

/// The printers of an answer, or nil when the answer is not the contract: an empty list must not be taken for "no printers". A printer without an id, or with the id of one before, is left out.
public func parsePrinters(_ body: String) -> [Printer]? {
    guard let data = body.data(using: .utf8), let root = (try? JSONSerialization.jsonObject(with: data)) as? PrinterJson,
          root["schema"] as? String == printersSchema, let list = root["printers"] as? [Any] else { return nil }
    var seen = Set<String>()
    return objects(list, maxPrinters).compactMap { printer($0) }.filter { seen.insert($0.id).inserted }
}

// ---- how it is written: what is unknown is said as unknown, never as zero

private func half(_ value: Double) -> Int { Int((value + 0.5).rounded(.down)) }

/// A temperature in whole degrees, or `unknown`.
public func printerDegrees(_ celsius: Double?, unknown: String) -> String { celsius.map { "\(half($0)) °C" } ?? unknown }

/// The progress in whole percent (rounded down, so 100 % is only said when it is done), or `unknown`.
public func printerPercent(_ percent: Double?, unknown: String) -> String { percent.map { "\(Int($0.rounded(.down))) %" } ?? unknown }

/// A layer number, or `unknown`.
public func printerNumber(_ value: Int?, unknown: String) -> String { value.map { String($0) } ?? unknown }

/// The time left as hours and minutes, rounded up to the minute.
public func printerTimeLeft(_ seconds: Int) -> (hours: Int, minutes: Int) {
    let minutes = (seconds + 59) / 60
    return (minutes / 60, minutes % 60)
}

/// The family of protocol by the name people know; another family is shown as the server writes it.
public func printerFamilyName(_ family: String) -> String {
    switch family {
    case "moonraker": return "Klipper / Moonraker"
    case "bambu_lan": return "Bambu Lab LAN"
    default: return family
    }
}
