// EH3D-IOS-CONTROL - the summary shown before a job starts: what it does, how long it takes, how far each axis goes (the dry run of the exact plan) and what looks wrong in the work.
// Pure rules with no screen in them, so they are tested; the Android app has the same rules and both read the same test cases.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

/// What the person is shown before a job starts. `seconds` is nil when nothing says how long it takes.
public struct StartSummary: Equatable, Sendable {
    public let count: Int
    public let tools: Int
    /// Width and height of the work in mm.
    public let sizeMm: [Double]?
    public let seconds: Double?
    public let reach: DryRun?
    public let warnings: [WorkWarning]
    /// The exact plan goes past the course of an axis.
    public let outOfCourse: Bool
}

/// Half-up rounding to one decimal, the same on both phones.
public func round1(_ value: Double) -> Double { (value * 10.0 + 0.5).rounded(.down) / 10.0 }

/// A number as short as it can be written: `10` for 10.0, `1.5` for 1.5.
public func plain(_ value: Double) -> String {
    if !value.isFinite { return "0" }
    if value == value.rounded() && abs(value) < 1e15 { return String(Int64(value)) }
    return String(value)
}

public func startSummary(_ view: JobView) -> StartSummary {
    let count = view.kind == "route" ? view.paths.count : view.kind == "drill" ? view.holes.count : view.items
    let reach = view.dryRun
    var seconds: Double? = reach?.seconds
    if seconds == nil && view.estimateS > 0 { seconds = view.estimateS }
    var size: [Double]? = nil
    if let b = view.bounds, b.count >= 4 { size = [round1(b[2] - b[0]), round1(b[3] - b[1])] }
    return StartSummary(count: count, tools: view.tools.count, sizeMm: size, seconds: seconds, reach: reach, warnings: view.warnings, outOfCourse: reach.map { !$0.withinCourse } ?? false)
}

/// The reach of the axes on one line, in mm: `X 0.0..30.0   Y 0.0..20.0   Z 0.0..25.8`.
public func reachLine(_ r: DryRun) -> String {
    func axis(_ i: Int) -> String {
        let low = i < r.minMm.count ? r.minMm[i] : 0
        let high = i < r.maxMm.count ? r.maxMm[i] : 0
        return String(format: "%.1f..%.1f", locale: Locale(identifier: "en_US_POSIX"), low, high)
    }
    return "X \(axis(0))   Y \(axis(1))   Z \(axis(2))"
}

/// The numbers a warning is written with, as text and in the order its phrase uses them.
public func warningArgs(_ w: WorkWarning) -> [String] {
    let v = w.values.map { plain(round1($0)) }
    func at(_ i: Int) -> String { i < v.count ? v[i] : "0" }
    func raw(_ i: Int) -> String { i < w.values.count ? plain(w.values[i]) : "0" }
    switch w.code {
    case "tiny": return [at(0), at(1)]
    case "too_big": return [at(0), at(1), at(2), at(3)]
    case "far": return [at(0)]
    case "scale": return [raw(0), raw(1)]
    case "out_of_course": return [w.axis, at(0)]
    default: return [w.code]
    }
}
