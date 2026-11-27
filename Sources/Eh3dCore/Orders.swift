// EH3D-IOS-CONTROL - the rules of the orders that set a machine going: sent once, never from old data, and an order with no answer is not told as one that did not happen.
// Pure rules with no clock or screen in them, so they are tested; the Android app has the same rules.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.

/// One order at a time under each key: while it is on its way, and for `holdMs` after the server took it, the same order is not sent again (the second touch of a double touch must not answer the
/// next question of the machine). A refused or lost one is free at once.
public struct OrderGate: Sendable {
    private let holdMs: Int64
    private var until: [String: Int64] = [:]

    public init(holdMs: Int64 = 1_000) { self.holdMs = holdMs }

    /// True when the order may be sent now; the key is then taken until `done`.
    public mutating func take(_ key: String, nowMs: Int64) -> Bool {
        if let held = until[key], nowMs < held { return false }
        until[key] = Int64.max
        return true
    }

    public mutating func done(_ key: String, taken: Bool, nowMs: Int64) {
        if taken { until[key] = nowMs + holdMs } else { until[key] = nil }
    }
}

/// True when nothing says whether the order got to the server: it went out and no answer came, or a gateway lost it. `neverSent`: the connection could not even be made.
public func mayHaveArrived(status: Int, neverSent: Bool) -> Bool { (status == 0 && !neverSent) || status == 502 || status == 504 }

/// Whether a machine may be set going (started, confirmed, let go): an operator, and only while what is on the screen is what the server says now. A stop never asks this.
public func mayOrder(operator canOperate: Bool, link: LinkState) -> Bool { canOperate && link == .connected }

/// The sentence of a refusal with what the server added (the line and the reason of a refused program), when it added something.
public func withDetail(_ words: String, code: String, detail: String) -> String {
    var extra = Substring(detail)
    while extra.first?.isWhitespace == true { extra = extra.dropFirst() }
    while extra.last?.isWhitespace == true { extra = extra.dropLast() }
    return extra.isEmpty || extra == Substring(code) ? words : "\(words) (\(extra))"
}
