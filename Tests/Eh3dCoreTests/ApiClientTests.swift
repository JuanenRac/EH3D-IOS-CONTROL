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
}

/// A server that lives in the test: it answers every request of a session built with it and writes down what it was asked. Tests of this file run one at a time.
private final class StandIn: URLProtocol {
    static let lock = NSLock()
    static var seen: [Seen] = []
    static var reply: (Seen) -> (Int, String) = { _ in (200, "{}") }
    static var failure: Error?

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
                        agent: request.value(forHTTPHeaderField: "User-Agent"), body: StandIn.body(of: request))
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

    private func api(token: String = "", origin: String? = nil) -> Eh3dApi { Eh3dApi(origin: origin ?? self.origin, token: token, session: StandIn.session()) }
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
        XCTAssertEqual(seen[0].path, "/api/v1/login")
        XCTAssertEqual(try json(seen[0].body)["name"] as? String, "ana")
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
        XCTAssertEqual(seen[0].path, "/api/v1/logout")
        XCTAssertEqual(seen[0].method, "POST")
    }
}
