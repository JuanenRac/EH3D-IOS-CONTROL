// EH3D-IOS-CONTROL - what happened to a stop after the button was pressed: sent, confirmed by the next look at the fleet, or the machine still works.
// Pure rules with no clock or screen in them, so they are tested; the Android app has the same rules and both read the same test cases.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

public enum StopOutcome: Sendable { case sent, confirmed, stillWorking }

/// A stop that was sent to the server: the machine, when (milliseconds of a steady clock), what the fleet has said since and, once confirmed, when.
public struct StopNote: Equatable, Sendable {
    public let machineId: String
    public let machineName: String
    public let atMs: Int64
    public var outcome: StopOutcome = .sent
    public var resolvedMs: Int64?
    public init(machineId: String, machineName: String, atMs: Int64) { self.machineId = machineId; self.machineName = machineName; self.atMs = atMs }
}

/// What the fleet says of a machine after a stop: free is confirmed, anything else is a machine that still works. Before any look, the stop is only sent.
public func stopOutcome(_ machine: FleetMachine?, looked: Bool) -> StopOutcome {
    if !looked { return .sent }
    guard let machine else { return .confirmed }
    return machine.job == nil && machine.state == "idle" ? .confirmed : .stillWorking
}

/// The notes after a look at the fleet that was asked for at `askedMs`: only a look asked for after a stop counts for it. A confirmed note stays `keepMs` on screen and goes;
/// one that still works stays until the machine is free. A machine that still shows its job within `graceMs` of the stop is given that time to end it before the note says it still works.
public func followStops(_ notes: [StopNote], fleet: Fleet, askedMs: Int64, nowMs: Int64, keepMs: Int64 = 8_000, graceMs: Int64 = 3_000) -> [StopNote] {
    notes.compactMap { n -> StopNote? in
        let seen = n.atMs <= askedMs ? stopOutcome(fleet.machine(n.machineId), looked: true) : n.outcome
        let outcome = (seen == .stillWorking && nowMs - n.atMs < graceMs) ? StopOutcome.sent : seen
        let resolved: Int64? = outcome == .confirmed ? (n.resolvedMs ?? nowMs) : nil
        if let resolved, nowMs - resolved > keepMs { return nil }
        var next = n
        next.outcome = outcome
        next.resolvedMs = resolved
        return next
    }
}
