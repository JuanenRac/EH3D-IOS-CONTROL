// EH3D-IOS-CONTROL - preparing a job from the phone: what to do (drilling, routing, both or a free G-code program), the tools of the file with their count, the ones switched off, the tool to start at
// and the requests the server takes (docs/API.md of EH3D-SERVER). The same rules as the Android app, so both behave the same; the pure part, so a test can check it without a screen.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

/// What the job does: drilling, routing, both (two jobs, one after the other) or a free G-code program.
public enum Work: CaseIterable, Sendable { case drill, route, both, gcode }

/// The two kinds of work that come from files.
public enum Side: Sendable {
    case drill, route
    public var kind: String { self == .drill ? "drill" : "route" }
}

/// What the phone knows of the file of one side: its name and text, the text of the tool table (optional), and what the server planned from them.
public struct SideState: Equatable, Sendable {
    public var fileName = "", text = "", tableName = "", tableText = ""
    public var view: JobView?
    public var off: Set<Int> = []
    public var startAt: Int?
    public var error = ""
    public init(fileName: String = "", text: String = "", tableName: String = "", tableText: String = "", view: JobView? = nil, off: Set<Int> = [], startAt: Int? = nil, error: String = "") {
        self.fileName = fileName; self.text = text; self.tableName = tableName; self.tableText = tableText; self.view = view; self.off = off; self.startAt = startAt; self.error = error
    }
    public var hasFile: Bool { !text.isEmpty }
}

public enum Prepare {
    /// The biggest file the phone sends (the server has its own limit and refuses a bigger one with `too_big`).
    public static let maxFileBytes = 8 * 1024 * 1024

    /// What each work needs of a machine: the connection `node` takes drilling and routing, `grbl` G-code only and `demo` all of them.
    public static func machineTakes(_ connection: String, _ work: Work) -> Bool {
        switch connection {
        case "grbl": return work == .gcode
        case "node": return work != .gcode
        default: return true
        }
    }

    /// The works a machine can be given, in the order of the picker.
    public static func works(_ connection: String) -> [Work] { Work.allCases.filter { machineTakes(connection, $0) } }

    /// The tools of a file in the order the job does them: the one the work uses first comes first.
    public static func toolOrder(_ view: JobView) -> [Int] {
        var order: [Int] = []
        for h in view.holes where !order.contains(h.tool) { order.append(h.tool) }
        for p in view.paths where !order.contains(p.pen) { order.append(p.pen) }
        if order.isEmpty { for t in view.tools where !order.contains(t.number) { order.append(t.number) } }
        return order
    }

    /// The tools to leave out: the ones switched off and, when the job starts at a tool, every one that comes before it in the order of the job.
    public static func skipTools(order: [Int], off: Set<Int>, startAt: Int?) -> [Int] {
        var out = off
        if let first = startAt, order.contains(first) { for t in order { if t == first { break }; out.insert(t) } }
        return order.filter { out.contains($0) } + off.filter { !order.contains($0) }.sorted()
    }

    /// True when every tool of the file is left out (the server would refuse the job with `no_work`).
    public static func nothingLeft(order: [Int], skipped: [Int]) -> Bool { !order.isEmpty && order.allSatisfy { skipped.contains($0) } }

    /// Starting at a tool: choosing the one already chosen takes the choice back, and a tool that is switched off cannot be the start.
    public static func toggleStartAt(current: Int?, tool: Int, off: Set<Int>) -> Int? { off.contains(tool) ? current : (current == tool ? nil : tool) }

    /// Switching a tool off (or on again).
    public static func toggleOff(_ off: Set<Int>, tool: Int) -> Set<Int> { var o = off; if o.contains(tool) { o.remove(tool) } else { o.insert(tool) }; return o }

    /// The diameters an Excellon file declares in its header (`T01C0.80`), by tool number; empty when it declares none.
    public static func declaredDiameters(_ ncd: String) -> [Int: Double] {
        guard let re = try? NSRegularExpression(pattern: #"^\s*T(\d+)\s*C(\d*\.?\d+)"#, options: [.anchorsMatchLines]) else { return [:] }
        let head = String(ncd.prefix(20_000))
        let ns = head as NSString
        var out: [Int: Double] = [:]
        for m in re.matches(in: head, range: NSRange(location: 0, length: ns.length)) {
            guard let n = Int(ns.substring(with: m.range(at: 1))), let d = Double(ns.substring(with: m.range(at: 2))) else { continue }
            if out[n] == nil { out[n] = d }
        }
        return out
    }

    private static func encode(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    /// The request that plans a drilling or routing job from the text of the files.
    public static func fileBody(side: Side, name: String, text: String, tableText: String, skipTools: [Int]) -> String {
        var files: [String: Any] = [:]
        if side == .drill { files["ncd"] = text; if !tableText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { files["dtd"] = tableText } }
        else { files["plt"] = text; if !tableText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { files["rtd"] = tableText } }
        var body: [String: Any] = ["kind": side.kind, "files": files]
        if !name.trimmingCharacters(in: .whitespaces).isEmpty { body["name"] = name }
        if !skipTools.isEmpty { body["skip_tools"] = skipTools }
        return encode(body)
    }

    /// The request that plans a free G-code program: `skip` lines already done; the spindle and the coolant are started again only with `restoreOutputs` (off by default).
    public static func gcodeBody(name: String, gcode: String, skip: Int, restoreOutputs: Bool) -> String {
        var body: [String: Any] = ["kind": "gcode", "gcode": gcode, "skip": max(skip, 0), "restore_outputs": restoreOutputs]
        if !name.trimmingCharacters(in: .whitespaces).isEmpty { body["name"] = name }
        return encode(body)
    }

    /// The name of the job: the file without its extension.
    public static func jobName(_ fileName: String) -> String {
        let base = (fileName as NSString).deletingPathExtension
        return String((base.isEmpty ? fileName : base).prefix(60))
    }

    /// The number of lines of a program (counting blank and comment lines, as `skip` does).
    public static func lineCount(_ text: String) -> Int { text.isEmpty ? 0 : text.filter { $0 == "\n" }.count + (text.hasSuffix("\n") ? 0 : 1) }

    /// The `skip` to go on with after a stop: the line the job says, never beyond the program.
    public static func resumeSkip(line: Int, total: Int) -> Int { min(max(line, 0), max(total, 0)) }
}
