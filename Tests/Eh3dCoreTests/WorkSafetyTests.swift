import XCTest
@testable import Eh3dCore

/// The safety of the machines of the plugins as the phone decides it: the simulator badge, the interlocks, who may stop, release and start, the queue of a machine, the limits of a printer and the switches of
/// the server. The same cases as the Android app (WorkSafetyTest) and EH3D-STUDIO; the SERVER decides in the end.
final class WorkSafetyTests: XCTestCase {
    private func machine(_ plugin: String, detail: String = "{}", job: String = "", capabilities: String = "{}") -> WorkMachine {
        let jobText = job.isEmpty ? "null" : "\"\(job)\""
        let text = #"{"machines":[{"id":"m","name":"M","plugin":"\#(plugin)","state":"idle","job":\#(jobText),"capabilities":\#(capabilities),"detail":\#(detail)}]}"#
        guard let list = try? parseWorkMachines(text), let first = list.first else {
            XCTFail("the machine was not read: \(text)")
            return WorkMachine(id: "", name: "", plugin: plugin, state: "idle", latched: false, detail: [])
        }
        return first
    }

    private func job(_ id: String, _ machine: String, _ state: String, position: Int = 0) -> WorkJob {
        WorkJob(id: id, machine: machine, plugin: "printer3d", name: id, owner: "ana", state: state, percent: 0, position: position)
    }

    func testAMachineThatSaysItOnlyRanAgainstASimulatorIsMarkedWhicheverWayTheServerSaysIt() {
        XCTAssertTrue(machine("laser", detail: #"{"simulator_only":true}"#).simulatorOnly)
        XCTAssertTrue(machine("laser", detail: #"{"evidence":"simulator"}"#).simulatorOnly)
        XCTAssertTrue(machine("pnp", capabilities: #"{"evidence":"simulator"}"#).simulatorOnly)
        XCTAssertFalse(machine("laser", detail: #"{"evidence":"hardware"}"#).simulatorOnly)
        XCTAssertFalse(machine("laser").simulatorOnly)
    }

    func testTheNinePluginsThatOnlyRunAgainstASimulatorAreListed() {
        XCTAssertEqual(MachineSafety.simulatorPlugins, ["laser", "pnp", "pcb", "cnc", "gerber", "cam", "printer3d", "vision", "cad"])
    }

    func testTheInterlocksComeInTheOrderTheScreenShowsThem() {
        XCTAssertEqual(machine("laser").interlocks, [])
        XCTAssertEqual(machine("printer3d", detail: #"{"latched":true}"#).interlocks, [.latched])
        XCTAssertEqual(machine("laser", detail: #"{"estop_latched":true}"#).interlocks, [.estopLatched])
        XCTAssertEqual(machine("cnc", detail: #"{"alarm":true,"estop_latched":true,"latched":true}"#).interlocks, [.latched, .estopLatched, .alarm])
    }

    func testAnAlarmIsAFlagAWordThatIsNotACalmOneOrTheStateAlarm() {
        XCTAssertEqual(machine("cnc", detail: #"{"alarm":"hard_limit"}"#).interlocks, [.alarm])
        XCTAssertEqual(machine("cnc", detail: #"{"state_word":"Alarm"}"#).interlocks, [.alarm])
        for calm in ["", "none", "ok", "false", "0", "idle", "run", " OK "] {
            XCTAssertEqual(machine("cnc", detail: "{\"alarm\":\"\(calm)\"}").interlocks, [], "alarm: \"\(calm)\"")
        }
        XCTAssertEqual(machine("cnc", detail: #"{"alarm":false,"state_word":"idle"}"#).interlocks, [])
    }

    func testAMachineWithAnInterlockIsLatchedAndOneWithoutIsNot() {
        XCTAssertTrue(machine("laser", detail: #"{"estop_latched":true}"#).latched)
        XCTAssertFalse(machine("laser", detail: #"{"estop_latched":false}"#).latched)
    }

    func testAQueueThatStartsJobsByItselfIsAWarning() {
        XCTAssertTrue(machine("printer3d", detail: #"{"auto_start_queue":true}"#).autoStart)
        XCTAssertTrue(machine("printer3d", detail: #"{"auto_start":true}"#).autoStart)
        XCTAssertFalse(machine("printer3d", detail: #"{"auto_start_queue":false}"#).autoStart)
        XCTAssertFalse(machine("printer3d").autoStart)
    }

    func testThePluginsThatStopByARouteOfTheirOwnAndTheOnesThatStopByCancellingTheJob() {
        XCTAssertEqual(MachineSafety.stopRoute("cnc"), "emergency-stop")
        XCTAssertEqual(MachineSafety.stopRoute("printer3d"), "emergency-stop")
        for plugin in ["laser", "pnp", "pcb", "gerber", "cam", "vision", "cad", "demo"] { XCTAssertNil(MachineSafety.stopRoute(plugin), plugin) }
    }

    func testThePluginsThatLatchHaveARouteToReleaseTheLatch() {
        XCTAssertEqual(MachineSafety.releaseRoute("cnc"), "release")
        XCTAssertEqual(MachineSafety.releaseRoute("printer3d"), "release")
        XCTAssertEqual(MachineSafety.releaseRoute("laser"), "laser/release")
        for plugin in ["pnp", "pcb", "gerber", "cam", "vision", "cad"] { XCTAssertNil(MachineSafety.releaseRoute(plugin), plugin) }
    }

    func testTheEmergencyStopIsForAnOperatorWithARouteOrAJobAndNotForAMachineThatIsAlreadyHeld() {
        XCTAssertTrue(MachineSafety.canStop(isOperator: true, machine("printer3d")))
        XCTAssertTrue(MachineSafety.canStop(isOperator: true, machine("laser", job: "w-1")))
        XCTAssertFalse(MachineSafety.canStop(isOperator: true, machine("laser")), "a laser with no job has nothing to cancel")
        XCTAssertFalse(MachineSafety.canStop(isOperator: false, machine("printer3d")), "a viewer only watches")
        XCTAssertFalse(MachineSafety.canStop(isOperator: true, machine("printer3d", detail: #"{"latched":true}"#)), "a held machine is released, not stopped")
    }

    func testTheReleaseIsForAnAdministratorAndOnlyForAHeldMachineWhosePluginLatches() {
        let held = machine("laser", detail: #"{"estop_latched":true}"#)
        XCTAssertTrue(MachineSafety.canRelease(isAdmin: true, held))
        XCTAssertFalse(MachineSafety.canRelease(isAdmin: false, held), "an operator cannot release")
        XCTAssertFalse(MachineSafety.canRelease(isAdmin: true, machine("laser")), "nothing to release")
        XCTAssertFalse(MachineSafety.canRelease(isAdmin: true, machine("pnp", detail: #"{"alarm":true}"#)), "a pick-and-place machine has no route to release")
    }

    func testAPrintWaitsForAPerson() {
        XCTAssertTrue(MachineSafety.needsManualStart("printer3d"))
        XCTAssertFalse(MachineSafety.needsManualStart("laser"))
    }

    func testTheLimitsOfTemperatureAndTheHeatersOfAPrinterAreReadAndAMissingHeaterShowsADash() {
        let printer = machine("printer3d", detail: #"{"limits_c":{"hotend":260,"bed":100,"chamber":0},"temperatures":[{"name":"hotend","current_c":24.6,"target_c":200},{"name":"","current_c":1,"target_c":2},{"name":"bed","current_c":23,"target_c":60.4}]}"#)
        XCTAssertEqual(printer.limits, TempLimits(hotendC: 260, bedC: 100, chamberC: 0))
        XCTAssertEqual(printer.heaters, [Heater(name: "hotend", currentC: 24.6, targetC: 200), Heater(name: "bed", currentC: 23, targetC: 60.4)])
        XCTAssertEqual(printer.heaters.map { MachineSafety.heaterText($0) }, ["hotend 25/200", "bed 23/60"])
        XCTAssertEqual(MachineSafety.limitText(260), "260")
        XCTAssertEqual(MachineSafety.limitText(0), "-")
        XCTAssertEqual(MachineSafety.limitText(Double.nan), "-")
        XCTAssertNil(machine("laser").limits)
        XCTAssertEqual(machine("laser").heaters, [])
    }

    func testTheFactsLeaveOutWhatTheScreenShowsInItsOwnWayAndKeepToTheLimit() {
        let printer = machine("printer3d", detail: #"{"evidence":"simulator","simulator_only":true,"latched":false,"limits_c":{"hotend":260},"temperatures":[],"auto_start_queue":false,"model":"generic","online":true}"#)
        XCTAssertEqual(MachineSafety.facts(printer), [DetailLine("model", "generic"), DetailLine("online", "true")])
        let many = (1...10).map { "\"k\($0)\":\($0)" }.joined(separator: ",")
        XCTAssertEqual(MachineSafety.facts(machine("cnc", detail: "{\(many)}"), limit: 3).count, 3)
    }

    func testTheActiveJobsOfAMachineAreTheRunningFirstThenTheHeldThenTheQueuedInTheirPlace() {
        let jobs = [job("a", "p1", "queued", position: 2), job("b", "p1", "done"), job("c", "p1", "queued", position: 1), job("d", "p2", "queued"), job("e", "p1", "paused"), job("f", "p1", "running"), job("g", "p1", "cancelled")]
        XCTAssertEqual(MachineSafety.activeJobs(jobs, machineId: "p1").map { $0.id }, ["f", "e", "c", "a"])
        XCTAssertEqual(MachineSafety.activeJobs(jobs, machineId: "p2").map { $0.id }, ["d"])
        XCTAssertEqual(MachineSafety.activeJobs(jobs, machineId: "none"), [])
        XCTAssertEqual(MachineSafety.activeJobs([job("x", "p", "queued"), job("y", "p", "queued")], machineId: "p").map { $0.id }, ["x", "y"], "the same place keeps the order of the list")
    }

    func testAJobIsStartedOnlyByAnOperatorAndOnlyWhileItWaitsAndCancelledWhileItWaitsOrIsHeld() {
        XCTAssertTrue(MachineSafety.canStartJob(isOperator: true, job("a", "m", "queued")))
        XCTAssertFalse(MachineSafety.canStartJob(isOperator: false, job("a", "m", "queued")))
        for state in ["running", "paused", "done", "failed", "cancelled"] { XCTAssertFalse(MachineSafety.canStartJob(isOperator: true, job("a", "m", state)), state) }
        XCTAssertTrue(MachineSafety.canCancelJob(isOperator: true, job("a", "m", "queued")))
        XCTAssertTrue(MachineSafety.canCancelJob(isOperator: true, job("a", "m", "paused")))
        XCTAssertFalse(MachineSafety.canCancelJob(isOperator: true, job("a", "m", "running")), "a running job is stopped with the emergency stop")
        XCTAssertFalse(MachineSafety.canCancelJob(isOperator: false, job("a", "m", "queued")))
    }

    func testTheJobsOfTheQueueAreReadAndAnItemWithoutAnIdIsLeftOut() throws {
        let text = #"{"total":3,"items":[{"id":"w-1","machine":"l1","plugin":"laser","name":"Badge","owner":"ana","state":"running","percent":40,"position":0},{"machine":"x"},{"id":"w-2","machine":"p1"}]}"#
        let jobs = try parseWorkJobs(text)
        XCTAssertEqual(jobs.map { $0.id }, ["w-1", "w-2"])
        XCTAssertEqual(jobs[0], WorkJob(id: "w-1", machine: "l1", plugin: "laser", name: "Badge", owner: "ana", state: "running", percent: 40, position: 0))
        XCTAssertEqual(jobs[1].state, "queued")
        XCTAssertEqual(try parseWorkJobs("{}"), [])
        XCTAssertThrowsError(try parseWorkJobs("not json"))
    }

    func testTheSwitchesTheAppExplainsAreTheFourThatAreOffByDefaultInThatOrderAndTheRestAreLeftOut() throws {
        XCTAssertEqual(MachineSafety.switchKeys, ["mdns_announce", "compat_api", "compat_write", "slice_enabled"])
        let text = #"{"switches":[{"key":"url_token","value":false,"safe":true},{"key":"slice_enabled","value":true,"safe":false},{"key":"mdns_announce","value":false,"safe":true},{"key":"compat_api","value":false,"safe":true}]}"#
        let list = try parsePolicySwitches(text)
        XCTAssertEqual(list.map { $0.key }, ["mdns_announce", "compat_api", "slice_enabled"])
        XCTAssertEqual(list.last?.on, true)
        XCTAssertEqual(list.last?.safe, false)
        XCTAssertEqual(try parsePolicySwitches("{}"), [])
    }

    func testAMachineOfTheFleetIsNotOneOfThePluginsAndADetailThatIsNotAnObjectIsNoDetail() throws {
        let text = #"{"machines":[{"id":"d","plugin":"bungard","state":"idle","detail":{"latched":true}},{"id":"x","plugin":"cad","state":"idle","detail":null}]}"#
        let list = try parseWorkMachines(text)
        XCTAssertEqual(list.map { $0.id }, ["x"])
        XCTAssertFalse(list[0].latched)
        XCTAssertFalse(list[0].simulatorOnly)
        XCTAssertEqual(list[0].job, "")
    }
}
