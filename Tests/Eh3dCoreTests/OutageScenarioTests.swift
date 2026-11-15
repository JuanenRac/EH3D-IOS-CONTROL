import XCTest
@testable import Eh3dCore

/// A server that goes away and comes back: what it does now is chosen by the test, and every poll of the app goes through the real client (`Eh3dApi`) and the real rules of the link
/// (`classifyFailure`, `ServerLink`). Nothing here uses the network, a clock or a random generator of the system: the seeded runs are the same every time.
private final class Outage: URLProtocol {
    enum Mode { case ok, unreachable, serverError, otherService, sessionExpired }
    static let lock = NSLock()
    static var mode: Mode = .ok
    static var fleetText = "{}"

    static func set(_ mode: Mode) { lock.lock(); defer { lock.unlock() }; Outage.mode = mode }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Outage.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Outage.lock.lock()
        let mode = Outage.mode
        let fleet = Outage.fleetText
        Outage.lock.unlock()
        let url = request.url!
        func answer(_ status: Int, _ text: String) {
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(text.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        switch mode {
        case .ok: answer(200, fleet)
        case .unreachable: client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case .serverError: answer(503, #"{"error":"unavailable"}"#)
        case .otherService: answer(404, "<html>not found</html>")
        case .sessionExpired: answer(401, #"{"error":"unauthorized"}"#)
        }
    }
}

final class OutageScenarioTests: XCTestCase {
    private let origin = "http://sim.test:18200"

    override func setUp() {
        super.setUp()
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Examples").appendingPathComponent("fleet.json")
        Outage.fleetText = (try? String(contentsOf: url, encoding: .utf8)) ?? "{}"
        Outage.set(.ok)
    }

    private func api() -> Eh3dApi { Eh3dApi(origin: origin, token: "t", session: Outage.session()) }

    /// One poll of the app: asks for the fleet and keeps the link the way the app does (the server that answers as itself, even with a refusal, is a link that works).
    private func poll(_ link: ServerLink, at nowMs: Int64) async -> ServerLink {
        do {
            _ = try await api().fleet()
            return link.succeeded(nowMs: nowMs)
        } catch let error as ApiError {
            if let why = classifyFailure(status: error.status, code: error.code) { return link.failed(why, nowMs: nowMs) }
            return link.succeeded(nowMs: nowMs)
        } catch {
            XCTFail("another kind of error: \(error)")
            return link
        }
    }

    func testTheServerGoesAwayThePollsFailAndTheLinkComesBackWithTheFirstGoodAnswer() async {
        var link = await poll(ServerLink(), at: 10_000)
        XCTAssertEqual(link.state(), .connected)
        XCTAssertEqual(link.failures, 0)
        Outage.set(.unreachable)
        link = await poll(link, at: 11_500)
        XCTAssertEqual(link.state(), .connected, "one failure is not yet no connection")
        link = await poll(link, at: 13_000)
        XCTAssertEqual(link.state(), .offline)
        XCTAssertEqual(LinkPolicy().retryDelayMs(link.failures), 3_000)
        Outage.set(.ok)
        link = await poll(link, at: 16_000)
        XCTAssertEqual(link.state(), .connected)
        XCTAssertEqual(link.failures, 0)
        XCTAssertEqual(LinkPolicy().retryDelayMs(link.failures), 1_500, "the pace is the normal one again")
    }

    func testAServerThatAnswersWithAnErrorOfItsOwnIsUnreachableAndOneThatAnswersAsAnotherServiceIsTheWrongServer() async {
        var link = await poll(ServerLink(), at: 10_000)
        Outage.set(.serverError)
        link = await poll(link, at: 11_500)
        link = await poll(link, at: 13_000)
        XCTAssertEqual(link.state(), .offline)
        Outage.set(.ok)
        link = await poll(link, at: 14_500)
        XCTAssertEqual(link.state(), .connected)
        Outage.set(.otherService)
        link = await poll(link, at: 16_000)
        XCTAssertEqual(link.state(), .wrongServer, "a page of another service is not no connection")
        Outage.set(.ok)
        link = await poll(link, at: 17_500)
        XCTAssertEqual(link.state(), .connected)
    }

    func testAnExpiredSessionIsTheServerAnsweringAsItselfNotALostLink() async {
        var link = await poll(ServerLink(), at: 10_000)
        Outage.set(.sessionExpired)
        do {
            _ = try await api().fleet()
            XCTFail("the server refused")
        } catch let error as ApiError {
            XCTAssertTrue(error.unauthorized)
        } catch {
            XCTFail("\(error)")
        }
        link = await poll(link, at: 11_500)
        link = await poll(link, at: 13_000)
        XCTAssertEqual(link.state(), .connected)
        XCTAssertEqual(link.failures, 0)
    }

    func testOldDataWithOneFailureIsStaleAndAFirstFailureWithNothingToBeOldIsStillConnected() async {
        var link = await poll(ServerLink(), at: 10_000)
        Outage.set(.unreachable)
        link = await poll(link, at: 15_000)
        XCTAssertEqual(link.state(), .stale)
        let first = await poll(ServerLink(), at: 1_000)
        XCTAssertEqual(first.state(), .connected)
        XCTAssertNil(first.ageS())
    }

    func testSeededOutagesAlwaysEndOfflineAfterTwoFailuresWithGrowingWaitsAndAlwaysComeBack() async {
        var seed: UInt32 = 20_260
        func next(_ n: UInt32) -> UInt32 {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return (seed >> 8) % n
        }
        let policy = LinkPolicy()
        for _ in 0..<30 {
            Outage.set(.ok)
            var now: Int64 = 10_000
            var link = await poll(ServerLink(), at: now)
            let length = 2 + Int(next(5))
            var lastWait = 0
            for i in 0..<length {
                Outage.set(next(2) == 0 ? .unreachable : .serverError)
                now += Int64(policy.retryDelayMs(link.failures + 1))
                link = await poll(link, at: now)
                let wait = policy.retryDelayMs(link.failures)
                XCTAssertGreaterThanOrEqual(wait, lastWait)
                XCTAssertLessThanOrEqual(wait, 10_000)
                lastWait = wait
                XCTAssertEqual(link.state() == .offline, i >= 1, "offline from the second failure on")
            }
            Outage.set(.ok)
            now += Int64(policy.retryDelayMs(link.failures))
            link = await poll(link, at: now)
            XCTAssertEqual(link.state(), .connected)
            XCTAssertEqual(link.failures, 0)
        }
    }
}
