import XCTest
@testable import Eh3dCore

/// More checks of the rules of the app from their edges: the preparation of a job, the link, the stops, the drawing and the summary (the same cases as the Android app).
final class MoreTests: XCTestCase {
    // ---- a view of a job, written as the server writes it

    private func view(_ json: String) throws -> JobView { try parsePreview(json) }

    private let threeHoles = """
    {"kind":"drill","name":"b","tools":[{"number":1,"spindle_rpm":24000,"count":2,"feed_mm_min":1000},{"number":2,"spindle_rpm":24000,"count":1,"feed_mm_min":1000}],
     "holes":[{"tool":1,"x_mm":1,"y_mm":1},{"tool":1,"x_mm":2,"y_mm":1},{"tool":2,"x_mm":3,"y_mm":1}],"paths":[],"bounds_mm":[1,1,3.04,1],"items":6,"hole_ends":[2,4,6],"estimate_s":9}
    """

    private let route = """
    {"kind":"route","name":"r","tools":[],"holes":[],"paths":[{"pen":1,"points_mm":[[0,0],[10,0]]},{"pen":1,"points_mm":[[10,10]]}],"items":4,"hole_ends":[],"estimate_s":9}
    """

    // ---- the tools of a job

    func testTheOrderOfTheToolsIsTheOrderTheWorkUsesThem() throws {
        let holes = try view("{\"kind\":\"drill\",\"holes\":[{\"tool\":3,\"x_mm\":0,\"y_mm\":0},{\"tool\":1,\"x_mm\":1,\"y_mm\":1},{\"tool\":3,\"x_mm\":2,\"y_mm\":2},{\"tool\":2,\"x_mm\":3,\"y_mm\":3}]}")
        XCTAssertEqual(Prepare.toolOrder(holes), [3, 1, 2])
        let pens = try view("{\"kind\":\"route\",\"paths\":[{\"pen\":2,\"points_mm\":[]},{\"pen\":1,\"points_mm\":[]},{\"pen\":2,\"points_mm\":[]}]}")
        XCTAssertEqual(Prepare.toolOrder(pens), [2, 1])
        let both = try view("{\"kind\":\"drill\",\"holes\":[{\"tool\":5,\"x_mm\":0,\"y_mm\":0}],\"paths\":[{\"pen\":1,\"points_mm\":[]},{\"pen\":5,\"points_mm\":[]},{\"pen\":2,\"points_mm\":[]}]}")
        XCTAssertEqual(Prepare.toolOrder(both), [5, 1, 2])
        let tools = try view("{\"kind\":\"drill\",\"tools\":[{\"number\":4},{\"number\":2},{\"number\":4}]}")
        XCTAssertEqual(Prepare.toolOrder(tools), [4, 2])
        XCTAssertEqual(Prepare.toolOrder(try view("{}")), [])
    }

    func testTheToolsLeftOutAreTheSwitchedOffOnesTheOnesBeforeTheStartAndTheUnknownOnesLast() {
        let order = [3, 1, 2]
        XCTAssertEqual(Prepare.skipTools(order: order, off: [2], startAt: 1), [3, 2])
        XCTAssertEqual(Prepare.skipTools(order: order, off: [], startAt: 2), [3, 1])
        XCTAssertEqual(Prepare.skipTools(order: order, off: [], startAt: 3), [])
        XCTAssertEqual(Prepare.skipTools(order: order, off: [], startAt: 99), [])
        XCTAssertEqual(Prepare.skipTools(order: [1], off: [9, 7], startAt: nil), [7, 9])
        XCTAssertEqual(Prepare.skipTools(order: [1, 2], off: [7, 1], startAt: nil), [1, 7])
        XCTAssertEqual(Prepare.skipTools(order: [], off: [], startAt: 1), [])
    }

    func testNothingIsLeftToDoOnlyWhenTheFileHasToolsAndEveryOneIsOut() {
        XCTAssertFalse(Prepare.nothingLeft(order: [], skipped: []))
        XCTAssertFalse(Prepare.nothingLeft(order: [1, 2], skipped: [1]))
        XCTAssertTrue(Prepare.nothingLeft(order: [1, 2], skipped: [2, 1]))
        XCTAssertTrue(Prepare.nothingLeft(order: [1], skipped: [1, 5]))
    }

    func testChoosingTheStartAndSwitchingAToolOffFollowTheRulesOfTheScreen() {
        XCTAssertEqual(Prepare.toggleStartAt(current: nil, tool: 3, off: []), 3)
        XCTAssertNil(Prepare.toggleStartAt(current: 3, tool: 3, off: []))
        XCTAssertEqual(Prepare.toggleStartAt(current: 3, tool: 2, off: []), 2)
        XCTAssertEqual(Prepare.toggleStartAt(current: 3, tool: 2, off: [2]), 3)
        XCTAssertNil(Prepare.toggleStartAt(current: nil, tool: 2, off: [2]))
        XCTAssertEqual(Prepare.toggleOff([1], tool: 2), [1, 2])
        XCTAssertEqual(Prepare.toggleOff([1, 2], tool: 2), [1])
        XCTAssertEqual(Prepare.toggleOff([2], tool: 2), [])
    }

    func testTheDiametersADrillingFileDeclaresAreReadFromItsHeader() {
        XCTAssertEqual(Prepare.declaredDiameters("M48\nT01C0.80\nT02C1.0\n  T12 C3.175\n%\nT01C9.9\n"), [1: 0.8, 2: 1.0, 12: 3.175])
        XCTAssertEqual(Prepare.declaredDiameters("T1C.8F200S50"), [1: 0.8])
        XCTAssertEqual(Prepare.declaredDiameters("M48\nMETRIC\n%\nT01\nX1Y1\n"), [:])
        XCTAssertEqual(Prepare.declaredDiameters(""), [:])
        XCTAssertEqual(Prepare.declaredDiameters(String(repeating: "\n", count: 20_000) + "T01C0.80\n"), [:])
        XCTAssertEqual(Prepare.declaredDiameters(String(repeating: "\n", count: 19_000) + "T01C0.80\n"), [1: 0.8])
        XCTAssertEqual(Prepare.declaredDiameters("G05 T01C0.80\n"), [:])
    }

    // ---- the requests

    private func json(_ text: String) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]) }

    func testTheRequestOfAFileHasItsSlotsAndTheNameAndTheSkipsOnlyWhenThereIsSomethingToSay() throws {
        let drill = try json(Prepare.fileBody(side: .drill, name: "Placa ñandú 日本", text: "M48\n", tableText: "tools", skipTools: [2, 5]))
        XCTAssertEqual(drill["kind"] as? String, "drill")
        let files = try XCTUnwrap(drill["files"] as? [String: Any])
        XCTAssertEqual(files["ncd"] as? String, "M48\n")
        XCTAssertEqual(files["dtd"] as? String, "tools")
        XCTAssertEqual(drill["name"] as? String, "Placa ñandú 日本")
        XCTAssertEqual(drill["skip_tools"] as? [Int], [2, 5])
        let routed = try json(Prepare.fileBody(side: .route, name: "  ", text: "IN;", tableText: "  \n", skipTools: []))
        XCTAssertEqual(routed["kind"] as? String, "route")
        let routedFiles = try XCTUnwrap(routed["files"] as? [String: Any])
        XCTAssertEqual(routedFiles["plt"] as? String, "IN;")
        XCTAssertNil(routedFiles["rtd"])
        XCTAssertNil(routedFiles["ncd"])
        XCTAssertNil(routed["name"])
        XCTAssertNil(routed["skip_tools"])
    }

    func testTheRequestOfAProgramNeverHasANegativeSkipAndTheOutputsAreRestoredOnlyWhenAsked() throws {
        let a = try json(Prepare.gcodeBody(name: "p", gcode: "G0 X1", skip: -5, restoreOutputs: false))
        XCTAssertEqual(a["skip"] as? Int, 0)
        XCTAssertEqual(a["restore_outputs"] as? Bool, false)
        XCTAssertEqual(a["name"] as? String, "p")
        let b = try json(Prepare.gcodeBody(name: "", gcode: "G0 X1\nM2", skip: 7, restoreOutputs: true))
        XCTAssertEqual(b["skip"] as? Int, 7)
        XCTAssertEqual(b["restore_outputs"] as? Bool, true)
        XCTAssertNil(b["name"])
        XCTAssertEqual(b["kind"] as? String, "gcode")
    }

    func testAProgramCountsItsLinesAsTheSkipDoesAndTheWayToGoOnNeverGoesPastTheEnd() {
        XCTAssertEqual(Prepare.lineCount(""), 0)
        XCTAssertEqual(Prepare.lineCount("a"), 1)
        XCTAssertEqual(Prepare.lineCount("a\n"), 1)
        XCTAssertEqual(Prepare.lineCount("\n"), 1)
        XCTAssertEqual(Prepare.lineCount("a\n\n"), 2)
        XCTAssertEqual(Prepare.lineCount("a\n\nb"), 3)
        XCTAssertEqual(Prepare.resumeSkip(line: -3, total: 10), 0)
        XCTAssertEqual(Prepare.resumeSkip(line: 99, total: 10), 10)
        XCTAssertEqual(Prepare.resumeSkip(line: 4, total: 10), 4)
        XCTAssertEqual(Prepare.resumeSkip(line: 4, total: -1), 0)
        XCTAssertEqual(Prepare.resumeSkip(line: 0, total: 0), 0)
    }

    func testEachConnectionTakesTheWorksItCanDo() {
        XCTAssertEqual(Prepare.works("grbl"), [.gcode])
        XCTAssertEqual(Prepare.works("node"), [.drill, .route, .both])
        XCTAssertEqual(Prepare.works("demo"), Work.allCases)
        XCTAssertEqual(Prepare.works("something-new"), Work.allCases)
        XCTAssertFalse(Prepare.machineTakes("node", .gcode))
        XCTAssertFalse(Prepare.machineTakes("grbl", .drill))
    }

    // ---- the link

    func testTheWaitBeforeARetryGrowsWithTheFailuresAndStopsAtTheLastOne() {
        let p = LinkPolicy()
        XCTAssertEqual([-5, 0, 2, 3, 4, 400].map { p.retryDelayMs($0) }, [1_500, 1_500, 3_000, 6_000, 10_000, 10_000])
        XCTAssertEqual(p.retryDelayMs(1), 1_500)
        XCTAssertEqual(LinkPolicy(offlineAfter: 2, staleAfterS: 5, retryMs: [1_000, 3_000]).retryDelayMs(50), 3_000)
    }

    func testOneFailureIsNotYetNoConnectionOldDataIsStaleTwoFailuresAreOfflineAndAnotherServiceIsTheWrongServer() {
        let ok = ServerLink().succeeded(nowMs: 10_000)
        XCTAssertEqual(ok.state(), .connected)
        XCTAssertEqual(ok.ageS(), 0)
        let one = ok.failed(.unreachable, nowMs: 12_000)
        XCTAssertEqual(one.state(), .connected)
        XCTAssertEqual(one.ageS(), 2)
        XCTAssertEqual(ok.failed(.unreachable, nowMs: 15_000).state(), .stale)
        XCTAssertEqual(ok.failed(.unreachable, nowMs: 14_999).state(), .connected)
        XCTAssertEqual(one.failed(.unreachable, nowMs: 13_000).state(), .offline)
        XCTAssertEqual(ok.failed(.wrongServer, nowMs: 11_000).state(), .wrongServer)
        XCTAssertEqual(ok.failed(.wrongServer, nowMs: 11_000).failed(.wrongServer, nowMs: 12_000).state(), .wrongServer)
        XCTAssertEqual(ok.failed(.wrongServer, nowMs: 11_000).failed(.unreachable, nowMs: 12_000).state(), .offline)
        XCTAssertEqual(one.succeeded(nowMs: 20_000).state(), .connected)
        XCTAssertEqual(one.succeeded(nowMs: 20_000).failures, 0)
    }

    func testWithoutAGoodAnswerTheAgeIsUnknownAndAClockThatWentBackNeverGivesANegativeAge() {
        XCTAssertNil(ServerLink().ageS())
        XCTAssertEqual(ServerLink().failed(.unreachable, nowMs: 1).failed(.unreachable, nowMs: 2).state(), .offline)
        XCTAssertEqual(ServerLink().failed(.unreachable, nowMs: 1).state(), .connected)
        var link = ServerLink()
        link.failures = 1
        link.lastOkMs = 50_000
        link.atMs = 10_000
        link.failure = .unreachable
        XCTAssertEqual(link.ageS(), 0)
    }

    func testAFailureIsToldApartByItsStatusAndItsCode() {
        XCTAssertEqual(classifyFailure(status: 0, code: ""), .unreachable)
        XCTAssertEqual(classifyFailure(status: 0, code: "bad_json"), .unreachable)
        XCTAssertEqual(classifyFailure(status: 200, code: "bad_json"), .wrongServer)
        XCTAssertEqual(classifyFailure(status: 500, code: "bad_json"), .wrongServer)
        XCTAssertEqual(classifyFailure(status: 500, code: ""), .unreachable)
        XCTAssertEqual(classifyFailure(status: 503, code: "unavailable"), .unreachable)
        XCTAssertEqual(classifyFailure(status: 404, code: "http_404"), .wrongServer)
        XCTAssertEqual(classifyFailure(status: 400, code: "http_400"), .wrongServer)
        for status in [401, 403, 429] { XCTAssertNil(classifyFailure(status: status, code: "http_\(status)")) }
        XCTAssertNil(classifyFailure(status: 404, code: "no_such_job"))
        XCTAssertNil(classifyFailure(status: 200, code: ""))
        XCTAssertNil(classifyFailure(status: 302, code: "http_302"))
        XCTAssertNil(classifyFailure(status: 399, code: "http_399"))
    }

    // ---- the stops

    private func fleet(state: String, job: Bool) throws -> Fleet {
        let jobText = job ? ",\"job\":{\"id\":\"j\",\"name\":\"n\",\"kind\":\"drill\",\"state\":\"running\",\"by\":\"ana\",\"items_done\":1,\"items_total\":2,\"percent\":50}" : ""
        return try parseFleet("{\"machines\":[{\"id\":\"m1\",\"name\":\"Bungard\",\"model\":\"ccd-mtc\",\"station\":\"taller\",\"connection\":\"node\",\"state\":\"\(state)\"\(jobText)}]}")
    }

    func testAStopIsOnlySentUntilTheFleetIsLookedAtAndThenItIsConfirmedOrTheMachineStillWorks() throws {
        func outcome(_ state: String, _ job: Bool, looked: Bool) throws -> StopOutcome { stopOutcome(try fleet(state: state, job: job).machine("m1"), looked: looked) }
        XCTAssertEqual(stopOutcome(nil, looked: false), .sent)
        XCTAssertEqual(try outcome("busy", true, looked: false), .sent)
        XCTAssertEqual(stopOutcome(nil, looked: true), .confirmed)
        XCTAssertEqual(try outcome("idle", false, looked: true), .confirmed)
        XCTAssertEqual(try outcome("idle", true, looked: true), .stillWorking)
        XCTAssertEqual(try outcome("busy", false, looked: true), .stillWorking)
        XCTAssertEqual(try outcome("waiting", true, looked: true), .stillWorking)
    }

    func testALookThatWasAskedForBeforeTheStopSaysNothingAboutIt() throws {
        let note = StopNote(machineId: "m1", machineName: "Bungard", atMs: 5_000)
        let idle = try fleet(state: "idle", job: false)
        XCTAssertEqual(followStops([note], fleet: idle, askedMs: 4_999, nowMs: 5_500), [note])
        XCTAssertEqual(followStops([note], fleet: idle, askedMs: 5_000, nowMs: 5_500).first?.outcome, .confirmed)
    }

    func testTheMachineThatStillWorksIsGivenThreeSecondsBeforeItIsSaidSo() throws {
        let note = StopNote(machineId: "m1", machineName: "Bungard", atMs: 1_000)
        let busy = try fleet(state: "busy", job: true)
        XCTAssertEqual(followStops([note], fleet: busy, askedMs: 1_500, nowMs: 3_999).first?.outcome, .sent)
        XCTAssertEqual(followStops([note], fleet: busy, askedMs: 1_500, nowMs: 4_000).first?.outcome, .stillWorking)
        let later = followStops([note], fleet: busy, askedMs: 1_500, nowMs: 600_000)
        XCTAssertEqual(later.first?.outcome, .stillWorking)
        XCTAssertNil(later.first?.resolvedMs)
    }

    func testAConfirmedStopStaysEightSecondsFromItsConfirmationAndThenGoes() throws {
        let note = StopNote(machineId: "m1", machineName: "Bungard", atMs: 1_000)
        let idle = try fleet(state: "idle", job: false)
        let first = followStops([note], fleet: idle, askedMs: 2_000, nowMs: 10_000)
        XCTAssertEqual(first.first?.resolvedMs, 10_000)
        let again = followStops(first, fleet: idle, askedMs: 14_000, nowMs: 17_999)
        XCTAssertEqual(again.first?.resolvedMs, 10_000)
        XCTAssertFalse(followStops(first, fleet: idle, askedMs: 18_000, nowMs: 18_000).isEmpty)
        XCTAssertTrue(followStops(first, fleet: idle, askedMs: 18_001, nowMs: 18_001).isEmpty)
        let gone = try parseFleet("{\"machines\":[]}")
        XCTAssertEqual(followStops([note], fleet: gone, askedMs: 2_000, nowMs: 10_000).first?.outcome, .confirmed)
        XCTAssertTrue(followStops([], fleet: idle, askedMs: 0, nowMs: 0).isEmpty)
    }

    // ---- the drawing

    func testTheHolesDoneAreTheHolesWhoseEndHasBeenReached() throws {
        let v = try view(threeHoles)
        XCTAssertEqual([-1, 0, 1, 2, 3, 4, 6, 100].map { holesDone(v, itemsDone: $0) }, [0, 0, 0, 1, 1, 2, 3, 3])
        XCTAssertEqual(holesDone(.empty, itemsDone: 10), 0)
    }

    func testADrillingJobIsAtTheNextHoleAndAtTheLastOneWhenAllAreDone() throws {
        let v = try view(threeHoles)
        XCTAssertEqual(headSpot(v, itemsDone: 0, itemsTotal: 6)?.x, 1)
        XCTAssertEqual(headSpot(v, itemsDone: 2, itemsTotal: 6)?.x, 2)
        XCTAssertEqual(headSpot(v, itemsDone: 4, itemsTotal: 6)?.x, 3)
        XCTAssertEqual(headSpot(v, itemsDone: 6, itemsTotal: 6)?.x, 3)
        XCTAssertEqual(headSpot(v, itemsDone: 600, itemsTotal: 6)?.x, 3)
        XCTAssertNil(headSpot(try view("{\"kind\":\"drill\"}"), itemsDone: 0, itemsTotal: 0))
        let asRoute = try view("{\"kind\":\"route\",\"holes\":[{\"tool\":1,\"x_mm\":4,\"y_mm\":1}],\"hole_ends\":[1]}")
        XCTAssertEqual(headSpot(asRoute, itemsDone: 0, itemsTotal: 1)?.x, 4)
    }

    func testARoutingJobMovesAlongItsPathsInProportionToTheItemsDone() throws {
        let v = try view(route)
        func at(_ done: Int, _ total: Int = 4) throws -> Spot { try XCTUnwrap(headSpot(v, itemsDone: done, itemsTotal: total)) }
        XCTAssertEqual(try at(0).x, 0, accuracy: 1e-9)
        XCTAssertEqual(try at(1).x, 5, accuracy: 1e-9)
        XCTAssertEqual(try at(2).x, 10, accuracy: 1e-9)
        XCTAssertEqual(try at(3).y, 5, accuracy: 1e-9)
        XCTAssertEqual(try at(4).y, 10, accuracy: 1e-9)
        XCTAssertEqual(try at(99).y, 10, accuracy: 1e-9)
        XCTAssertEqual(try at(-3).x, 0, accuracy: 1e-9)
        XCTAssertEqual(try at(1, 0).x, 5, accuracy: 1e-9)
        let single = try view("{\"kind\":\"route\",\"paths\":[{\"pen\":1,\"points_mm\":[[7,8]]}],\"items\":0}")
        XCTAssertEqual(headSpot(single, itemsDone: 5, itemsTotal: 0)?.x, 7)
        XCTAssertNil(headSpot(try view("{\"kind\":\"route\",\"paths\":[{\"pen\":1,\"points_mm\":[]}]}"), itemsDone: 1, itemsTotal: 1))
    }

    func testThePointsReachedFollowTheItemsAndNeverGoPastThePaths() throws {
        let v = try view("{\"kind\":\"route\",\"paths\":[{\"pen\":1,\"points_mm\":[[0,0],[1,0],[2,0],[3,0]]},{\"pen\":2,\"points_mm\":[[0,0],[0,1]]}],\"items\":12}")
        XCTAssertEqual([0, 6, 12, 99, -4].map { pointsReached(v, itemsDone: $0, itemsTotal: 12) }, [0, 3, 6, 6, 0])
        XCTAssertEqual(pointsReached(v, itemsDone: 6, itemsTotal: 0), 3)
        XCTAssertEqual(pointsReached(try view("{\"kind\":\"route\",\"items\":5}"), itemsDone: 3, itemsTotal: 5), 0)
    }

    func testTheBoxOfTheDrawingHasAMarginAFloorOfAMillimetreAndATableWhenThereIsNoWork() throws {
        XCTAssertEqual(drawingBox(.empty), [-4, -4, 104, 84])
        XCTAssertEqual(drawingBox(try view("{\"bounds_mm\":[5,5,5,5]}")), [1, 1, 10, 10])
        XCTAssertEqual(drawingBox(try view("{\"bounds_mm\":[0,0,50,20]}"), marginMm: 0), [0, 0, 50, 20])
        XCTAssertEqual(drawingBox(try view("{\"bounds_mm\":[0,0,10,10]}"), marginMm: 3), [-3, -3, 13, 13])
    }

    func testAPlanFitsTheBoxInTheCanvasCentredWithYGoingUp() {
        let plan = Plan(box: [0, 0, 100, 50], width: 200, height: 200)
        XCTAssertEqual(plan.scale, 2, accuracy: 1e-9)
        XCTAssertEqual(plan.x(0), 0, accuracy: 1e-9)
        XCTAssertEqual(plan.x(100), 200, accuracy: 1e-9)
        XCTAssertEqual(plan.y(0), 150, accuracy: 1e-9)
        XCTAssertEqual(plan.y(50), 50, accuracy: 1e-9)
        let tall = Plan(box: [-10, -10, 10, 30], width: 100, height: 400)
        XCTAssertEqual(tall.scale, 5, accuracy: 1e-9)
        XCTAssertEqual(tall.x(-10), 0, accuracy: 1e-9)
        XCTAssertEqual(tall.y(10), 200, accuracy: 1e-9)
    }

    func testTheIsometricViewFromAboveIsThePlanAndTheScaleThatFitsGrowsWithTheCanvas() {
        let top = Iso(cx: 50, cy: 25, yaw: 0, pitch: .pi / 2)
        let p = top.project(60, 35)
        XCTAssertEqual(p.sx, 10, accuracy: 1e-9)
        XCTAssertEqual(p.sy, -10, accuracy: 1e-9)
        XCTAssertEqual(top.fit(tableW: 100, tableD: 50, zMax: 0, width: 200, height: 200, marginPx: 0), 2, accuracy: 1e-9)
        XCTAssertGreaterThan(top.fit(tableW: 100, tableD: 50, zMax: 0, width: 400, height: 400), top.fit(tableW: 100, tableD: 50, zMax: 0, width: 200, height: 200))
        XCTAssertGreaterThan(top.fit(tableW: 0, tableD: 0, zMax: 0, width: 200, height: 200), 0)
        XCTAssertEqual(Iso(cx: 0, cy: 0, yaw: 0, pitch: 0).project(0, 0, 10).sy, -10, accuracy: 1e-9)
        let turned = Iso(cx: 50, cy: 25, yaw: 2 * .pi, pitch: 0.5).project(70, 20, 3)
        let still = Iso(cx: 50, cy: 25, yaw: 0, pitch: 0.5).project(70, 20, 3)
        XCTAssertEqual(turned.sx, still.sx, accuracy: 1e-9)
        XCTAssertEqual(turned.sy, still.sy, accuracy: 1e-9)
    }

    func testATimeIsWrittenInHoursAndMinutesMinutesAndSecondsOrSeconds() {
        XCTAssertEqual([0, -5, 59.9, 60, 61, 3599, 3600, 3661, 100_000].map { formatDuration($0) },
                       ["0 s", "0 s", "59 s", "1 min 00 s", "1 min 01 s", "59 min 59 s", "1 h 00 min", "1 h 01 min", "27 h 46 min"])
        XCTAssertEqual(formatDuration(.nan), "0 s")
        XCTAssertEqual(formatDuration(.infinity), "0 s")
    }

    // ---- the summary

    func testNumbersAreRoundedHalfUpToOneDecimalAndWrittenAsShortAsTheyCanBe() {
        XCTAssertEqual(round1(0.25), 0.3, accuracy: 1e-12)
        XCTAssertEqual(round1(-0.25), -0.2, accuracy: 1e-12)
        XCTAssertEqual(round1(9.96), 10, accuracy: 1e-12)
        XCTAssertEqual(round1(0.04), 0, accuracy: 1e-12)
        XCTAssertEqual([10, 1.5, 0, -2.5, 0.1, 1_000_000].map { plain($0) }, ["10", "1.5", "0", "-2.5", "0.1", "1000000"])
        XCTAssertEqual([Double.nan, .infinity, -.infinity].map { plain($0) }, ["0", "0", "0"])
        XCTAssertEqual(plain(-0.0), "0")
    }

    func testTheReachOfTheAxesIsOnOneLineWithADotForTheDecimalsInAnyLanguage() throws {
        let v = try view("{\"kind\":\"drill\",\"dry_run\":{\"min_mm\":[0,0,-1.5],\"max_mm\":[30,20,25.8],\"end_mm\":[0,0,0],\"steps\":10,\"seconds\":1,\"within_course\":true}}")
        XCTAssertEqual(reachLine(try XCTUnwrap(v.dryRun)), "X 0.0..30.0   Y 0.0..20.0   Z -1.5..25.8")
        let short = try view("{\"kind\":\"drill\",\"dry_run\":{\"min_mm\":[1],\"max_mm\":[2],\"steps\":10,\"seconds\":1}}")
        XCTAssertEqual(reachLine(try XCTUnwrap(short.dryRun)), "X 1.0..2.0   Y 0.0..0.0   Z 0.0..0.0")
    }

    func testTheSummaryCountsWhatTheKindOfJobCountsAndTakesTheTimeFromTheDryRunBeforeTheEstimate() throws {
        let drillText = "{\"kind\":\"drill\",\"tools\":[{\"number\":1},{\"number\":2}],\"holes\":[{\"tool\":1,\"x_mm\":1,\"y_mm\":1},{\"tool\":1,\"x_mm\":2,\"y_mm\":1},{\"tool\":2,\"x_mm\":3,\"y_mm\":1}],\"bounds_mm\":[1,1,3.04,1],\"estimate_s\":9,\"dry_run\":{\"min_mm\":[0,0,0],\"max_mm\":[10,10,1],\"end_mm\":[0,0,0],\"steps\":100,\"seconds\":42,\"within_course\":false}}"
        let drill = startSummary(try view(drillText))
        XCTAssertEqual(drill.count, 3)
        XCTAssertEqual(drill.tools, 2)
        XCTAssertEqual(drill.sizeMm, [2.0, 0.0])
        XCTAssertEqual(drill.seconds, 42)
        XCTAssertTrue(drill.outOfCourse)
        let routed = startSummary(try view("{\"kind\":\"route\",\"paths\":[{\"pen\":1,\"points_mm\":[]},{\"pen\":1,\"points_mm\":[]}],\"estimate_s\":9}"))
        XCTAssertEqual(routed.count, 2)
        XCTAssertEqual(routed.seconds, 9)
        XCTAssertFalse(routed.outOfCourse)
        XCTAssertNil(routed.sizeMm)
        let program = startSummary(try view("{\"kind\":\"gcode\",\"items\":77}"))
        XCTAssertEqual(program.count, 77)
        XCTAssertNil(program.seconds)
        let inside = try view("{\"kind\":\"drill\",\"dry_run\":{\"min_mm\":[0,0,0],\"max_mm\":[1,1,1],\"end_mm\":[0,0,0],\"steps\":1,\"seconds\":1,\"within_course\":true}}")
        XCTAssertFalse(startSummary(inside).outOfCourse)
    }

    func testEveryWarningGivesTheNumbersOfItsPhraseInOrderAndAnUnknownOneGivesItsCode() {
        func w(_ code: String, _ axis: String, _ values: [Double]) -> WorkWarning { WorkWarning(code: code, axis: axis, values: values) }
        XCTAssertEqual(warningArgs(w("tiny", "", [0.46, 0.25])), ["0.5", "0.3"])
        XCTAssertEqual(warningArgs(w("too_big", "", [400, 300.04, 299.96, 200])), ["400", "300", "300", "200"])
        XCTAssertEqual(warningArgs(w("far", "", [123.45])), ["123.5"])
        XCTAssertEqual(warningArgs(w("scale", "", [1.02, 1])), ["1.02", "1"])
        XCTAssertEqual(warningArgs(w("out_of_course", "X", [5.25])), ["X", "5.3"])
        XCTAssertEqual(warningArgs(w("something_new", "", [1])), ["something_new"])
        XCTAssertEqual(warningArgs(w("tiny", "", [])), ["0", "0"])
        XCTAssertEqual(warningArgs(w("scale", "", [])), ["0", "0"])
        XCTAssertEqual(warningArgs(w("out_of_course", "Y", [])), ["Y", "0"])
    }

    // ---- the version of a release

    func testAVersionIsThreeOrFourPlainNumbersAndNothingElseIsOne() {
        XCTAssertEqual(SemanticVersion.parse("1.2.3"), [1, 2, 3, 0])
        XCTAssertEqual(SemanticVersion.parse("v0.8.0.1"), [0, 8, 0, 1])
        XCTAssertEqual(SemanticVersion.parse("  0.0.0 "), [0, 0, 0, 0])
        for bad in ["", "v", "1", "1.2", "1.2.3.4.5", "01.2.3", "1.02.3", "1.2.3-rc1", "1.2.3+b5", "V1.2.3", "vv1.2.3", "1.2.3.", ".1.2.3", "1..3", "1.2.x", "1,2,3", "latest", "1.2.\u{00BD}", "\u{0661}.\u{0662}.\u{0663}", "-1.2.3", "99999999999999999999.0.0"] {
            XCTAssertNil(SemanticVersion.parse(bad), bad)
        }
    }

    func testANewerVersionIsNewerByNumberAndNeverByText() {
        XCTAssertTrue(SemanticVersion.isNewer("0.10.0", than: "0.9.0"))
        XCTAssertFalse(SemanticVersion.isNewer("0.9.0", than: "0.10.0"))
        XCTAssertTrue(SemanticVersion.isNewer("0.8.0.1", than: "0.8.0"))
        XCTAssertFalse(SemanticVersion.isNewer("0.8.0", than: "0.8.0.0"))
        XCTAssertFalse(SemanticVersion.isNewer("0.8.0.0", than: "0.8.0"))
        XCTAssertTrue(SemanticVersion.isNewer("1.0.0", than: "0.99.99.99"))
        XCTAssertFalse(SemanticVersion.isNewer("2.0.0-rc1", than: "1.0.0"))
        XCTAssertFalse(SemanticVersion.isNewer("1.0.0", than: "garbage"))
        XCTAssertFalse(SemanticVersion.isNewer("garbage", than: "1.0.0"))
    }

    // ---- the addresses

    func testAnAddressWithAPortThatDoesNotExistIsNotAnAddress() {
        for url in ["http://192.168.0.5:0", "http://192.168.0.5:65536", "https://eh3d.example:70000"] { XCTAssertNil(ServerEndpoint.parse(url), url) }
        XCTAssertEqual(ServerEndpoint.parse("http://192.168.0.5:65535")?.origin, "http://192.168.0.5:65535")
        XCTAssertEqual(ServerEndpoint.parse("https://eh3d.example")?.origin, "https://eh3d.example")
    }

    func testATypedHostAndPortArePutTogetherSafely() {
        XCTAssertEqual(ServerEndpoint.fromHostAndPort("  192.168.0.5  ", " 18200 ")?.origin, "http://192.168.0.5:18200")
        XCTAssertEqual(ServerEndpoint.fromHostAndPort("localhost", "1")?.origin, "http://localhost:1")
        XCTAssertEqual(ServerEndpoint.fromHostAndPort("HTTP://192.168.0.5/some/path", "65535")?.origin, "http://192.168.0.5:65535")
        for port in ["", "0", "-1", "65536", "abc", "18 200", "1e3"] { XCTAssertNil(ServerEndpoint.fromHostAndPort("192.168.0.5", port), port) }
        for host in ["", " ", "user@192.168.0.5", "192.168.0.5?x=1", "192.168.0.5#f"] { XCTAssertNil(ServerEndpoint.fromHostAndPort(host, "18200"), host) }
    }

    func testTheTypedAddressNeedsASecureConnectionOnlyOutsideTheHouseAndABarePublicAddressIsFlagged() {
        XCTAssertFalse(ServerEndpoint.needsSecureConnection(""))
        XCTAssertFalse(ServerEndpoint.needsSecureConnection("192.168.0.5"))
        XCTAssertFalse(ServerEndpoint.needsSecureConnection("http://10.0.0.1:18200/api"))
        XCTAssertFalse(ServerEndpoint.needsSecureConnection("HTTPS://eh3d.example"))
        XCTAssertTrue(ServerEndpoint.needsSecureConnection("eh3d.example"))
        XCTAssertTrue(ServerEndpoint.needsSecureConnection("8.8.8.8:18200"))
        XCTAssertTrue(ServerEndpoint.needsSecureConnection("http://eh3d.example"))
        XCTAssertTrue(ServerEndpoint.usesPublicIpAddress("8.8.8.8"))
        XCTAssertTrue(ServerEndpoint.usesPublicIpAddress("https://8.8.8.8:443"))
        XCTAssertFalse(ServerEndpoint.usesPublicIpAddress("192.168.0.5"))
        XCTAssertFalse(ServerEndpoint.usesPublicIpAddress("eh3d.example"))
        XCTAssertFalse(ServerEndpoint.usesPublicIpAddress("  "))
    }

    func testTheTwoAddressesOfAnInstallationChooseByPlaceAndOfferTheOtherOne() throws {
        let home = try XCTUnwrap(ServerEndpoint.parse("http://192.168.0.5:18200"))
        let away = try XCTUnwrap(ServerEndpoint.parse("https://eh3d.example"))
        let both = DualEndpoint(home: home, away: away)
        XCTAssertEqual(both.chosen(for: .home), home)
        XCTAssertEqual(both.chosen(for: .away), away)
        XCTAssertEqual(both.chosen(for: .unknown), home)
        XCTAssertEqual(both.alternative(to: home), away)
        XCTAssertEqual(both.alternative(to: away), home)
        let onlyAway = DualEndpoint(home: nil, away: away)
        XCTAssertEqual(onlyAway.chosen(for: .home), away)
        XCTAssertEqual(onlyAway.chosen(for: .unknown), away)
        XCTAssertNil(onlyAway.alternative(to: away))
        XCTAssertNil(DualEndpoint(home: nil, away: nil).chosen(for: .away))
        XCTAssertNil(DualEndpoint(home: home, away: home).alternative(to: home))
    }
}
