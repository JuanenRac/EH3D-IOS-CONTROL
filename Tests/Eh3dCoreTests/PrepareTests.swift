import XCTest
@testable import Eh3dCore

/// Preparing a job from the phone: the tools of a file, the ones switched off, the start at a tool and the requests the server takes (the same cases as the Android app).
final class PrepareTests: XCTestCase {
    private let previewText = """
    {"kind":"drill","name":"board","tools":[{"number":2,"spindle_rpm":24000,"count":2,"feed_mm_min":1000},{"number":1,"spindle_rpm":24000,"count":1,"feed_mm_min":1000},{"number":3,"spindle_rpm":24000,"count":1,"feed_mm_min":1000}],
     "holes":[{"tool":2,"x_mm":1,"y_mm":1},{"tool":2,"x_mm":2,"y_mm":1},{"tool":1,"x_mm":3,"y_mm":1},{"tool":3,"x_mm":4,"y_mm":1}],
     "paths":[],"bounds_mm":[1,1,4,1],"items":8,"hole_ends":[2,4,6,8],"estimate_s":12.5,"travel_mm":3.0,"skipped_tools":[],"skipped":0}
    """

    private func dict(_ text: String) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]) }

    func testTheToolsComeInTheOrderTheJobDoesThem() throws {
        XCTAssertEqual(Prepare.toolOrder(try parsePreview(previewText)), [2, 1, 3])
    }

    func testAPreviewMayBeTheViewOrAJobThatCarriesIt() throws {
        XCTAssertEqual(try parsePreview(previewText).holes.count, 4)
        let job = "{\"id\":\"j1\",\"machine\":\"m\",\"name\":\"n\",\"kind\":\"drill\",\"state\":\"ready\",\"view\":\(previewText)}"
        XCTAssertEqual(try parsePreview(job).holes.count, 4)
    }

    func testSwitchedOffToolsAreLeftOut() {
        XCTAssertEqual(Prepare.skipTools(order: [2, 1, 3], off: [1], startAt: nil), [1])
        XCTAssertEqual(Prepare.skipTools(order: [2, 1, 3], off: [], startAt: nil), [])
    }

    func testStartingAtAToolLeavesOutTheOnesBeforeItInTheOrderOfTheJob() {
        let order = [2, 1, 3]
        XCTAssertEqual(Prepare.skipTools(order: order, off: [], startAt: 3), [2, 1])
        XCTAssertEqual(Prepare.skipTools(order: order, off: [], startAt: 1), [2])
        XCTAssertEqual(Prepare.skipTools(order: order, off: [], startAt: 2), [])
        XCTAssertEqual(Prepare.skipTools(order: order, off: [3, 2], startAt: 1), [2, 3])
        XCTAssertEqual(Prepare.skipTools(order: order, off: [3], startAt: 1), [2, 3])
    }

    func testAStartThatIsNotInTheFileLeavesNothingOut() {
        XCTAssertEqual(Prepare.skipTools(order: [1, 2], off: [], startAt: 9), [])
    }

    func testNothingIsLeftWhenEveryToolIsOut() {
        XCTAssertTrue(Prepare.nothingLeft(order: [1, 2], skipped: [1, 2]))
        XCTAssertFalse(Prepare.nothingLeft(order: [1, 2], skipped: [1]))
        XCTAssertFalse(Prepare.nothingLeft(order: [], skipped: []))
    }

    func testChoosingTheStartAgainTakesItBackAndAToolThatIsOffCannotBeTheStart() {
        XCTAssertEqual(Prepare.toggleStartAt(current: nil, tool: 3, off: []), 3)
        XCTAssertNil(Prepare.toggleStartAt(current: 3, tool: 3, off: []))
        XCTAssertEqual(Prepare.toggleStartAt(current: 3, tool: 2, off: []), 2)
        XCTAssertEqual(Prepare.toggleStartAt(current: 3, tool: 1, off: [1]), 3)
        XCTAssertEqual(Prepare.toggleOff([], tool: 1), [1])
        XCTAssertEqual(Prepare.toggleOff([1], tool: 1), [])
    }

    func testTheDiametersAnExcellonFileDeclaresAreRead() {
        let ncd = "M48\nINCH\nT1C0.8\nT02C1.0\nT3C.9\n%\nT1\nX1000Y1000\n"
        XCTAssertEqual(Prepare.declaredDiameters(ncd), [1: 0.8, 2: 1.0, 3: 0.9])
        XCTAssertTrue(Prepare.declaredDiameters("%\nT01\nX1000Y1000\n").isEmpty)
    }

    func testTheRequestOfAFileCarriesTheTextTheToolsOffAndNoHolesAtTheSameTime() throws {
        let body = try dict(Prepare.fileBody(side: .drill, name: "board 1", text: "T1\nX1Y1", tableText: "table", skipTools: [1, 2]))
        XCTAssertEqual(body["kind"] as? String, "drill")
        let files = try XCTUnwrap(body["files"] as? [String: Any])
        XCTAssertEqual(files["ncd"] as? String, "T1\nX1Y1")
        XCTAssertEqual(files["dtd"] as? String, "table")
        XCTAssertEqual((body["skip_tools"] as? [Int])?.count, 2)
        XCTAssertNil(body["holes"])
        let route = try dict(Prepare.fileBody(side: .route, name: "", text: "IN;", tableText: "", skipTools: []))
        XCTAssertEqual(route["kind"] as? String, "route")
        let rfiles = try XCTUnwrap(route["files"] as? [String: Any])
        XCTAssertEqual(rfiles["plt"] as? String, "IN;")
        XCTAssertNil(rfiles["rtd"])
        XCTAssertNil(route["skip_tools"])
        XCTAssertNil(route["name"])
    }

    func testTheRequestOfAProgramKeepsTheOutputsOffUnlessAsked() throws {
        let off = try dict(Prepare.gcodeBody(name: "frame", gcode: "G21\nM30\n", skip: 0, restoreOutputs: false))
        XCTAssertEqual(off["kind"] as? String, "gcode")
        XCTAssertEqual(off["skip"] as? Int, 0)
        XCTAssertEqual(off["restore_outputs"] as? Bool, false)
        let on = try dict(Prepare.gcodeBody(name: "frame", gcode: "G21\nM30\n", skip: 5, restoreOutputs: true))
        XCTAssertEqual(on["skip"] as? Int, 5)
        XCTAssertEqual(on["restore_outputs"] as? Bool, true)
        XCTAssertEqual(try dict(Prepare.gcodeBody(name: "", gcode: "x", skip: -3, restoreOutputs: false))["skip"] as? Int, 0)
    }

    func testWhatAMachineTakesFollowsItsConnection() {
        XCTAssertEqual(Prepare.works("node"), [.drill, .route, .both])
        XCTAssertEqual(Prepare.works("grbl"), [.gcode])
        XCTAssertEqual(Prepare.works("demo"), Work.allCases)
    }

    func testAProgramGoesOnFromTheLineTheJobSaysWithoutGoingBeyondTheProgram() {
        XCTAssertEqual(Prepare.lineCount("a\nb\nc\n"), 3)
        XCTAssertEqual(Prepare.lineCount("a\nb\nc"), 3)
        XCTAssertEqual(Prepare.lineCount(""), 0)
        XCTAssertEqual(Prepare.resumeSkip(line: 12, total: 40), 12)
        XCTAssertEqual(Prepare.resumeSkip(line: 99, total: 40), 40)
        XCTAssertEqual(Prepare.resumeSkip(line: -1, total: 40), 0)
        XCTAssertEqual(Prepare.jobName("board.NCD"), "board")
    }

    func testAGcodeJobCarriesItsLineAndTheHoldPause() throws {
        let job = try parseJob("""
        {"id":"g1","machine":"m","name":"frame","kind":"gcode","state":"waiting_operator","line":17,"pause":{"kind":"hold"},"items_total":40,"items_done":12,
         "view":{"kind":"gcode","items":40,"bounds_mm":[0,0,40,10],"estimate_s":5.0,"spindle_warnings":[{"code":"rpm_above_max","tool":0,"value":30000,"limit":24000}]}}
        """)
        XCTAssertEqual(job.summary.line, 17)
        XCTAssertEqual(job.summary.pause?.kind, "hold")
        XCTAssertEqual(job.view.items, 40)
        XCTAssertEqual(job.view.spindleWarnings.count, 1)
        XCTAssertEqual(try parseJobs("[{\"id\":\"a\",\"machine\":\"m\",\"kind\":\"drill\",\"state\":\"done\"}]").first?.line, 0)
    }
}
