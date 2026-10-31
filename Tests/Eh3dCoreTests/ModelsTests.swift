import XCTest
@testable import Eh3dCore

/// What the server says (docs/API.md of EH3D-SERVER), read into the data the screens show: the same checks as the Android app.
final class ModelsTests: XCTestCase {
    private let fleetText = """
    {"stations":[{"id":"bench","machines":["bungard","spare"]}],
     "machines":[
      {"id":"bungard","name":"Bungard CCD","model":"ccd-mtc","station":"bench","connection":"node","state":"waiting","ready":2,
       "job":{"id":"j7","name":"board 1","kind":"drill","state":"waiting_operator","by":"ana","items_done":17,"items_total":34,"holes_done":8,"holes_total":16,"percent":50,
              "pause":{"kind":"tool_change","tool":2},"estimate_s":120.0}},
      {"id":"spare","name":"Spare","model":"","station":"bench","connection":"demo","state":"idle","ready":0,"job":null}],
     "summary":{"machines":2,"idle":1,"busy":0,"waiting":1,"stations":1}}
    """

    func testTheFleetIsReadWithItsJobsAndThePauseOfAJob() throws {
        let fleet = try parseFleet(fleetText)
        XCTAssertEqual(fleet.machines.count, 2)
        XCTAssertEqual([fleet.idle, fleet.busy, fleet.waiting], [1, 0, 1])
        let m = try XCTUnwrap(fleet.machine("bungard"))
        XCTAssertEqual(m.state, "waiting")
        XCTAssertEqual(m.ready, 2)
        let job = try XCTUnwrap(m.job)
        XCTAssertEqual(job.percent, 50)
        XCTAssertEqual(job.pause, Pause(kind: "tool_change", tool: 2))
        XCTAssertEqual(job.remainingS, 60, accuracy: 1e-9)
        XCTAssertNil(fleet.machine("spare")?.job)
        XCTAssertNil(fleet.machine("nobody"))
    }

    func testAnEmptyOrOddFleetDoesNotBreakTheScreens() throws {
        XCTAssertTrue(try parseFleet(#"{"machines":[]}"#).machines.isEmpty)
        let odd = try parseFleet(#"{"machines":[{"id":"a"}]}"#)
        XCTAssertEqual(odd.machines.first?.state, "idle")
        XCTAssertEqual(odd.idle, 1)
        XCTAssertThrowsError(try parseFleet("not json"))
    }

    func testTheJobWithItsViewIsRead() throws {
        let job = try parseJob("""
        {"id":"j7","machine":"bungard","name":"board 1","kind":"drill","state":"running","by":"ana","items_total":34,"items_done":14,"holes_total":3,"holes_done":1,"message":"","pause":null,"estimate_s":28.8,
         "view":{"kind":"drill","name":"board 1","tools":[{"number":1,"spindle_rpm":24000,"count":3,"feed_mm_min":1000,"depth_mm":null,"iterations":null}],
                 "holes":[{"tool":1,"x_mm":10.0,"y_mm":10.0},{"tool":1,"x_mm":20.0,"y_mm":10.0},{"tool":1,"x_mm":30.0,"y_mm":20.0}],"paths":[],
                 "bounds_mm":[10.0,10.0,30.0,20.0],"items":34,"hole_ends":[14,17,24],"estimate_s":28.8,"travel_mm":10.0}}
        """)
        XCTAssertEqual(job.summary.state, "running")
        XCTAssertEqual(job.summary.percent, 41)
        XCTAssertEqual(job.view.holes.count, 3)
        XCTAssertEqual(job.view.tools.first?.spindleRpm, 24000)
        XCTAssertNil(job.view.tools.first?.depthMm)
        XCTAssertEqual(job.view.holeEnds, [14, 17, 24])
        XCTAssertEqual(job.view.bounds?[2], 30.0)
        XCTAssertTrue(JobStates.active(job.summary.state))
        XCTAssertFalse(JobStates.finished(job.summary.state))
    }

    func testARoutingJobKeepsItsPathsInMillimetres() throws {
        let job = try parseJob(#"{"id":"r","machine":"m","name":"","kind":"route","state":"ready","by":"x","items_total":4,"items_done":0,"estimate_s":3,"view":{"kind":"route","name":"","tools":[],"holes":[],"paths":[{"pen":1,"points_mm":[[10,10],[40,10],[40,30]]}],"bounds_mm":[10,10,40,30],"items":4,"hole_ends":[],"estimate_s":3,"travel_mm":50}}"#)
        XCTAssertEqual(job.view.paths.first?.points, [Spot(x: 10, y: 10), Spot(x: 40, y: 10), Spot(x: 40, y: 30)])
        XCTAssertEqual(job.summary.state, "ready")
    }

    func testTheJobsOfTheListHaveNoView() throws {
        let list = try parseJobs(#"[{"id":"a","machine":"m","name":"n","kind":"drill","state":"done","by":"x","items_total":10,"items_done":10,"holes_total":5,"holes_done":5,"message":"","estimate_s":1.0}]"#)
        XCTAssertEqual(list.first?.percent, 100)
        XCTAssertTrue(JobStates.finished(list[0].state))
    }

    func testTheHeadAndAMeasureAreRead() throws {
        let head = try parseHead(#"{"node":"aux","camera":true,"camera_model":"ov5640","laser":true,"rpm_sensor":true,"rpm":23890,"temp_c":41.5,"heat":"warn","protect_open":false,"uptime_s":99}"#)
        XCTAssertTrue(head.camera)
        XCTAssertEqual(head.cameraModel, "ov5640")
        XCTAssertEqual(head.tempC, 41.5)
        XCTAssertEqual(head.heat, "warn")
        XCTAssertNil(try parseHead(#"{"temp_c":null}"#).tempC)
        let m = try parseMeasure(#"{"ok":true,"why":"ok","distance_mm":12.345,"sigma_mm":0.02,"asked":7,"used":6,"rejected":1}"#)
        XCTAssertTrue(m.ok)
        XCTAssertEqual(m.used, 6)
    }

    func testOnlyAnOperatorOrAnAdministratorMayOperate() {
        XCTAssertTrue(Roles.canOperate("operator")); XCTAssertTrue(Roles.canOperate("admin"))
        XCTAssertFalse(Roles.canOperate("viewer")); XCTAssertFalse(Roles.canOperate(""))
    }

    func testTheErrorOfTheServerIsItsCodeAndItsDetail() {
        let a = describeError(status: 409, body: #"{"error":"machine_busy","detail":"one job at a time"}"#)
        XCTAssertEqual(a.code, "machine_busy"); XCTAssertEqual(a.detail, "one job at a time")
        let b = describeError(status: 502, body: "<html>bad gateway</html>")
        XCTAssertEqual(b.code, "http_502"); XCTAssertEqual(b.detail, "")
    }

    func testVersionsAreComparedNumberByNumber() {
        XCTAssertTrue(SemanticVersion.isNewer("0.0.4", than: "0.0.3"))
        XCTAssertTrue(SemanticVersion.isNewer("v0.1.0", than: "0.0.9"))
        XCTAssertTrue(SemanticVersion.isNewer("0.8.0.1", than: "0.8.0"))
        XCTAssertFalse(SemanticVersion.isNewer("0.0.3", than: "0.0.3"))
        XCTAssertFalse(SemanticVersion.isNewer("0.0.2", than: "0.0.3"))
        XCTAssertFalse(SemanticVersion.isNewer("0.0.4-rc1", than: "0.0.3"))
        XCTAssertFalse(SemanticVersion.isNewer("junk", than: "0.0.3"))
    }
}
