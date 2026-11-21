import XCTest
@testable import Eh3dCore

/// What a request of the client looks like to the server (path, method, headers, body), written down by the stand-in below.
private struct Seen {
    let method: String
    let path: String
    let query: String?
    let authorization: String?
    let contentType: String?
    let agent: String?
    let body: String
    let timeout: TimeInterval
}

/// A server that lives in the test: it answers every request of a session built with it and writes down what it was asked. Tests of this file run one at a time.
private final class StandIn: URLProtocol {
    static let lock = NSLock()
    static var seen: [Seen] = []
    static var reply: (Seen) -> (Int, String) = { _ in (200, "{}") }
    static var failure: Error?

    /// How many requests have arrived (the one being answered included); the reply of a test reads it to answer differently the third time.
    static var attempts: Int { lock.lock(); defer { lock.unlock() }; return seen.count }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        seen = []
        reply = { _ in (200, "{}") }
        failure = nil
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StandIn.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    private static func body(of request: URLRequest) -> String {
        if let data = request.httpBody { return String(decoding: data, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return String(decoding: data, as: UTF8.self)
    }

    override func startLoading() {
        let url = request.url!
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let note = Seen(method: request.httpMethod ?? "GET", path: parts?.percentEncodedPath ?? "", query: parts?.percentEncodedQuery,
                        authorization: request.value(forHTTPHeaderField: "Authorization"), contentType: request.value(forHTTPHeaderField: "Content-Type"),
                        agent: request.value(forHTTPHeaderField: "User-Agent"), body: StandIn.body(of: request), timeout: request.timeoutInterval)
        StandIn.lock.lock()
        StandIn.seen.append(note)
        let failure = StandIn.failure
        let reply = StandIn.reply
        StandIn.lock.unlock()
        if let failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let (status, text) = reply(note)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// The client of the API against a server that is a stand-in: what it sends and how it reads the answers and the refusals.
final class ApiClientTests: XCTestCase {
    private let origin = "http://stub.test:18200"

    override func setUp() {
        super.setUp()
        StandIn.reset()
    }

    private func api(token: String = "", origin: String? = nil) -> Eh3dApi {
        // one try each: the tries again and the renewal of the login have their own tests (ApiConnectionTests)
        let client = Eh3dApi(origin: origin ?? self.origin, token: token, settings: ConnectionSettings(retries: 0), session: StandIn.session())
        client.autoRefresh = false
        return client
    }
    private func answer(_ text: String, status: Int = 200) { StandIn.reply = { _ in (status, text) } }
    private var seen: [Seen] { StandIn.lock.lock(); defer { StandIn.lock.unlock() }; return StandIn.seen }
    private func json(_ text: String) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]) }

    private func refusal(_ work: () async throws -> Void) async -> ApiError? {
        do { try await work(); return nil } catch let error as ApiError { return error } catch { XCTFail("another kind of error: \(error)"); return nil }
    }

    // ---- reading

    func testTheHealthCallReadsTheVersionOfTheServer() async throws {
        answer(#"{"version":"1.2.3"}"#)
        let version = try await api().health()
        XCTAssertEqual(version, "1.2.3")
        XCTAssertEqual(seen[0].method, "GET")
        XCTAssertEqual(seen[0].path, "/api/v1/health")
    }

    func testAServerThatSaysNothingOfItsVersionGivesAnEmptyOne() async throws {
        answer("{}")
        let version = try await api().health()
        XCTAssertEqual(version, "")
    }

    func testTheSetupCallSaysWhetherTheFirstAdministratorIsStillToBeMade() async throws {
        answer(#"{"needed":true}"#)
        let needed = try await api().setupNeeded()
        XCTAssertTrue(needed)
        answer(#"{"needed":false}"#)
        let notNeeded = try await api().setupNeeded()
        XCTAssertFalse(notNeeded)
        answer("{}")
        let silent = try await api().setupNeeded()
        XCTAssertFalse(silent)
    }

    func testTheFirstAdministratorIsMadeWithTheCodeTheServerPrinted() async throws {
        answer(#"{"ok":true}"#)
        try await api().setup(code: "123456", name: "owner", password: "a long pass phrase")
        XCTAssertEqual(seen[0].method, "POST")
        XCTAssertEqual(seen[0].path, "/api/v1/setup")
        let body = try json(seen[0].body)
        XCTAssertEqual(body["code"] as? String, "123456")
        XCTAssertEqual(body["name"] as? String, "owner")
        XCTAssertEqual(body["password"] as? String, "a long pass phrase")
        XCTAssertEqual(seen[0].contentType, "application/json")
    }

    func testALoginSendsTheNameAndThePasswordAndReadsTheTokenAndTheRole() async throws {
        answer(#"{"token":"t_abc","name":"Ana","role":"operator"}"#)
        let login = try await api().login(name: "ana", password: "secret phrase")
        XCTAssertEqual(login, Login(token: "t_abc", name: "Ana", role: "operator"))
        XCTAssertEqual(seen[0].path, "/api/v1/auth/login")
        XCTAssertEqual(try json(seen[0].body)["name"] as? String, "ana")
        XCTAssertEqual(try json(seen[0].body)["app"] as? String, "ios")
        XCTAssertNil(seen[0].authorization)
    }

    func testALoginThatNamesNoRoleIsAViewerAndKeepsTheTypedName() async throws {
        answer(#"{"token":"t_x"}"#)
        let login = try await api().login(name: "ana", password: "secret phrase")
        XCTAssertEqual(login.role, "viewer")
        XCTAssertEqual(login.name, "ana")
    }

    func testTheSessionCallKeepsTheTokenItWasAskedWith() async throws {
        answer(#"{"name":"Ana","role":"admin"}"#)
        let login = try await api(token: "t_kept").session()
        XCTAssertEqual(login, Login(token: "t_kept", name: "Ana", role: "admin"))
        XCTAssertEqual(seen[0].authorization, "Bearer t_kept")
    }

    func testNoTokenMeansNoAuthorizationHeader() async throws {
        answer(#"{"machines":[]}"#)
        _ = try await api().fleet()
        XCTAssertNil(seen[0].authorization)
    }

    func testEveryRequestSaysWhichAppItComesFrom() async throws {
        answer(#"{"machines":[]}"#)
        _ = try await api(token: "t").fleet()
        XCTAssertEqual(try XCTUnwrap(seen[0].agent).hasPrefix("EH3D-IOS-CONTROL/"), true)
        XCTAssertEqual(seen[0].authorization, "Bearer t")
    }

    func testATrailingSlashOfTheAddressDoesNotDoubleInThePath() async throws {
        answer(#"{"machines":[]}"#)
        _ = try await api(origin: origin + "/").fleet()
        XCTAssertEqual(seen[0].path, "/api/v1/fleet")
    }

    // ---- refusals

    func testARefusalGivesItsStatusItsCodeAndItsDetail() async {
        answer(#"{"error":"forbidden","detail":"viewers cannot do this"}"#, status: 403)
        let error = await refusal { try await self.api(token: "t").start("job1") }
        XCTAssertEqual(error, ApiError(status: 403, code: "forbidden", detail: "viewers cannot do this"))
        XCTAssertEqual(error?.unauthorized, false)
    }

    func testARefusedTokenIsToldAsUnauthorized() async {
        answer(#"{"error":"unauthorized"}"#, status: 401)
        let error = await refusal { _ = try await self.api(token: "t_old").fleet() }
        XCTAssertEqual(error?.unauthorized, true)
        XCTAssertEqual(error?.code, "unauthorized")
        XCTAssertEqual(error?.detail, "unauthorized")
    }

    func testAnErrorThatIsNotJsonIsNamedAfterItsStatus() async {
        answer("<html>bad gateway</html>", status: 502)
        let error = await refusal { _ = try await self.api().fleet() }
        XCTAssertEqual(error?.status, 502)
        XCTAssertEqual(error?.code, "http_502")
    }

    func testAnErrorWithAnEmptyBodyIsNamedAfterItsStatusToo() async {
        answer("", status: 404)
        let error = await refusal { _ = try await self.api().job("gone") }
        XCTAssertEqual(error?.status, 404)
        XCTAssertEqual(error?.code, "http_404")
    }

    func testA200ThatIsNotJsonIsAnotherServiceAndNotACrash() async {
        answer("<html>router login</html>")
        let error = await refusal { _ = try await self.api().fleet() }
        XCTAssertEqual(error?.code, "bad_json")
    }

    func testNobodyListeningIsAnUnreachableServerWithNoStatus() async {
        StandIn.failure = URLError(.cannotConnectToHost)
        let error = await refusal { _ = try await self.api().fleet() }
        XCTAssertEqual(error?.status, 0)
        XCTAssertEqual(error?.code, "unreachable")
    }

    // ---- the paths and the methods

    func testTheJobsOfOneMachineAreAskedForWithItsNameEncoded() async throws {
        answer("[]")
        _ = try await api().jobs(machine: "Mill & Drill")
        XCTAssertEqual(seen[0].path, "/api/v1/jobs")
        XCTAssertEqual(seen[0].query, "machine=Mill%20%26%20Drill")
    }

    func testTheJobsOfAllTheMachinesAreAskedForWithoutAQuery() async throws {
        answer("[]")
        let jobs = try await api().jobs()
        XCTAssertEqual(jobs.count, 0)
        XCTAssertNil(seen[0].query)
    }

    func testTheIdOfAJobIsEncodedInThePathSoItCannotClimbOutOfIt() async throws {
        answer(#"{"id":"x"}"#)
        _ = try await api().job("../health")
        XCTAssertEqual(seen[0].path, "/api/v1/jobs/..%2Fhealth")
    }

    func testTheActionsOnAJobUseTheMethodAndThePathOfTheApi() async throws {
        answer(#"{"ok":true}"#)
        let client = api(token: "t")
        try await client.start("j"); try await client.confirm("j"); try await client.cancel("j"); try await client.pause("j")
        try await client.resume("j"); try await client.delete("j"); try await client.stopMachine("m1")
        XCTAssertEqual(seen.map { "\($0.method) \($0.path)" }, [
            "POST /api/v1/jobs/j/start", "POST /api/v1/jobs/j/confirm", "POST /api/v1/jobs/j/cancel", "POST /api/v1/jobs/j/pause",
            "POST /api/v1/jobs/j/resume", "DELETE /api/v1/jobs/j", "POST /api/v1/machines/m1/stop",
        ])
        XCTAssertEqual(seen[0].body, "{}")
    }

    func testGoingOnFromAStoppedJobReadsTheNewJobItMakes() async throws {
        answer(#"{"id":"j2","resumed_from":"j1","state":"ready"}"#)
        let job = try await api().resumeFrom("j1")
        XCTAssertEqual(job.summary.id, "j2")
        XCTAssertEqual(job.summary.resumedFrom, "j1")
        XCTAssertEqual(seen[0].path, "/api/v1/jobs/j1/resume-from")
    }

    func testTheSwitchOfTheDollarLinesIsReadFromTheMachine() async throws {
        answer(#"{"allow_dollar":true}"#)
        let allowed = try await api().allowDollar("m 1")
        XCTAssertTrue(allowed)
        XCTAssertEqual(seen[0].path, "/api/v1/machines/m%201")
    }

    func testAPreviewAndANewJobPostTheRequestAsItIs() async throws {
        answer(#"{"kind":"drill","name":"p","holes":[]}"#)
        let client = api()
        _ = try await client.preview("m1", body: #"{"kind":"drill"}"#)
        _ = try await client.createJob("m1", body: #"{"kind":"route"}"#)
        XCTAssertEqual(seen[0].path, "/api/v1/machines/m1/preview")
        XCTAssertEqual(seen[0].body, #"{"kind":"drill"}"#)
        XCTAssertEqual(seen[1].path, "/api/v1/machines/m1/jobs")
        XCTAssertEqual(seen[1].body, #"{"kind":"route"}"#)
    }

    func testSettingTheSpindleSendsOnlyWhatIsGiven() async throws {
        answer(#"{"spindle":"vfd","guard":"warn"}"#)
        let client = api(token: "t")
        let info = try await client.setSpindle("m1", spindle: nil, guardMode: "warn")
        XCTAssertEqual(seen[0].method, "PUT")
        XCTAssertEqual(try json(seen[0].body).keys.sorted(), ["guard"])
        XCTAssertEqual(info.spindle, "vfd")
        _ = try await client.setSpindle("m1", spindle: "original", guardMode: nil)
        XCTAssertEqual(try json(seen[1].body).keys.sorted(), ["spindle"])
        _ = try await client.setSpindle("m1", spindle: "", guardMode: "reject")
        let both = try json(seen[2].body)
        XCTAssertEqual(both["spindle"] as? String, "")
        XCTAssertEqual(both["guard"] as? String, "reject")
    }

    func testTheRingIsSwitchedOffAtLevelZeroAndNeverAskedForMoreThanAHundred() async throws {
        answer(#"{"on":true,"level":100,"max_level":80}"#)
        let client = api()
        _ = try await client.setLight("m1", level: 0)
        _ = try await client.setLight("m1", level: -5)
        _ = try await client.setLight("m1", level: 40)
        _ = try await client.setLight("m1", level: 250)
        XCTAssertEqual(seen.map { $0.query ?? "" }, ["on=0", "on=0", "on=1&level=40&tone=white&sectors=all", "on=1&level=100&tone=white&sectors=all"])
    }

    func testAMeasureAsksForTheSamplesItIsGiven() async throws {
        answer(#"{"ok":true,"distance_mm":12.5,"sigma_mm":0.01,"used":5,"asked":7}"#)
        let measure = try await api().measure("m1", samples: 9)
        XCTAssertEqual(seen[0].query, "samples=9")
        XCTAssertEqual(measure.distanceMm, 12.5, accuracy: 1e-9)
        _ = try await api().measure("m1")
        XCTAssertEqual(seen[1].query, "samples=7")
    }

    func testAQualityCheckCarriesTheHoleAndTheLightOnlyWhenThereAreAny() async throws {
        answer(#"{"verdict":"ok","holes":[],"findings":[]}"#)
        let client = api()
        _ = try await client.inspect("m1", light: 0, holeMm: 0)
        _ = try await client.inspect("m1", light: 50, holeMm: 0.8)
        _ = try await client.inspect("m1", light: 300, holeMm: 0)
        XCTAssertEqual(seen[0].body, #"{"holes":[]}"#)
        let lit = try json(seen[1].body)
        XCTAssertEqual(lit["light"] as? Int, 50)
        XCTAssertEqual(lit["restore_light"] as? Bool, true)
        let hole = try XCTUnwrap((lit["holes"] as? [[String: Any]])?.first)
        XCTAssertEqual(try XCTUnwrap(hole["dia_mm"] as? Double), 0.8, accuracy: 1e-9)
        XCTAssertEqual(try json(seen[2].body)["light"] as? Int, 100)
    }

    func testThereBeingNoCheckYetIsNilAndAnyOtherRefusalIsPassedOn() async throws {
        answer(#"{"error":"no_inspection"}"#, status: 404)
        let none = try await api().lastInspection("m1")
        XCTAssertNil(none)
        answer(#"{"error":"forbidden"}"#, status: 403)
        let error = await refusal { _ = try await self.api().lastInspection("m1") }
        XCTAssertEqual(error?.code, "forbidden")
        answer(#"{"verdict":"not_ok","holes":[{"ok":false}],"findings":[]}"#)
        let last = try await api().lastInspection("m1")
        XCTAssertEqual(last?.verdict, "not_ok")
    }

    func testThePresetOfTheAnalyserIsChosenByNumberAndAWrongNumberIsClamped() async throws {
        answer(#"{"ok":true}"#)
        let client = api()
        for index in [0, 1, 2, 9, -3] { try await client.inspectPreset("m1", index: index) }
        XCTAssertEqual(try seen.map { try json($0.body)["preset"] as? String }, ["standard", "fine_pitch", "prototype", "prototype", "standard"])
        XCTAssertEqual(seen[0].method, "PUT")
    }

    func testTheCameraAddressHasNoCredentialAndTheTicketIsAddedJustBeforeItIsOpened() async throws {
        answer(#"{"ticket":"abc123"}"#)
        let client = api(token: "t_secret")
        let bare = try XCTUnwrap(client.streamURL("m 1"))
        XCTAssertEqual(bare.absoluteString, "http://stub.test:18200/api/v1/machines/m%201/head/stream")
        XCTAssertFalse(bare.absoluteString.contains("t_secret"))
        let opened = try await client.withTicket(bare)
        XCTAssertEqual(opened.absoluteString, bare.absoluteString + "?ticket=abc123")
        XCTAssertFalse(opened.absoluteString.contains("t_secret"))
        XCTAssertEqual(seen[0].path, "/api/v1/tickets")
    }

    func testATicketIsAddedAfterTheQueryThatThereAlreadyIs() throws {
        let url = try XCTUnwrap(URL(string: "http://h/s?a=1"))
        XCTAssertEqual(Eh3dApi.ticketURL(url, ticket: "abc").absoluteString, "http://h/s?a=1&ticket=abc")
        let plain = try XCTUnwrap(URL(string: "http://h/s"))
        XCTAssertEqual(Eh3dApi.ticketURL(plain, ticket: "abc").absoluteString, "http://h/s?ticket=abc")
    }

    func testCalibratingThePictureAndReadingTheHeadAndTheSpindleUseTheirPaths() async throws {
        answer(#"{"node":"n1"}"#)
        let client = api()
        try await client.inspectCalibrate("m1")
        _ = try await client.head("m1")
        _ = try await client.spindle("m1")
        XCTAssertEqual(seen.map { "\($0.method) \($0.path)" }, ["POST /api/v1/machines/m1/head/inspect/calibrate", "GET /api/v1/machines/m1/head/status", "GET /api/v1/machines/m1/spindle"])
    }

    func testSigningOutNeverThrowsEvenWhenTheServerIsAway() async {
        StandIn.failure = URLError(.notConnectedToInternet)
        await api(token: "t").logout()
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen[0].path, "/api/v1/auth/logout")
        XCTAssertEqual(seen[0].method, "POST")
    }
}


/// The rules of the client of the suite in the client of the app: the login that is renewed by itself, the token that a 401 makes it forget, the tries again after a failure and their pauses, and the calls of the
/// logins and of the machines of the plugins. The pauses and the clock are the ones of the test, so nothing waits.
final class ApiConnectionTests: XCTestCase {
    private let origin = "http://stub.test:18200"

    /// The pauses the client asked for, and the clock it reads, both in the hands of the test.
    private final class Time: @unchecked Sendable {
        private let lock = NSLock()
        private var waited: [Int] = []
        private var now: Int64 = 5_000_000
        func wait(_ ms: Int) { lock.lock(); defer { lock.unlock() }; waited.append(ms) }
        var pauses: [Int] { lock.lock(); defer { lock.unlock() }; return waited }
        func read() -> Int64 { lock.lock(); defer { lock.unlock() }; return now }
        func advance(seconds: Int) { lock.lock(); defer { lock.unlock() }; now += Int64(seconds) * 1000 }
    }

    private var time = Time()

    override func setUp() {
        super.setUp()
        StandIn.reset()
        time = Time()
    }

    private func api(token: String = "", retries: Int = 0, timeoutS: Int = 15, refresh: Bool = true) -> Eh3dApi {
        let clock = time
        let client = Eh3dApi(origin: origin, token: token, settings: ConnectionSettings(timeoutS: timeoutS, retries: retries), session: StandIn.session(),
                             pause: { ms in clock.wait(ms) }, clockMs: { clock.read() })
        client.autoRefresh = refresh
        return client
    }

    private var seen: [Seen] { StandIn.lock.lock(); defer { StandIn.lock.unlock() }; return StandIn.seen }
    private var lines: [String] { seen.map { "\($0.method) \($0.path)" } }
    private func answer(_ text: String, status: Int = 200) { StandIn.reply = { _ in (status, text) } }
    private func refusal(_ work: () async throws -> Void) async -> ApiError? {
        do { try await work(); return nil } catch let error as ApiError { return error } catch { XCTFail("another kind of error: \(error)"); return nil }
    }

    /// The server of a login that lasts 1000 s: it answers the login, the renewal and the fleet.
    private func serveLogin() {
        StandIn.reply = { note in
            switch note.path {
            case "/api/v1/auth/login": return (200, #"{"token":"t_new","name":"Ana","role":"operator","session_id":"s1","expires_s":1000}"#)
            case "/api/v1/auth/refresh": return (200, #"{"ok":true,"expires_s":1000}"#)
            default: return (200, #"{"machines":[]}"#)
            }
        }
    }

    // ---- the login and its life

    func testALoginReadsTheIdOfTheLoginAndHowLongItLasts() async throws {
        serveLogin()
        let login = try await api().login(name: "ana", password: "secret phrase")
        XCTAssertEqual(login, Login(token: "t_new", name: "Ana", role: "operator", sessionId: "s1", expiresS: 1000))
    }

    func testTheClientKeepsTheTokenOfTheLoginItMade() async throws {
        serveLogin()
        let client = api()
        _ = try await client.login(name: "ana", password: "secret phrase")
        XCTAssertEqual(client.token, "t_new")
        _ = try await client.fleet()
        XCTAssertEqual(seen.last?.authorization, "Bearer t_new")
    }

    func testALoginInTheLastQuarterOfItsLifeIsRenewedBeforeTheNextRequest() async throws {
        serveLogin()
        let client = api()
        _ = try await client.login(name: "ana", password: "secret phrase")
        time.advance(seconds: 800)
        _ = try await client.fleet()
        XCTAssertEqual(lines, ["POST /api/v1/auth/login", "POST /api/v1/auth/refresh", "GET /api/v1/fleet"])
        XCTAssertEqual(seen[1].authorization, "Bearer t_new")
    }

    func testALoginBeforeTheLastQuarterIsNotRenewed() async throws {
        serveLogin()
        let client = api()
        _ = try await client.login(name: "ana", password: "secret phrase")
        time.advance(seconds: 700)
        _ = try await client.fleet()
        XCTAssertEqual(lines, ["POST /api/v1/auth/login", "GET /api/v1/fleet"])
    }

    func testARenewalGivesTheLoginItsWholeLifeAgainSoItIsNotRenewedTwice() async throws {
        serveLogin()
        let client = api()
        _ = try await client.login(name: "ana", password: "secret phrase")
        time.advance(seconds: 800)
        _ = try await client.fleet()
        _ = try await client.fleet()
        XCTAssertEqual(lines.filter { $0.hasSuffix("/auth/refresh") }.count, 1)
    }

    func testTheCallsOfTheLoginAreNeverPrecededByARenewal() async throws {
        serveLogin()
        let client = api()
        _ = try await client.login(name: "ana", password: "secret phrase")
        time.advance(seconds: 900)
        answer(#"{"sessions":[]}"#)
        _ = try await client.sessions()
        XCTAssertEqual(lines, ["POST /api/v1/auth/login", "GET /api/v1/auth/sessions"])
    }

    func testAnUnknownLifeIsNeverRenewed() async throws {
        answer(#"{"machines":[]}"#)
        let client = api(token: "t_kept")
        time.advance(seconds: 100_000)
        _ = try await client.fleet()
        XCTAssertEqual(lines, ["GET /api/v1/fleet"])
    }

    func testARenewalThatFailsIsLeftToTheRequestItself() async throws {
        StandIn.reply = { note in note.path.hasSuffix("/auth/refresh") ? (500, #"{"error":"internal"}"#) : (note.path.hasSuffix("/login") ? (200, #"{"token":"t","expires_s":100}"#) : (200, #"{"machines":[]}"#)) }
        let client = api()
        _ = try await client.login(name: "ana", password: "secret phrase")
        time.advance(seconds: 90)
        _ = try await client.fleet()
        XCTAssertEqual(lines.last, "GET /api/v1/fleet")
    }

    func testTheRenewalCanBeTurnedOff() async throws {
        serveLogin()
        let client = api(refresh: false)
        _ = try await client.login(name: "ana", password: "secret phrase")
        time.advance(seconds: 900)
        _ = try await client.fleet()
        XCTAssertEqual(lines, ["POST /api/v1/auth/login", "GET /api/v1/fleet"])
    }

    func testRefreshingAKeptSessionReadsTheSecondsLeft() async throws {
        answer(#"{"ok":true,"expires_s":86400}"#)
        let left = try await api(token: "t_kept").refresh()
        XCTAssertEqual(left, 86400)
        XCTAssertEqual(seen[0].method, "POST")
        XCTAssertEqual(seen[0].path, "/api/v1/auth/refresh")
        XCTAssertEqual(seen[0].body, "{}")
    }

    // ---- a refusal of the login

    func testA401MakesTheClientForgetTheToken() async {
        answer(#"{"error":"unauthorized"}"#, status: 401)
        let client = api(token: "t_old")
        let error = await refusal { _ = try await client.fleet() }
        XCTAssertEqual(error?.unauthorized, true)
        XCTAssertEqual(client.token, "")
        _ = await refusal { _ = try await client.fleet() }
        XCTAssertNil(seen[1].authorization)
    }

    func testA401OfTheLoginItselfIsAWrongPasswordAndKeepsTheToken() async {
        answer(#"{"error":"unauthorized"}"#, status: 401)
        let client = api(token: "t_kept")
        _ = await refusal { _ = try await client.login(name: "ana", password: "wrong") }
        XCTAssertEqual(client.token, "t_kept")
    }

    func testA403KeepsTheTokenBecauseTheLoginIsGoodAndOnlyTheRoleIsNot() async {
        answer(#"{"error":"forbidden"}"#, status: 403)
        let client = api(token: "t_kept")
        let error = await refusal { _ = try await client.fleet() }
        XCTAssertEqual(error?.forbidden, true)
        XCTAssertEqual(error?.unauthorized, false)
        XCTAssertEqual(client.token, "t_kept")
    }

    // ---- the logins and the machines of the plugins

    func testTheLoginsOfThePersonAreListed() async throws {
        answer(#"{"sessions":[{"id":"s1","name":"ana","role":"operator","app":"ios","ip":"192.168.0.7","current":true},{"id":"s2","name":"ana","role":"operator","app":"studio","ip":"192.168.0.9"}]}"#)
        let list = try await api(token: "t").sessions()
        XCTAssertEqual(list.map { $0.id }, ["s1", "s2"])
        XCTAssertEqual(list.map { $0.current }, [true, false])
        XCTAssertEqual(seen[0].method, "GET")
        XCTAssertEqual(seen[0].path, "/api/v1/auth/sessions")
    }

    func testOneLoginIsClosedByItsEncodedId() async throws {
        answer(#"{"ok":true}"#)
        try await api(token: "t").closeSession("a b/c")
        XCTAssertEqual(seen[0].method, "DELETE")
        XCTAssertEqual(seen[0].path, "/api/v1/auth/sessions/a%20b%2Fc")
    }

    func testEveryLoginIsEndedWithOnePost() async throws {
        answer(#"{"ok":true}"#)
        try await api(token: "t").logoutAll()
        XCTAssertEqual(lines, ["POST /api/v1/auth/logout-all"])
        XCTAssertEqual(seen[0].body, "{}")
    }

    func testSigningOutUsesTheSingleLogoutOfTheServer() async {
        await api(token: "t").logout()
        XCTAssertEqual(lines, ["POST /api/v1/auth/logout"])
    }

    func testTheMachinesOfThePluginsAreReadFromTheWorkRoute() async throws {
        answer(#"{"machines":[{"id":"l1","name":"Laser","plugin":"laser","state":"idle","detail":{"estop_latched":true}},{"id":"b1","plugin":"bungard"}]}"#)
        let list = try await api(token: "t").workMachines()
        XCTAssertEqual(lines, ["GET /api/v1/work/machines"])
        XCTAssertEqual(list.map { $0.id }, ["l1"])
        XCTAssertTrue(list[0].latched)
    }

    // ---- time-out and tries again

    func testTheTimeOutOfEachTryIsASettingOfTheConnection() async throws {
        answer("{}")
        let client = api(token: "t", timeoutS: 40)
        _ = try await client.health()
        client.settings = client.settings.withTimeout(7)
        _ = try await client.health()
        XCTAssertEqual(seen.map { $0.timeout }, [40, 7])
    }

    func testAReadIsTriedAgainAfterABadGatewayWithGrowingPauses() async throws {
        StandIn.reply = { _ in StandIn.attempts < 3 ? (503, #"{"error":"busy"}"#) : (200, #"{"machines":[]}"#) }
        _ = try await api(token: "t", retries: 2).fleet()
        XCTAssertEqual(seen.count, 3)
        XCTAssertEqual(time.pauses, [200, 400])
    }

    func testTheTriesStopWhenTheRetriesAreSpent() async {
        answer(#"{"error":"busy"}"#, status: 503)
        let error = await refusal { _ = try await self.api(token: "t", retries: 2).fleet() }
        XCTAssertEqual(error?.status, 503)
        XCTAssertEqual(seen.count, 3)
    }

    func testNothingIsTriedAgainWithNoRetries() async {
        answer(#"{"error":"busy"}"#, status: 503)
        _ = await refusal { _ = try await self.api(token: "t", retries: 0).fleet() }
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(time.pauses, [])
    }

    func testThePausesGrowToTwoSecondsAndNoFurther() async {
        answer(#"{"error":"busy"}"#, status: 503)
        _ = await refusal { _ = try await self.api(token: "t", retries: 5).fleet() }
        XCTAssertEqual(time.pauses, [200, 400, 800, 1600, 2000])
    }

    func testAPostIsNeverSentTwiceAfterAnAnswerOrATimeOut() async {
        answer(#"{"error":"busy"}"#, status: 503)
        _ = await refusal { try await self.api(token: "t", retries: 3).start("j1") }
        XCTAssertEqual(seen.count, 1)
        StandIn.reset()
        StandIn.failure = URLError(.timedOut)
        _ = await refusal { try await self.api(token: "t", retries: 3).start("j1") }
        XCTAssertEqual(seen.count, 1)
    }

    func testAPostIsTriedAgainWhenTheConnectionCouldNotBeMade() async {
        StandIn.failure = URLError(.cannotConnectToHost)
        let error = await refusal { try await self.api(token: "t", retries: 2).start("j1") }
        XCTAssertEqual(seen.count, 3)
        XCTAssertEqual(error?.status, 0)
        XCTAssertEqual(error?.neverSent, true)
    }

    func testAReadIsTriedAgainAfterATimeOutButAnAnswerOfTheServerIsFinal() async {
        StandIn.failure = URLError(.timedOut)
        let error = await refusal { _ = try await self.api(token: "t", retries: 1).fleet() }
        XCTAssertEqual(seen.count, 2)
        XCTAssertEqual(error?.neverSent, false)
        StandIn.reset()
        answer(#"{"error":"unknown_machine"}"#, status: 404)
        _ = await refusal { _ = try await self.api(token: "t", retries: 3).job("gone") }
        XCTAssertEqual(seen.count, 1)
    }

    func testWhatTheSystemSaysOfAConnectionThatWasNeverMade() {
        for code in [URLError.Code.cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet] { XCTAssertTrue(Eh3dApi.neverSent(code), "\(code)") }
        for code in [URLError.Code.timedOut, .networkConnectionLost, .cancelled, .badServerResponse] { XCTAssertFalse(Eh3dApi.neverSent(code), "\(code)") }
    }

    func testTheSettingsOfTheConnectionAreBroughtIntoTheirRange() {
        XCTAssertEqual(Eh3dApi(origin: origin, settings: ConnectionSettings(timeoutS: 0, retries: 99)).settings, ConnectionSettings(timeoutS: 1, retries: 5))
    }

    // ---- the machines of the plugins

    private func pluginMachine(_ kind: String, job: String = "") -> WorkMachine { WorkMachine(id: "m1", name: "M", plugin: kind, state: "idle", latched: false, detail: [], job: job) }

    func testTheEmergencyStopOfACncMachineOrAPrinterIsItsOwnRouteSentAtOnceWithNoOtherRequest() async throws {
        for kind in ["cnc", "printer3d"] {
            StandIn.reset()
            answer(#"{"ok":true}"#)
            let sent = try await api(token: "t").emergencyStopWork(pluginMachine(kind))
            XCTAssertTrue(sent, kind)
            XCTAssertEqual(seen.map { "\($0.method) \($0.path)" }, ["POST /api/v1/work/machines/m1/emergency-stop"], kind)
            XCTAssertEqual(seen[0].authorization, "Bearer t")
        }
    }

    func testTheEmergencyStopOfAMachineWithoutARouteOfItsOwnCancelsTheJobThatRunsOnIt() async throws {
        answer(#"{"ok":true}"#)
        let sent = try await api(token: "t").emergencyStopWork(pluginMachine("laser", job: "w-7"))
        XCTAssertTrue(sent)
        XCTAssertEqual(seen.map { "\($0.method) \($0.path)" }, ["POST /api/v1/work/jobs/w-7/cancel"])
    }

    func testAMachineWithNeitherARouteNorAJobIsAskedNothing() async throws {
        let sent = try await api(token: "t").emergencyStopWork(pluginMachine("pnp"))
        XCTAssertFalse(sent)
        XCTAssertTrue(seen.isEmpty)
    }

    func testAStopThatTheServerRefusesIsAnErrorToShowAndIsNotHidden() async {
        answer(#"{"error":"forbidden"}"#, status: 403)
        let client = api(token: "t")
        let machine = pluginMachine("cnc")
        let error = await refusal { _ = try await client.emergencyStopWork(machine) }
        XCTAssertEqual(error?.forbidden, true)
        XCTAssertEqual(seen.count, 1, "a refusal is not sent again")
    }

    func testAStopThatGotNoAnswerIsSentOnceMoreAndThenSaidToHaveFailed() async {
        StandIn.failure = URLError(.timedOut)
        let client = api(token: "t")
        let machine = pluginMachine("printer3d")
        let error = await refusal { _ = try await client.emergencyStopWork(machine) }
        XCTAssertEqual(error?.status, 0)
        XCTAssertEqual(seen.map { $0.path }, ["/api/v1/work/machines/m1/emergency-stop", "/api/v1/work/machines/m1/emergency-stop"])
    }

    func testTheReleaseOfALatchUsesTheRouteOfThePluginAndAPluginThatDoesNotLatchIsAskedNothing() async throws {
        for (kind, path) in [("cnc", "release"), ("printer3d", "release"), ("laser", "laser/release")] {
            StandIn.reset()
            answer(#"{"released":true}"#)
            let released = try await api(token: "t").releaseWork(pluginMachine(kind))
            XCTAssertTrue(released, kind)
            XCTAssertEqual(seen.map { "\($0.method) \($0.path)" }, ["POST /api/v1/work/machines/m1/\(path)"], kind)
        }
        StandIn.reset()
        let none = try await api(token: "t").releaseWork(pluginMachine("pcb"))
        XCTAssertFalse(none)
        XCTAssertTrue(seen.isEmpty)
    }

    func testTheQueueIsReadFromTheGenericRouteAndAJobIsStartedOrCancelledByItsIdWithAnEmptyBody() async throws {
        answer(#"{"items":[{"id":"w-2","machine":"p1","state":"queued"}]}"#)
        let client = api(token: "t")
        let jobs = try await client.workJobs()
        XCTAssertEqual(jobs.map { $0.id }, ["w-2"])
        try await client.startWorkJob("w-2")
        try await client.cancelWorkJob("w-3")
        XCTAssertEqual(seen.map { "\($0.method) \($0.path)" }, ["GET /api/v1/work/jobs", "POST /api/v1/work/jobs/w-2/start", "POST /api/v1/work/jobs/w-3/cancel"])
        XCTAssertEqual(seen[0].query, "limit=100")
        XCTAssertEqual(seen[1].body, "{}")
    }

    func testTheSwitchesOfTheServerAreReadFromThePolicyAndARoleThatIsNotAnAdministratorIsRefused() async throws {
        answer(#"{"switches":[{"key":"mdns_announce","value":false,"safe":true}]}"#)
        let list = try await api(token: "t").policySwitches()
        XCTAssertEqual(seen[0].path, "/api/v1/auth/policy")
        XCTAssertEqual(list.map { $0.key }, ["mdns_announce"])
        StandIn.reset()
        answer(#"{"error":"forbidden"}"#, status: 403)
        let client = api(token: "t")
        let error = await refusal { _ = try await client.policySwitches() }
        XCTAssertEqual(error?.forbidden, true)
        XCTAssertEqual(client.token, "t", "a refusal for the role keeps the login")
    }

    func testAStartNamesTheHashThatWasShownAndAnAuthorizationSendsItInItsOwnRoute() async throws {
        StandIn.reset()
        answer(#"{"ok":true}"#)
        let client = api(token: "t")
        try await client.authorizeWorkJob("w-2", hash: "H1")
        try await client.startWorkJob("w-2", hash: "H1")
        try await client.startWorkJob("w-3")
        XCTAssertEqual(seen.map { "\($0.method) \($0.path)" }, ["POST /api/v1/work/jobs/w-2/authorize", "POST /api/v1/work/jobs/w-2/start", "POST /api/v1/work/jobs/w-3/start"])
        let sent = try [0, 1].map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data(seen[$0].body.utf8)) as? [String: String]) }
        XCTAssertEqual(sent[0]["toolpath_sha256"], "H1")
        XCTAssertEqual(sent[1]["toolpath_sha256"], "H1")
        XCTAssertEqual(seen[2].body, "{}", "a start with no hash keeps the empty body")
    }

    func testTheRefusalsOfTheAuthorizationAreToldApartAndNothingIsRetried() async throws {
        for code in ["stale_authorization", "authorization_required"] {
            StandIn.reset()
            answer(#"{"error":"\#(code)","detail":"x"}"#, status: 409)
            let client = api(token: "t")
            let error = await refusal { try await client.startWorkJob("w-2", hash: "H1") }
            XCTAssertEqual(error?.status, 409)
            XCTAssertEqual(error?.code, code)
            XCTAssertTrue(MachineSafety.needsReview(error?.code ?? ""))
            XCTAssertEqual(seen.count, 1, "a refused start is sent once")
        }
    }
}
