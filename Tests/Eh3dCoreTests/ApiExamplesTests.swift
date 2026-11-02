import XCTest
@testable import Eh3dCore

/// What the server answers, as the tests of the server make it (`Examples/*.json`, copied from `tests/examples` of EH3D-SERVER): every example is read by the same functions that
/// read the answers of a real server, and what comes out is compared with the example itself, so an answer that changes and that the app does not follow fails here.
final class ApiExamplesTests: XCTestCase {
    private func example(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Examples").appendingPathComponent("\(name).json")
        return try String(contentsOf: url, encoding: .utf8)  // read from the folder of this file: a resource bundle on the test target would take the place of the one of the package
    }

    private func object(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func list(_ text: String) throws -> [[String: Any]] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
    }

    func testTheFleetIsReadWithEveryMachineOfTheExample() throws {
        let text = try example("fleet")
        let raw = try object(text)
        let fleet = try parseFleet(text)
        let machines = try XCTUnwrap(raw["machines"] as? [[String: Any]])
        XCTAssertGreaterThan(machines.count, 1)
        XCTAssertEqual(fleet.machines.count, machines.count)
        for m in machines {
            let id = try XCTUnwrap(m["id"] as? String)
            let read = try XCTUnwrap(fleet.machine(id), id)
            XCTAssertEqual(read.name, m["name"] as? String)
            XCTAssertEqual(read.model, m["model"] as? String)
            XCTAssertEqual(read.station, m["station"] as? String)
            XCTAssertEqual(read.connection, m["connection"] as? String)
            XCTAssertEqual(read.state, m["state"] as? String)
            XCTAssertEqual(read.ready, m["ready"] as? Int)
            XCTAssertEqual(read.job == nil, m["job"] is NSNull)
        }
        let summary = try XCTUnwrap(raw["summary"] as? [String: Any])
        XCTAssertEqual([fleet.idle, fleet.busy, fleet.waiting], [summary["idle"] as? Int, summary["busy"] as? Int, summary["waiting"] as? Int].compactMap { $0 })
    }

    func testTheListOfJobsAndOneJobAreReadWithWhatTheExampleSays() throws {
        let rawList = try list(try example("jobs"))
        let read = try parseJobs(try example("jobs"))
        XCTAssertFalse(rawList.isEmpty)
        XCTAssertEqual(read.count, rawList.count)
        for (raw, job) in zip(rawList, read) {
            XCTAssertEqual(job.id, raw["id"] as? String)
            XCTAssertEqual(job.machine, raw["machine"] as? String)
            XCTAssertEqual(job.name, raw["name"] as? String)
            XCTAssertEqual(job.kind, raw["kind"] as? String)
            XCTAssertEqual(job.state, raw["state"] as? String)
            XCTAssertEqual(job.by, raw["by"] as? String)
            XCTAssertEqual(job.itemsTotal, raw["items_total"] as? Int)
            XCTAssertEqual(job.holesTotal, raw["holes_total"] as? Int)
            XCTAssertEqual(job.estimateS, try XCTUnwrap(raw["estimate_s"] as? Double), accuracy: 1e-9)
        }
        let text = try example("job")
        let raw = try object(text)
        let job = try parseJob(text)
        XCTAssertEqual(job.summary.id, raw["id"] as? String)
        XCTAssertEqual(job.summary.id, rawList[0]["id"] as? String)
        let view = try XCTUnwrap(raw["view"] as? [String: Any])
        XCTAssertEqual(job.view.holes.count, (view["holes"] as? [Any])?.count)
        XCTAssertEqual(job.view.tools.count, (view["tools"] as? [Any])?.count)
        XCTAssertEqual(job.view.items, view["items"] as? Int)
        XCTAssertEqual(job.view.holeEnds.count, (view["hole_ends"] as? [Any])?.count)
        let bounds = try XCTUnwrap(view["bounds_mm"] as? [Double])
        XCTAssertEqual(try XCTUnwrap(job.view.bounds)[2], bounds[2], accuracy: 1e-9)
        XCTAssertEqual(job.view.estimateS, try XCTUnwrap(view["estimate_s"] as? Double), accuracy: 1e-9)
        XCTAssertEqual(job.summary.created, raw["created"] as? Int)
        XCTAssertEqual(job.summary.finished == nil, raw["finished"] is NSNull)
        // the dry run and the warnings the server sends with every drilling or routing view
        let dry = try XCTUnwrap(view["dry_run"] as? [String: Any])
        let dryRead = try XCTUnwrap(job.view.dryRun)
        XCTAssertEqual(dryRead.maxMm[2], try XCTUnwrap((dry["max_mm"] as? [Double])?[2]), accuracy: 1e-9)
        XCTAssertEqual(dryRead.minMm.count, (dry["min_mm"] as? [Any])?.count)
        XCTAssertEqual(dryRead.endMm.count, (dry["end_mm"] as? [Any])?.count)
        XCTAssertEqual(dryRead.steps, dry["steps"] as? Int)
        XCTAssertEqual(dryRead.seconds, try XCTUnwrap(dry["seconds"] as? Double), accuracy: 1e-9)
        XCTAssertEqual(dryRead.withinCourse, dry["within_course"] as? Bool)
        XCTAssertEqual(job.view.warnings.count, (view["warnings"] as? [Any])?.count)
    }

    func testThePreviewIsTheViewThatTheJobCarries() throws {
        let preview = try parsePreview(try example("preview"))
        let inJob = try parseJob(try example("job")).view
        XCTAssertFalse(preview.holes.isEmpty)
        XCTAssertEqual(preview.holes, inJob.holes)
        XCTAssertEqual(preview.items, inJob.items)
        XCTAssertEqual(preview.tools.map(\.number), inJob.tools.map(\.number))
        XCTAssertTrue(preview.spindleWarnings.isEmpty)
        XCTAssertNotNil(preview.dryRun)
        XCTAssertEqual(preview.dryRun, inJob.dryRun)
    }

    func testTheSpindleIsReadWithItsLimitsAndTheOneInForce() throws {
        let text = try example("spindle")
        let raw = try object(text)
        let spindle = try parseSpindle(text)
        XCTAssertEqual(spindle.spindle, raw["spindle"] as? String)
        XCTAssertEqual(spindle.guardMode, raw["guard"] as? String)
        let limits = try XCTUnwrap(raw["limits"] as? [String: Any])
        let vfd = try XCTUnwrap(limits["vfd"] as? [String: Any])
        XCTAssertEqual(spindle.vfd?.maxRpm, vfd["max_rpm"] as? Int)
        XCTAssertEqual(spindle.vfd?.maxZMmMin, vfd["max_z_mm_min"] as? Int)
        XCTAssertEqual(spindle.original?.minRpm, (limits["original"] as? [String: Any])?["min_rpm"] as? Int)
        XCTAssertEqual(spindle.active == nil, raw["active"] is NSNull)
        if let active = raw["active"] as? [String: Any] { XCTAssertEqual(spindle.active?.maxXyMmMin, active["max_xy_mm_min"] as? Int) }
    }

    func testARefusalGivesItsCodeAndItsDetail() throws {
        let text = try example("error")
        let raw = try object(text)
        let described = describeError(status: 422, body: text)
        XCTAssertEqual(described.code, raw["error"] as? String)
        XCTAssertEqual(described.detail, raw["detail"] as? String)
    }
}
