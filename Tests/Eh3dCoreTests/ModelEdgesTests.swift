import XCTest
@testable import Eh3dCore

/// The readers of the answers of the server from their edges: what is missing, null, of the wrong kind or from an older server (the same cases as the Android app).
final class ModelEdgesTests: XCTestCase {
    // ---- the states of a job

    func testTheStatesAJobCanGoOnFromAreTheOnesThatStoppedBeforeTheEnd() {
        XCTAssertTrue(JobStates.canGoOn("cancelled"))
        XCTAssertTrue(JobStates.canGoOn("failed"))
        for state in ["ready", "connecting", "running", "waiting_operator", "done", "", "other"] { XCTAssertFalse(JobStates.canGoOn(state), state) }
    }

    func testAJobIsActiveWhileItConnectsRunsOrWaits() {
        for state in ["connecting", "running", "waiting_operator"] { XCTAssertTrue(JobStates.active(state), state) }
        for state in ["ready", "done", "cancelled", "failed", ""] { XCTAssertFalse(JobStates.active(state), state) }
    }

    func testAJobIsFinishedWhenItIsDoneCancelledOrFailedAndNeverBothActiveAndFinished() {
        for state in ["done", "cancelled", "failed"] { XCTAssertTrue(JobStates.finished(state), state) }
        for state in ["ready", "connecting", "running", "waiting_operator"] { XCTAssertFalse(JobStates.finished(state), state) }
        for state in ["ready", "connecting", "running", "waiting_operator", "done", "cancelled", "failed"] { XCTAssertFalse(JobStates.active(state) && JobStates.finished(state), state) }
    }

    // ---- how far a job is

    private func remaining(percent: Int, estimate: Double) throws -> Double {
        let fleet = try parseFleet("{\"machines\":[{\"id\":\"a\",\"job\":{\"percent\":\(percent),\"estimate_s\":\(estimate)}}]}")
        return try XCTUnwrap(fleet.machines[0].job).remainingS
    }

    func testWhatIsLeftOfTheEstimateFollowsThePercentAndNeverGoesBelowZeroOrAboveTheEstimate() throws {
        XCTAssertEqual(try remaining(percent: 50, estimate: 100), 50, accuracy: 1e-9)
        XCTAssertEqual(try remaining(percent: 0, estimate: 100), 100, accuracy: 1e-9)
        XCTAssertEqual(try remaining(percent: 100, estimate: 100), 0, accuracy: 1e-9)
        XCTAssertEqual(try remaining(percent: -20, estimate: 100), 100, accuracy: 1e-9)
        XCTAssertEqual(try remaining(percent: 250, estimate: 100), 0, accuracy: 1e-9)
    }

    func testWithNoEstimateNothingIsLeftToWaitFor() throws {
        XCTAssertEqual(try remaining(percent: 10, estimate: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(try remaining(percent: 10, estimate: -5), 0, accuracy: 1e-9)
    }

    private func percentOfListed(done: Int, total: Int) throws -> Int {
        try parseJobs("[{\"id\":\"a\",\"items_done\":\(done),\"items_total\":\(total)}]")[0].percent
    }

    func testThePercentOfAListedJobIsItsItemsDoneOverItsItemsTotal() throws {
        XCTAssertEqual(try percentOfListed(done: 5, total: 0), 0)
        XCTAssertEqual(try percentOfListed(done: 0, total: 10), 0)
        XCTAssertEqual(try percentOfListed(done: 5, total: 10), 50)
        XCTAssertEqual(try percentOfListed(done: 1, total: 3), 33)
        XCTAssertEqual(try percentOfListed(done: 10, total: 10), 100)
        XCTAssertEqual(try percentOfListed(done: 12, total: 10), 100)
        XCTAssertEqual(try percentOfListed(done: -3, total: 10), 0)
    }

    // ---- the fleet

    func testAFleetWithNoSummaryCountsItsMachinesByState() throws {
        let fleet = try parseFleet(#"{"machines":[{"id":"a","state":"idle"},{"id":"b","state":"busy"},{"id":"c","state":"busy"},{"id":"d","state":"waiting"}]}"#)
        XCTAssertEqual([fleet.idle, fleet.busy, fleet.waiting], [1, 2, 1])
    }

    func testTheSummaryOfTheServerWinsOverTheCountOfTheMachines() throws {
        let fleet = try parseFleet(#"{"machines":[{"id":"a","state":"idle"}],"summary":{"idle":7,"busy":8,"waiting":9}}"#)
        XCTAssertEqual([fleet.idle, fleet.busy, fleet.waiting], [7, 8, 9])
    }

    func testAMachineWithNoStateIsIdleAndOneWithNoJobHasNone() throws {
        let machine = try parseFleet(#"{"machines":[{"id":"a","name":"Mill"}]}"#).machines[0]
        XCTAssertEqual(machine.state, "idle")
        XCTAssertNil(machine.job)
        XCTAssertEqual(machine.name, "Mill")
        XCTAssertEqual(machine.model, "")
        XCTAssertEqual(machine.ready, 0)
    }

    func testTheFleetCanFindAMachineByItsId() throws {
        let fleet = try parseFleet(#"{"machines":[{"id":"a"},{"id":"b"}]}"#)
        XCTAssertEqual(fleet.machine("b")?.id, "b")
        XCTAssertNil(fleet.machine("zzz"))
        XCTAssertEqual(Fleet.empty.machines.count, 0)
    }

    func testAFleetThatIsNotAJsonObjectIsAnErrorTheCallerCanCatch() {
        XCTAssertThrowsError(try parseFleet("<html>")) { error in
            XCTAssertEqual((error as? ApiError)?.code, "bad_json")
        }
        XCTAssertThrowsError(try parseFleet("[]"))
        XCTAssertThrowsError(try parseFleet(""))
    }

    func testAListOfMachinesWithOddEntriesDoesNotBreakTheScreens() throws {
        XCTAssertNoThrow(try parseFleet(#"{"machines":[1,"x",null]}"#))
        XCTAssertEqual(try parseFleet(#"{"machines":"none"}"#).machines.count, 0)
        XCTAssertEqual(try parseFleet("{}").machines.count, 0)
    }

    func testTheStateOfAMachineIsTheStateOfItsJobElseItsOwn() throws {
        let fleet = try parseFleet(#"{"machines":[{"id":"a","state":"busy","job":{"id":"j","state":"running"}},{"id":"b","state":"idle"}]}"#)
        XCTAssertEqual(fleetStates(fleet), ["a": "running", "b": "idle"])
    }

    func testThereAreNoNoticesWhenThereWasNothingToCompareWith() throws {
        let fleet = try parseFleet(#"{"machines":[{"id":"a","state":"busy","job":{"id":"j","state":"waiting_operator"}}]}"#)
        XCTAssertTrue(fleetNotices(before: [:], now: fleet).isEmpty)
    }

    func testAMachineThatWasNotThereBeforeGivesNoNotice() throws {
        let fleet = try parseFleet(#"{"machines":[{"id":"new","state":"busy","job":{"id":"j","state":"waiting_operator"}}]}"#)
        XCTAssertTrue(fleetNotices(before: ["old": "running"], now: fleet).isEmpty)
    }

    func testWaitingForTheOperatorAndEndingAreToldOnceAndASteadyStateIsNotTold() throws {
        let waiting = try parseFleet(#"{"machines":[{"id":"a","name":"Mill","state":"waiting","job":{"id":"j","state":"waiting_operator"}}]}"#)
        XCTAssertEqual(fleetNotices(before: ["a": "running"], now: waiting).first?.kind, .waiting)
        XCTAssertEqual(fleetNotices(before: ["a": "running"], now: waiting).count, 1)
        XCTAssertTrue(fleetNotices(before: ["a": "waiting_operator"], now: waiting).isEmpty)
        let ended = try parseFleet(#"{"machines":[{"id":"a","name":"Mill","state":"idle"}]}"#)
        let notice = try XCTUnwrap(fleetNotices(before: ["a": "running"], now: ended).first)
        XCTAssertEqual(notice, Notice(machineId: "a", machineName: "Mill", kind: .ended))
        XCTAssertTrue(fleetNotices(before: ["a": "ready"], now: ended).isEmpty)
    }

    // ---- the jobs

    func testAFinishedJobInTheListHasAFinishTimeAndAnUnfinishedOneHasNone() throws {
        let jobs = try parseJobs(#"[{"id":"a","created":100,"finished":160},{"id":"b","created":200,"finished":null},{"id":"c","created":300}]"#)
        XCTAssertEqual(jobs[0].finished, 160)
        XCTAssertNil(jobs[1].finished)
        XCTAssertNil(jobs[2].finished)
        XCTAssertEqual(jobs.map(\.created), [100, 200, 300])
    }

    func testAnEmptyListOfJobsIsEmptyAndSomethingElseIsAnError() throws {
        XCTAssertEqual(try parseJobs("[]").count, 0)
        XCTAssertThrowsError(try parseJobs("{}"))
        XCTAssertThrowsError(try parseJobs("nope"))
    }

    func testAJobFromAnOlderServerHasNoLineNoResumedFromAndNobodyWhoStartedIt() throws {
        let job = try parseJobs(#"[{"id":"a","state":"cancelled"}]"#)[0]
        XCTAssertEqual(job.line, 0)
        XCTAssertEqual(job.resumedFrom, "")
        XCTAssertEqual(job.startedBy, "")
        XCTAssertEqual(job.stoppedBy, "")
        XCTAssertNil(job.pause)
    }

    func testAJobWithoutAViewGetsTheEmptyView() throws {
        let job = try parseJob(#"{"id":"a"}"#)
        XCTAssertEqual(job.view, JobView.empty)
        XCTAssertTrue(job.view.holes.isEmpty)
        XCTAssertNil(job.view.bounds)
    }

    func testAPauseWithoutAToolHasNoToolNumber() throws {
        let pause = try XCTUnwrap(try parseJobs(#"[{"id":"a","pause":{"kind":"spindle_start"}}]"#)[0].pause)
        XCTAssertEqual(pause, Pause(kind: "spindle_start", tool: nil))
        XCTAssertEqual(try parseJobs(#"[{"id":"a","pause":{"kind":"hold","question":"q0a1b2c3"}}]"#)[0].pause?.question, "q0a1b2c3")
        XCTAssertEqual(try parseJobs(#"[{"id":"a","pause":{"kind":"tool_change","tool":3}}]"#)[0].pause?.tool, 3)
    }

    // ---- the view of a job

    func testTheBoundsOfAViewNeedFourNumbers() throws {
        XCTAssertNil(try parsePreview(#"{"bounds_mm":[0,0,10]}"#).bounds)
        XCTAssertNil(try parsePreview("{}").bounds)
        XCTAssertEqual(try parsePreview(#"{"bounds_mm":[1,2,11,22]}"#).bounds, [1, 2, 11, 22])
        XCTAssertEqual(try parsePreview(#"{"bounds_mm":[1,2,11,22,99]}"#).bounds, [1, 2, 11, 22])
    }

    func testAPointOfAPathWithASingleNumberIsDropped() throws {
        let view = try parsePreview(#"{"paths":[{"pen":2,"points_mm":[[1,2],[3],[4,5]]}]}"#)
        XCTAssertEqual(view.paths[0].points, [Spot(x: 1, y: 2), Spot(x: 4, y: 5)])
        XCTAssertEqual(view.paths[0].pen, 2)
    }

    func testAViewWithoutListsIsEmptyAndDoesNotThrow() throws {
        let view = try parsePreview(#"{"kind":"route","name":"p","items":4}"#)
        XCTAssertEqual(view.items, 4)
        XCTAssertTrue(view.tools.isEmpty && view.holes.isEmpty && view.paths.isEmpty && view.holeEnds.isEmpty)
        XCTAssertTrue(view.skippedTools.isEmpty && view.spindleWarnings.isEmpty && view.warnings.isEmpty)
        XCTAssertNil(view.dryRun)
    }

    func testTheDryRunKeepsItsThreeAxesAndCountsAMissingCourseFlagAsWithinTheCourse() throws {
        let dry = try XCTUnwrap(try parsePreview(#"{"dry_run":{"min_mm":[0,0,0],"max_mm":[10,20,5],"end_mm":[1,1,1],"steps":1234,"seconds":12.5}}"#).dryRun)
        XCTAssertEqual(dry.maxMm, [10, 20, 5])
        XCTAssertEqual(dry.steps, 1234)
        XCTAssertEqual(dry.seconds, 12.5, accuracy: 1e-9)
        XCTAssertTrue(dry.withinCourse)
        let out = try XCTUnwrap(try parsePreview(#"{"dry_run":{"within_course":false}}"#).dryRun)
        XCTAssertFalse(out.withinCourse)
        XCTAssertTrue(out.minMm.isEmpty)
    }

    func testAWarningOfTheWorkKeepsItsValuesInOrderAndItsAxis() throws {
        let warning = try XCTUnwrap(try parsePreview(#"{"warnings":[{"code":"out_of_course","axis":"Z","values":[26.5,25]}]}"#).warnings.first)
        XCTAssertEqual(warning, WorkWarning(code: "out_of_course", axis: "Z", values: [26.5, 25]))
    }

    func testAToolWithoutDepthOrIterationsHasNone() throws {
        let tool = try XCTUnwrap(try parsePreview(#"{"tools":[{"number":1,"spindle_rpm":24000,"count":5,"feed_mm_min":300}]}"#).tools.first)
        XCTAssertNil(tool.depthMm)
        XCTAssertNil(tool.iterations)
        XCTAssertEqual(tool.spindleRpm, 24000)
    }

    func testAPreviewThatCarriesAViewIsThatViewAndABareOneIsItself() throws {
        XCTAssertEqual(try parsePreview(#"{"view":{"kind":"drill"}}"#).kind, "drill")
        XCTAssertEqual(try parsePreview(#"{"kind":"route"}"#).kind, "route")
    }

    func testTheSwitchForTheDollarLinesIsOffUnlessTheServerSaysOn() throws {
        XCTAssertTrue(try parseAllowDollar(#"{"allow_dollar":true}"#))
        XCTAssertFalse(try parseAllowDollar(#"{"allow_dollar":false}"#))
        XCTAssertFalse(try parseAllowDollar("{}"))
    }

    // ---- the head, the check, the ring, the measure and the spindle

    func testTheHeadOfAnOlderNodeHasTheDefaultsAndNoTemperature() throws {
        let head = try parseHead(#"{"node":"n1"}"#)
        XCTAssertEqual(head.node, "n1")
        XCTAssertFalse(head.camera)
        XCTAssertNil(head.tempC)
        XCTAssertEqual(head.heat, "ok")
        XCTAssertEqual(head.laserAgeMs, -1)
        XCTAssertEqual(head.tempSensors, 0)
        XCTAssertFalse(head.light)
    }

    func testTheTemperatureSensorsAreCountedFromTheListOfTheirAddressesAndBlanksDoNotCount() throws {
        XCTAssertEqual(try parseHead(#"{"temp_roms":"28aa,28bb"}"#).tempSensors, 2)
        XCTAssertEqual(try parseHead(#"{"temp_roms":"28aa, ,"}"#).tempSensors, 1)
        XCTAssertEqual(try parseHead(#"{"temp_roms":""}"#).tempSensors, 0)
    }

    func testThePhraseForTheLaserFollowsTheStatusAndAnUnknownStatusIsNotValid() {
        XCTAssertEqual(laserStatusPhrase(""), "")
        XCTAssertEqual(laserStatusPhrase("valid"), "Láser: lectura válida")
        XCTAssertEqual(laserStatusPhrase("signal_low"), "Láser: señal débil")
        XCTAssertEqual(laserStatusPhrase("sigma_high"), "Láser: demasiada dispersión")
        XCTAssertEqual(laserStatusPhrase("out_of_range"), "Láser: fuera de rango")
        XCTAssertEqual(laserStatusPhrase("sensor_fault"), "Láser: fallo del sensor")
        XCTAssertEqual(laserStatusPhrase("none"), "Láser: sin lecturas todavía")
        XCTAssertEqual(laserStatusPhrase("something new"), "Láser: lectura no válida")
    }

    func testThePhraseForTheSpeedSignalIsEmptyForAnUnknownQuality() {
        XCTAssertEqual(rpmQualityPhrase("good"), "Señal de rpm buena")
        XCTAssertEqual(rpmQualityPhrase("noisy"), "Señal de rpm con ruido")
        XCTAssertEqual(rpmQualityPhrase("none"), "Sin señal de rpm")
        XCTAssertEqual(rpmQualityPhrase(""), "")
        XCTAssertEqual(rpmQualityPhrase("something new"), "")
    }

    func testACheckWithoutFindingsOrHolesIsUnknownAndAnEmptyOneHasNoChannel() throws {
        let quality = try parseQuality("{}")
        XCTAssertEqual(quality.verdict, "unknown")
        XCTAssertEqual(quality.holesTotal, 0)
        XCTAssertNil(quality.channelMm)
        XCTAssertTrue(quality.findings.isEmpty)
    }

    func testAFindingWithoutTheFailsMemberFailsAndOneThatNamesNoHoleHasNone() throws {
        let quality = try parseQuality(#"{"verdict":"not_ok","findings":[{"code":"mill_pinched"},{"code":"hole_missing","hole":2,"fails":false}]}"#)
        XCTAssertEqual(quality.findings[0], Finding(code: "mill_pinched", hole: nil, fails: true))
        XCTAssertEqual(quality.findings[1], Finding(code: "hole_missing", hole: 2, fails: false))
    }

    func testTheRingIsOffAtLevelZeroAndItsCeilingIsEightyUnlessTheNodeSays() throws {
        XCTAssertEqual(try parseRingLight("{}"), RingLight(on: false, level: 0, maxLevel: 80))
        XCTAssertEqual(try parseRingLight(#"{"on":true,"level":40,"max_level":60}"#), RingLight(on: true, level: 40, maxLevel: 60))
    }

    func testAMeasureThatFailedKeepsTheReason() throws {
        let measure = try parseMeasure(#"{"ok":false,"why":"signal_low","used":2,"asked":7}"#)
        XCTAssertFalse(measure.ok)
        XCTAssertEqual(measure.why, "signal_low")
        XCTAssertEqual(measure.distanceMm, 0, accuracy: 1e-9)
        XCTAssertEqual(measure.used, 2)
    }

    func testASpindleWithNoLimitsHasNoneOfThemAndTheGuardDefaultsToReject() throws {
        let info = try parseSpindle(#"{"spindle":""}"#)
        XCTAssertEqual(info.spindle, "")
        XCTAssertEqual(info.guardMode, "reject")
        XCTAssertNil(info.original)
        XCTAssertNil(info.vfd)
        XCTAssertNil(info.active)
        XCTAssertNil(info.nodeMaxRpm)
    }

    // ---- the refusals, the roles and the small stores

    func testTheErrorOfTheServerFallsBackToTheStatusWhenItNamesNoCode() {
        XCTAssertEqual(describeError(status: 500, body: "not json").code, "http_500")
        XCTAssertEqual(describeError(status: 500, body: "not json").detail, "")
        XCTAssertEqual(describeError(status: 404, body: #"{"other":"x"}"#).code, "http_404")
        let named = describeError(status: 404, body: #"{"error":"bad_job","detail":"the job is gone"}"#)
        XCTAssertEqual(named.code, "bad_job")
        XCTAssertEqual(named.detail, "the job is gone")
        XCTAssertEqual(describeError(status: 400, body: #"{"error":""}"#).code, "http_400")
        XCTAssertEqual(describeError(status: 400, body: "").code, "http_400")
    }

    func testOnlyUnauthorizedIsUnauthorized() {
        XCTAssertTrue(ApiError(status: 401, code: "unauthorized", detail: "").unauthorized)
        XCTAssertFalse(ApiError(status: 403, code: "forbidden", detail: "").unauthorized)
        XCTAssertFalse(ApiError(status: 0, code: "unreachable", detail: "").unauthorized)
    }

    func testViewersWatchOperatorsOperateAndOnlyAdministratorsSetTheSpindle() {
        XCTAssertFalse(Roles.canOperate("viewer"))
        XCTAssertFalse(Roles.canOperate(""))
        XCTAssertTrue(Roles.canOperate("operator"))
        XCTAssertTrue(Roles.canOperate("admin"))
        XCTAssertFalse(Roles.canAdmin("operator"))
        XCTAssertTrue(Roles.canAdmin("admin"))
    }

    func testTheMemoryStoreKeepsGivesBackAndForgets() {
        let store = MemoryStore()
        XCTAssertNil(store.get("a"))
        store.put("a", "1")
        store.put("a", "2")
        XCTAssertEqual(store.get("a"), "2")
        store.remove("a")
        XCTAssertNil(store.get("a"))
        store.remove("never there")
    }

    func testTheMemorySecretsReadAbsentValueOrLockedAccordingToTheItemAndThePhone() {
        let secrets = MemorySecrets()
        XCTAssertEqual(secrets.read("k"), .absent)
        secrets.write("k", "v", tiedToUnlock: false)
        XCTAssertEqual(secrets.read("k"), .value("v"))
        secrets.phoneLocked = true
        XCTAssertEqual(secrets.read("k"), .value("v"))
        secrets.write("k", "w", tiedToUnlock: true)
        XCTAssertEqual(secrets.read("k"), .locked)
        secrets.phoneLocked = false
        XCTAssertEqual(secrets.read("k"), .value("w"))
        secrets.remove("k")
        XCTAssertEqual(secrets.read("k"), .absent)
    }
}
