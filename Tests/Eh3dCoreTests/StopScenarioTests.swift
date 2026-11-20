import XCTest
@testable import Eh3dCore

/// A simulated EH3D-SERVER with a memory: one machine, `m1`, with one job, `j1`. A request to stop the job reaches the machine only after the fleet has been looked at twice more, and
/// the server can be made unreachable. Every look of the app goes through the real client (`Eh3dApi`) and the real rules of the stops and of the notices (`followStops`, `fleetNotices`).
/// Nothing here uses the network or a clock: the time is a number, so every run is the same. It has not run against a real server or a phone.
private final class WorkshopServer: URLProtocol {
    static let lock = NSLock()
    static var jobState: String? = "running"
    static var stopReads = 0
    static var unreachable = false

    static func reset() { lock.lock(); defer { lock.unlock() }; jobState = "running"; stopReads = 0; unreachable = false }
    static func set(job state: String?) { lock.lock(); defer { lock.unlock() }; jobState = state }
    static func set(unreachable value: Bool) { lock.lock(); defer { lock.unlock() }; unreachable = value }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WorkshopServer.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    private static func fleetText() -> String {
        let job: String
        let machine: String
        if let state = jobState {
            job = #"{"id":"j1","name":"board","kind":"drill","state":"\#(state)","by":"ana","items_done":3,"items_total":10,"holes_done":3,"holes_total":10,"percent":30,"estimate_s":60.0}"#
            machine = state == "waiting_operator" ? "waiting" : "busy"
        } else {
            job = "null"
            machine = "idle"
        }
        // after a stop the machine goes on showing its job for two more looks
        if stopReads > 0 {
            stopReads -= 1
            if stopReads == 0 { jobState = nil }
        }
        return #"{"machines":[{"id":"m1","name":"Drill 1","model":"ccd-mtc","station":"bench","connection":"node","state":"\#(machine)","ready":0,"job":\#(job)}]}"#
    }

    override func startLoading() {
        WorkshopServer.lock.lock()
        defer { WorkshopServer.lock.unlock() }
        if WorkshopServer.unreachable {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let url = request.url!
        var text = #"{"error":"not_found"}"#
        var status = 404
        if url.path == "/api/v1/fleet" {
            text = WorkshopServer.fleetText()
            status = 200
        } else if url.path == "/api/v1/jobs/j1/cancel" {
            if WorkshopServer.jobState != nil { WorkshopServer.stopReads = 2 }
            text = #"{"ok":true}"#
            status = 200
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class StopScenarioTests: XCTestCase {
    private var nowMs: Int64 = 0
    private var fleet = Fleet(machines: [], idle: 0, busy: 0, waiting: 0)

    override func setUp() {
        super.setUp()
        WorkshopServer.reset()
        nowMs = 0
    }

    private func api() -> Eh3dApi { Eh3dApi(origin: "http://sim.test:18200", token: "t", settings: ConnectionSettings(retries: 0), session: WorkshopServer.session()) }

    /// One look at the fleet every 1.5 s of the clock of the test; a failed look leaves the last fleet as it was.
    private func look() async {
        nowMs += 1_500
        if let seen = try? await api().fleet() { fleet = seen }
    }

    func testAStopIsSentThenStillWorkingPastTheGraceThenConfirmedAndTheNoteGoesAfterAWhile() async throws {
        await look()
        XCTAssertEqual(fleet.machine("m1")?.state, "busy")
        try await api().cancel("j1")
        var notes = [StopNote(machineId: "m1", machineName: "Drill 1", atMs: nowMs)]
        var seen: [StopOutcome] = []
        for _ in 0..<3 {
            await look()
            notes = followStops(notes, fleet: fleet, askedMs: nowMs, nowMs: nowMs + 50)
            seen.append(notes[0].outcome)
        }
        XCTAssertEqual(seen, [.sent, .stillWorking, .confirmed])
        XCTAssertNil(fleet.machine("m1")?.job)
        // eight seconds after the confirmation the note is gone
        notes = followStops(notes, fleet: fleet, askedMs: nowMs + 8_000, nowMs: nowMs + 8_100)
        XCTAssertTrue(notes.isEmpty)
    }

    func testAMachineThatDoesNotStopIsToldAsStillWorkingUntilItDoes() async {
        await look()
        var notes = [StopNote(machineId: "m1", machineName: "Drill 1", atMs: nowMs)]
        var seen: [StopOutcome] = []
        // the stop never reaches the machine: the server is not told to cancel
        for _ in 0..<4 {
            await look()
            notes = followStops(notes, fleet: fleet, askedMs: nowMs, nowMs: nowMs + 50)
            seen.append(notes[0].outcome)
        }
        XCTAssertEqual(seen, [.sent, .stillWorking, .stillWorking, .stillWorking])
        WorkshopServer.set(job: nil)
        await look()
        notes = followStops(notes, fleet: fleet, askedMs: nowMs, nowMs: nowMs + 50)
        XCTAssertEqual(notes[0].outcome, .confirmed)
    }

    func testAnOutageMakesNoNoticeAndTheChangesThatHappenedMeanwhileAreToldWhenTheServerIsBack() async {
        await look()
        let before = fleetStates(fleet)
        WorkshopServer.set(job: "waiting_operator")
        WorkshopServer.set(unreachable: true)
        await look()
        XCTAssertTrue(fleetNotices(before: before, now: fleet).isEmpty)
        WorkshopServer.set(unreachable: false)
        await look()
        XCTAssertEqual(fleetNotices(before: before, now: fleet), [Notice(machineId: "m1", machineName: "Drill 1", kind: .waiting)])
        let waiting = fleetStates(fleet)
        WorkshopServer.set(job: nil)
        await look()
        XCTAssertEqual(fleetNotices(before: waiting, now: fleet), [Notice(machineId: "m1", machineName: "Drill 1", kind: .ended)])
    }

    func testAStopThatDidNotReachTheServerIsSentOnceMoreButAnAnswerIsFinal() async throws {
        var calls = 0
        try await withStopRetry(pauseMs: 1) { calls += 1; if calls == 1 { throw ApiError(status: 0, code: "", detail: "") } }
        XCTAssertEqual(calls, 2)

        calls = 0
        do { try await withStopRetry(pauseMs: 1) { calls += 1; throw ApiError(status: 0, code: "", detail: "") }; XCTFail("must throw") } catch { XCTAssertEqual(calls, 2, "once more, not for ever") }

        calls = 0
        do { try await withStopRetry(pauseMs: 1) { calls += 1; throw ApiError(status: 503, code: "", detail: "") }; XCTFail("must throw") } catch { XCTAssertEqual(calls, 1, "an answer is not sent again") }
    }

    func testAStopRefusedForTheEndedSessionIsSentAgainOnlyWhileItIsRecent() {
        let pending = [PendingStop(machineId: "a", atMs: 1_000), PendingStop(machineId: "b", atMs: 200_000), PendingStop(machineId: "a", atMs: 1_500)]
        XCTAssertEqual(stopsToResend(pending, nowMs: 250_000), ["b"])
        XCTAssertEqual(stopsToResend(pending, nowMs: 100_000), ["a"])
        XCTAssertEqual(stopsToResend(pending, nowMs: 100), [])
    }
}
