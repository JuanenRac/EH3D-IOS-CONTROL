import XCTest
@testable import Eh3dCore

/// A server of the test that lists the nodes of the pick-and-place machines, or answers 501 while they are switched off, and writes down what it was asked. Nothing here has talked to a real feeder or
/// head. Tests of this file run one at a time.
private final class PnpSim: URLProtocol {
    static let lock = NSLock()
    static var off = false
    static var calls: [String] = []
    static var authorizations: [String] = []

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        off = false; calls = []; authorizations = []
    }

    static var asked: [String] { lock.lock(); defer { lock.unlock() }; return calls }
    static var tokens: [String] { lock.lock(); defer { lock.unlock() }; return authorizations }
    static func switchOff() { lock.lock(); defer { lock.unlock() }; off = true }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PnpSim.self]
        return URLSession(configuration: configuration)
    }

    /// The answer of the server for a feeder that is ready and a head that is silent.
    static let answer = """
        {"nodes":[
        {"id":"feeder-1","kind":"feeder","name":"Feeders left","address":"192.168.0.60:80","token":"********","machine":"pnp-1","enabled":true,"health":"ok","ready":true,"silent_for_s":null,
        "polls":{"ok":7,"failed":1},"last_error":"","status":{"safe":false,"selfcheck":"ok","slots":4,"online":3,"low":1,"empty":0,"faulted":0,"bus":"rs485","node":"feeder-a"},"evidence":"simulator","simulator_only":true},
        {"id":"head-1","kind":"head","name":"Head","address":"192.168.0.61:80","token":"","machine":"","enabled":true,"health":"silent","ready":false,
        "polls":{"ok":0,"failed":9},"last_error":"unreachable","status":null,"evidence":"simulator"}],
        "summary":{"registered":2,"ready":1,"not_ready":1},"limits":{"max":16,"poll_s":5,"silence_s":30,"timeout_s":3,"kinds":["feeder","head"]}}
        """

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        PnpSim.lock.lock()
        PnpSim.calls.append("\(request.httpMethod ?? "GET") \(url.path)")
        PnpSim.authorizations.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
        let off = PnpSim.off
        PnpSim.lock.unlock()
        var status = 200
        var text = PnpSim.answer
        if url.path != "/api/v1/pnp/nodes" { status = 404; text = #"{"error":"not_found"}"# }
        else if off { status = 501; text = #"{"error":"pnp_nodes_off","detail":"the nodes are off"}"# }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// A small generator that gives the same numbers every time (xorshift32), for the answers made from a fixed seed.
private struct FixedSeed {
    var state: UInt32
    mutating func below(_ n: Int) -> Int {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return Int(state % UInt32(n))
    }
}

/// The nodes of the pick-and-place machines as the phone reads them, read only. The same cases as the Android app (PnpNodesTest).
final class PnpNodesTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PnpSim.reset()
    }

    private func phone() -> Eh3dApi {
        let client = Eh3dApi(origin: "http://sim.test:18200", token: "t_abc", settings: ConnectionSettings(retries: 0), session: PnpSim.session())
        client.autoRefresh = false
        return client
    }

    func testAFeederAndAHeadAreReadWithTheirHealthReadinessAndTheNumbersTheySaidLast() throws {
        let nodes = try parsePnpNodes(PnpSim.answer)
        XCTAssertEqual(nodes.map { $0.id }, ["feeder-1", "head-1"])
        let feeder = nodes[0]
        XCTAssertEqual(feeder.kind, "feeder")
        XCTAssertEqual(feeder.name, "Feeders left")
        XCTAssertEqual(feeder.address, "192.168.0.60:80")
        XCTAssertEqual(feeder.machine, "pnp-1")
        XCTAssertTrue(feeder.enabled)
        XCTAssertEqual(feeder.health, "ok")
        XCTAssertTrue(feeder.ready)
        XCTAssertTrue(feeder.simulatorOnly)
        XCTAssertEqual(feeder.facts.map { "\($0.key)=\($0.value)" }, ["safe=false", "selfcheck=ok", "online=3", "slots=4", "low=1", "empty=0", "faulted=0"])
        let head = nodes[1]
        XCTAssertEqual(head.kind, "head")
        XCTAssertEqual(head.health, "silent")
        XCTAssertFalse(head.ready)
        XCTAssertEqual(head.lastError, "unreachable")
        XCTAssertEqual(head.machine, "")
        XCTAssertEqual(head.facts, [])
    }

    func testTheTokenOfANodeIsNeverReadSoItCannotBeShown() throws {
        let nodes = try parsePnpNodes(PnpSim.answer)
        let text = String(describing: nodes)
        XCTAssertFalse(text.contains("********"))
        XCTAssertFalse(text.contains("token"))
    }

    func testAnAnswerThatDoesNotSayIsNotReadyAndANodeWithoutAnIdOrAListThatIsNotOneIsLeftOut() throws {
        let nodes = try parsePnpNodes(#"{"nodes":[{"id":"n1"},{"name":"no id"},{"id":""}]}"#)
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].id, "n1")
        XCTAssertEqual(nodes[0].name, "n1")
        XCTAssertEqual(nodes[0].health, "unknown")
        XCTAssertFalse(nodes[0].ready)
        XCTAssertTrue(nodes[0].enabled)
        let none = try parsePnpNodes("{}")
        let notAList = try parsePnpNodes(#"{"nodes":"x"}"#)
        let empty = try parsePnpNodes(#"{"nodes":[]}"#)
        XCTAssertEqual(none, [])
        XCTAssertEqual(notAList, [])
        XCTAssertEqual(empty, [])
    }

    func testOnlyTheNumbersThePhoneListsAreTakenFromWhatANodeSaidInAFixedOrder() throws {
        let list = try parsePnpNodes(#"{"nodes":[{"id":"h","kind":"head","status":{"pump":true,"extra":"x","faulted":2,"safe":null,"nozzle_count":2}}]}"#)
        let node = try XCTUnwrap(list.first)
        XCTAssertEqual(node.facts.map { "\($0.key)=\($0.value)" }, ["faulted=2", "nozzle_count=2", "pump=true"])
    }

    func testAnswersMadeFromAFixedSeedWithAnyKindOfValueNeverBreakTheReading() throws {
        var seed = FixedSeed(state: 20261121)
        let pieces = [#""x""#, "\"\"", "5", "1.5", "true", "false", "null", #"{"safe":true,"pump":"on"}"#]
        let keys = ["id", "kind", "name", "address", "machine", "enabled", "health", "ready", "last_error", "status", "evidence", "simulator_only"]
        for _ in 0..<300 {
            var items: [String] = []
            for _ in 0..<seed.below(4) {
                var fields: [String] = []
                for key in keys {
                    if seed.below(2) == 0 { fields.append("\"\(key)\":\(pieces[seed.below(pieces.count)])") }
                }
                items.append("{" + fields.joined(separator: ",") + "}")
            }
            let nodes = try parsePnpNodes("{\"nodes\":[" + items.joined(separator: ",") + "]}")
            XCTAssertTrue(nodes.allSatisfy { !$0.id.isEmpty })
            XCTAssertLessThanOrEqual(nodes.count, items.count)
        }
    }

    func testTheCallAsksGetPnpNodesWithTheTokenAndReadsTheList() async throws {
        let nodes = try await phone().pnpNodes()
        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(PnpSim.asked, ["GET /api/v1/pnp/nodes"])
        XCTAssertEqual(PnpSim.tokens, ["Bearer t_abc"])
    }

    func testAServerThatHasTheNodesSwitchedOffAnswersWithItsCode() async {
        PnpSim.switchOff()
        do {
            _ = try await phone().pnpNodes()
            XCTFail("the nodes are off: the call must fail")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 501)
            XCTAssertEqual(error.code, "pnp_nodes_off")
            XCTAssertFalse(error.unauthorized)
        } catch {
            XCTFail("another error: \(error)")
        }
    }
}
