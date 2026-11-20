import XCTest
@testable import Eh3dCore

/// A server of the test with a laser and a printer of the plugins: the laser and the printer latch when they are stopped, refuse the release to who is not an administrator, and keep a queue that nothing starts.
/// It writes down every POST the phone made to `/work/`. Tests of this file run one at a time.
private final class WorkSim: URLProtocol {
    static let lock = NSLock()
    static var laserLatched = false
    static var printerLatched = false
    static var admin = false
    static var calls: [String] = []

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        laserLatched = false; printerLatched = false; admin = false; calls = []
    }

    static var written: [String] { lock.lock(); defer { lock.unlock() }; return calls }
    static func allowAdmin() { lock.lock(); defer { lock.unlock() }; admin = true }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WorkSim.self]
        return URLSession(configuration: configuration)
    }

    /// The queue of the simulated server: a laser job that runs, a print that waits for a person and a print that is over.
    private static let jobs = """
        {"total":3,"offset":0,"limit":100,"items":[
        {"id":"w-1","machine":"l1","plugin":"laser","name":"Badge","owner":"ana","state":"running","percent":40,"position":0},
        {"id":"w-2","machine":"p1","plugin":"printer3d","name":"Benchy","owner":"ana","state":"queued","percent":0,"position":1},
        {"id":"w-3","machine":"p1","plugin":"printer3d","name":"Old","owner":"ana","state":"done","percent":100,"position":0}]}
        """

    /// The switches of security as the server answers an administrator: the four of the app are off, and one more that the app leaves out.
    private static let policy = """
        {"switches":[{"key":"url_token","value":false,"safe":true},{"key":"slice_enabled","value":false,"safe":true},{"key":"mdns_announce","value":false,"safe":true},{"key":"compat_api","value":false,"safe":true},{"key":"compat_write","value":false,"safe":true}]}
        """

    private static func machines() -> String {
        let laserJob = laserLatched ? "null" : "\"w-1\""
        let laserState = laserLatched ? "idle" : "busy"
        return """
        {"machines":[
        {"id":"l1","name":"Laser","plugin":"laser","state":"\(laserState)","job":\(laserJob),"capabilities":{"evidence":"simulator"},"detail":{"evidence":"simulator","simulator_only":true,"estop_latched":\(laserLatched)}},
        {"id":"p1","name":"Printer","plugin":"printer3d","state":"idle","job":null,"detail":{"evidence":"simulator","simulator_only":true,"latched":\(printerLatched),"auto_start_queue":false,"limits_c":{"hotend":260,"bed":100,"chamber":0},"temperatures":[{"name":"hotend","current_c":24.6,"target_c":0},{"name":"bed","current_c":23,"target_c":0}]}}]}
        """
    }

    private static func answer(_ method: String, _ path: String) -> (Int, String) {
        lock.lock(); defer { lock.unlock() }
        let forbidden = (403, #"{"error":"forbidden"}"#)
        if path == "/api/v1/work/machines" { return (200, machines()) }
        if path == "/api/v1/work/jobs" { return (200, jobs) }
        if path == "/api/v1/auth/policy" { return admin ? (200, policy) : forbidden }
        if path.hasPrefix("/api/v1/work/") && method == "POST" {
            calls.append("POST \(path)")
            switch path {
            case "/api/v1/work/jobs/w-1/cancel": laserLatched = true; return (200, #"{"ok":true}"#)
            case "/api/v1/work/machines/p1/emergency-stop": printerLatched = true; return (200, #"{"ok":true}"#)
            case "/api/v1/work/machines/l1/laser/release": if admin { laserLatched = false; return (200, #"{"released":true}"#) } else { return forbidden }
            case "/api/v1/work/machines/p1/release": if admin { printerLatched = false; return (200, #"{"released":true}"#) } else { return forbidden }
            case "/api/v1/work/jobs/w-2/start": return (200, #"{"id":"w-2","state":"running"}"#)
            default: return (404, #"{"error":"not_found"}"#)
            }
        }
        return (404, #"{"error":"not_found"}"#)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let (status, text) = WorkSim.answer(request.httpMethod ?? "GET", url.path)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// The machines of the plugins against a server that latches them: what the phone shows, offers and sends. The same scenarios as the Android app (SimulatedServerTest).
final class WorkSimulatedServerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        WorkSim.reset()
    }

    private func phone() -> Eh3dApi {
        let client = Eh3dApi(origin: "http://sim.test:18200", token: "t", settings: ConnectionSettings(retries: 0), session: WorkSim.session())
        client.autoRefresh = false
        return client
    }

    private func found(_ api: Eh3dApi, _ id: String) async throws -> WorkMachine {
        let list = try await api.workMachines()
        return try XCTUnwrap(list.first { $0.id == id }, id)
    }

    func testAMachineOfAPluginSaysItIsASimulatorAndItsEmergencyStopIsOneRequestThatLatchesIt() async throws {
        let api = phone()
        let laser = try await found(api, "l1")
        XCTAssertTrue(laser.simulatorOnly)
        XCTAssertEqual(laser.job, "w-1")
        XCTAssertTrue(MachineSafety.canStop(isOperator: true, laser))
        XCTAssertFalse(MachineSafety.canStop(isOperator: false, laser))
        let sent = try await api.emergencyStopWork(laser)
        XCTAssertTrue(sent)
        XCTAssertEqual(WorkSim.written, ["POST /api/v1/work/jobs/w-1/cancel"])
        let held = try await found(api, "l1")
        XCTAssertEqual(held.interlocks, [.estopLatched])
        XCTAssertTrue(held.latched)
        XCTAssertFalse(MachineSafety.canStop(isOperator: true, held), "a held machine is released, not stopped again")
        XCTAssertTrue(MachineSafety.canRelease(isAdmin: true, held))
        XCTAssertFalse(MachineSafety.canRelease(isAdmin: false, held))
    }

    func testThePrinterStopsByItsOwnRouteAndOnlyAnAdministratorGetsTheLatchReleased() async throws {
        let api = phone()
        let printer = try await found(api, "p1")
        XCTAssertTrue(printer.simulatorOnly)
        XCTAssertEqual(printer.job, "")
        XCTAssertTrue(MachineSafety.canStop(isOperator: true, printer))
        XCTAssertEqual(printer.heaters.map { MachineSafety.heaterText($0) }, ["hotend 25/0", "bed 23/0"])
        XCTAssertEqual(MachineSafety.limitText(printer.limits?.hotendC ?? 0), "260")
        let sent = try await api.emergencyStopWork(printer)
        XCTAssertTrue(sent)
        let held = try await found(api, "p1")
        XCTAssertEqual(held.interlocks, [.latched])
        do { _ = try await api.releaseWork(held); XCTFail("a release by who is not an administrator is refused") }
        catch let error as ApiError { XCTAssertTrue(error.forbidden) }
        let stillHeld = try await found(api, "p1")
        XCTAssertTrue(stillHeld.latched, "the refused release leaves it held")
        WorkSim.allowAdmin()
        let released = try await api.releaseWork(held)
        XCTAssertTrue(released)
        let free = try await found(api, "p1")
        XCTAssertFalse(free.latched)
        XCTAssertEqual(WorkSim.written, ["POST /api/v1/work/machines/p1/emergency-stop", "POST /api/v1/work/machines/p1/release", "POST /api/v1/work/machines/p1/release"])
    }

    func testLookingAtTheQueueStartsNothingAndAJobStartsOnlyWhenItIsAskedForByItsId() async throws {
        let api = phone()
        let jobs = try await api.workJobs()
        _ = try await api.workMachines()
        XCTAssertEqual(MachineSafety.activeJobs(jobs, machineId: "p1").map { $0.id }, ["w-2"])
        XCTAssertEqual(MachineSafety.activeJobs(jobs, machineId: "l1").map { $0.id }, ["w-1"])
        let waiting = try XCTUnwrap(jobs.first { $0.id == "w-2" })
        XCTAssertTrue(MachineSafety.canStartJob(isOperator: true, waiting))
        XCTAssertFalse(MachineSafety.canStartJob(isOperator: false, waiting))
        let running = try XCTUnwrap(jobs.first { $0.id == "w-1" })
        XCTAssertFalse(MachineSafety.canStartJob(isOperator: true, running))
        XCTAssertTrue(WorkSim.written.isEmpty, "reading the queue and the machines sent nothing")
        try await api.startWorkJob(waiting.id)
        XCTAssertEqual(WorkSim.written, ["POST /api/v1/work/jobs/w-2/start"])
    }

    func testTheSwitchesOfTheServerAreReadByAnAdministratorOnlyAndTheFourAreOff() async throws {
        let api = phone()
        do { _ = try await api.policySwitches(); XCTFail("a role that is not an administrator is refused") }
        catch let error as ApiError { XCTAssertTrue(error.forbidden) }
        XCTAssertNotEqual(api.token, "", "a refusal for the role keeps the login")
        WorkSim.allowAdmin()
        let list = try await api.policySwitches()
        XCTAssertEqual(list.map { $0.key }, MachineSafety.switchKeys)
        XCTAssertTrue(list.allSatisfy { !$0.on })
        XCTAssertTrue(list.allSatisfy { $0.safe })
    }
}
