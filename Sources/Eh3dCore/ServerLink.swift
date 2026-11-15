// EH3D-IOS-CONTROL - how honest the app is about its link to the server: connected, data that is getting old, no connection, or an address that answers another service.
// One failure does not make the app say "no connection" (the Wi-Fi of a shop blinks); two in a row do, and the retries slow down while the server is away.
// Pure rules with no clock or screen in them, so they are tested; the Android app has the same rules and both read the same test cases.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

/// Why a request failed as far as the link goes.
public enum LinkFailure: Sendable { case unreachable, wrongServer }

/// What the screen says about the link.
public enum LinkState: Sendable { case connected, stale, offline, wrongServer }

/// The numbers of the link: how many failures in a row make "no connection", how old the data may be before it is called old, and the waits between retries.
public struct LinkPolicy: Equatable, Sendable {
    public var offlineAfter = 2
    public var staleAfterS = 5
    public var retryMs = [1_500, 3_000, 6_000, 10_000]
    public init() {}
    public init(offlineAfter: Int, staleAfterS: Int, retryMs: [Int]) { self.offlineAfter = offlineAfter; self.staleAfterS = staleAfterS; self.retryMs = retryMs }

    /// The wait before the next request: the normal pace while all goes well and after one failure, then longer up to the last of `retryMs`.
    public func retryDelayMs(_ failures: Int) -> Int { retryMs[min(max(failures - 1, 0), retryMs.count - 1)] }
}

/// The link as far as it is known: the failures in a row, when the last good answer came and when the last request was made (milliseconds of any steady clock).
public struct ServerLink: Equatable, Sendable {
    public var failures = 0
    public var lastOkMs: Int64?
    public var atMs: Int64 = 0
    public var failure: LinkFailure?
    public init() {}

    public func succeeded(nowMs: Int64) -> ServerLink { var l = ServerLink(); l.lastOkMs = nowMs; l.atMs = nowMs; return l }
    public func failed(_ why: LinkFailure, nowMs: Int64) -> ServerLink { var l = self; l.failures += 1; l.atMs = nowMs; l.failure = why; return l }

    /// How old the last good answer is, in seconds; nil when there has been none.
    public func ageS() -> Int64? { lastOkMs.map { max((atMs - $0) / 1000, 0) } }

    public func state(_ policy: LinkPolicy = LinkPolicy()) -> LinkState {
        if failures <= 0 { return .connected }
        if failure == .wrongServer { return .wrongServer }
        if failures >= policy.offlineAfter { return .offline }
        if let age = ageS(), age >= Int64(policy.staleAfterS) { return .stale }
        return .connected
    }
}

/// What a refused or lost request says about the link, or nil when the server answered as itself (a 404 for a job that is gone, a 403 for a viewer: the link is fine).
/// No answer at all and a 5xx are an unreachable server; an answer that is not the JSON of EH3D-SERVER, or an error without the `error` member of the API, is another service on that address.
public func classifyFailure(status: Int, code: String) -> LinkFailure? {
    if status == 0 { return .unreachable }
    if code == "bad_json" { return .wrongServer }
    if status >= 500 { return .unreachable }
    if code.hasPrefix("http_") && (400...499).contains(status) && status != 401 && status != 403 && status != 429 { return .wrongServer }
    return nil
}
