import XCTest
@testable import Eh3dCore

/// A server of the test that answers the list of printers with the status and the body it is told, and writes down what it was asked. Nothing here has talked to a real printer. Tests of this file run one at a time.
private final class PrinterSim: URLProtocol {
    static let lock = NSLock()
    static var status = 200
    static var body = ""
    static var calls: [String] = []

    static func answer(_ status: Int, _ body: String) {
        lock.lock(); defer { lock.unlock() }
        self.status = status; self.body = body; calls = []
    }

    static var asked: [String] { lock.lock(); defer { lock.unlock() }; return calls }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PrinterSim.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        PrinterSim.lock.lock()
        PrinterSim.calls.append("\(request.httpMethod ?? "GET") \(url.path) \(request.value(forHTTPHeaderField: "Authorization") ?? "")")
        let status = PrinterSim.status
        let text = PrinterSim.body
        PrinterSim.lock.unlock()
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// A small generator that gives the same numbers every time (xorshift32), for the answers made from a fixed seed.
private struct PrinterSeed {
    var state: UInt32
    mutating func below(_ n: Int) -> Int {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return Int(state % UInt32(n))
    }
}

/// The 3D printers as the phone reads them, read only: the cases shared with the Android app (printer_cases.json: simulated answers and hostile ones), random answers made from a fixed seed and the
/// request against a stand-in of the server. The same cases as the Android app (PrintersTest).
final class PrintersTests: XCTestCase {
    private typealias Obj = [String: Any]

    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    private func shared() throws -> Obj {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Cases").appendingPathComponent("printer_cases.json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? Obj)
    }

    private func double(_ any: Any?) -> Double? { (any as? NSNumber)?.doubleValue }
    private func int(_ any: Any?) -> Int? { (any as? NSNumber)?.intValue }

    private func check(_ name: String, _ want: Obj, _ got: Printer) throws {
        let id = try XCTUnwrap(want["id"] as? String)
        let at = "\(name): \(id)"
        XCTAssertEqual(got.id, id, at)
        XCTAssertEqual(got.name, want["name"] as? String, at)
        XCTAssertEqual(got.family, want["family"] as? String, at)
        XCTAssertEqual(got.health, want["health"] as? String, at)
        XCTAssertEqual(got.current, want["current"] as? Bool, at)
        XCTAssertEqual(got.state, want["state"] as? String, at)
        let temperatures = try XCTUnwrap(want["temperatures"] as? [[Any]], at)
        XCTAssertEqual(got.temperatures.count, temperatures.count, at)
        for (t, row) in zip(got.temperatures, temperatures) {
            XCTAssertEqual(t.name, row[0] as? String, at)
            XCTAssertEqual(t.currentC, double(row[1]), at)
            XCTAssertEqual(t.targetC, double(row[2]), at)
        }
        XCTAssertEqual(got.progressPct, double(want["progress"]), at)
        XCTAssertEqual(got.remainingS, int(want["remaining_s"]), at)
        XCTAssertEqual(got.remainingEstimated, want["estimated"] as? Bool, at)
        XCTAssertEqual(got.layer, int(want["layer"]), at)
        XCTAssertEqual(got.layers, int(want["layers"]), at)
        XCTAssertEqual(got.jobName, want["job"] as? String, at)
        if let alerts = want["alerts"] as? [[String]] {
            XCTAssertEqual(got.alerts?.map { [$0.severity, $0.code, $0.message] }, alerts, at)
        } else {
            XCTAssertNil(got.alerts, at)
        }
        XCTAssertEqual(got.ageS, int(want["age_s"]), at)
        XCTAssertEqual(got.simulated, want["simulated"] as? Bool, at)
    }

    func testEverySharedAnswerIsReadAsTheCaseSays() throws {
        let cases = try XCTUnwrap(try shared()["documents"] as? [Obj])
        XCTAssertGreaterThanOrEqual(cases.count, 20)
        for c in cases {
            let name = c["name"] as? String ?? ""
            let read = parsePrinters(try XCTUnwrap(c["body"] as? String))
            if let want = c["expect"] as? [Obj] {
                let got = try XCTUnwrap(read, name)
                XCTAssertEqual(got.count, want.count, name)
                for (w, g) in zip(want, got) { try check(name, w, g) }
            } else {
                XCTAssertNil(read, name)
            }
        }
    }

    private func view(_ word: String) -> PrinterView { word == "listed" ? .listed : word == "unreadable" ? .unreadable : .hidden }

    func testAfterEverySharedFailureThePageShowsWhatTheCaseSays() throws {
        let one = try XCTUnwrap(parsePrinters(#"{"schema":"eh3d.printers.status/1","printers":[{"id":"a"}]}"#))
        for c in try XCTUnwrap(try shared()["failures"] as? [Obj]) {
            let status = try XCTUnwrap(c["status"] as? Int)
            let code = try XCTUnwrap(c["code"] as? String)
            let was = c["before"] as? String ?? ""
            let name = "\(status) \(code) after \(was)"
            let before: PrinterListing = was == "listed" ? PrinterListing(.listed, printers: one) : was == "unreadable" ? .unreadable : .hidden
            let after = printersAfterFailure(before, status: status, code: code)
            XCTAssertEqual(after.view, view(c["view"] as? String ?? ""), name)
            XCTAssertEqual(after.old, c["old"] as? Bool, name)
            XCTAssertEqual(after.printers.count, after.view == .listed ? 1 : 0, name)
        }
    }

    func testEveryNumberIsWrittenAsTheCasesSayAndAnUnknownOneIsNeverZero() throws {
        let written = try XCTUnwrap(try shared()["written"] as? Obj)
        func rows(_ key: String) throws -> [[Any]] { try XCTUnwrap(written[key] as? [[Any]], key) }
        for row in try rows("degrees") { XCTAssertEqual(printerDegrees(double(row[0]), unknown: "?"), row[1] as? String, "\(row)") }
        for row in try rows("percent") { XCTAssertEqual(printerPercent(double(row[0]), unknown: "?"), row[1] as? String, "\(row)") }
        for row in try rows("number") { XCTAssertEqual(printerNumber(int(row[0]), unknown: "?"), row[1] as? String, "\(row)") }
        for row in try rows("time_left") {
            let time = printerTimeLeft(try XCTUnwrap(int(row[0])))
            XCTAssertEqual(time.hours, int(row[1]), "\(row)")
            XCTAssertEqual(time.minutes, int(row[2]), "\(row)")
        }
        for row in try rows("family") { XCTAssertEqual(printerFamilyName(row[0] as? String ?? "?"), row[1] as? String, "\(row)") }
    }

    func testAnswersMadeFromAFixedSeedWithAnyKindOfValueNeverBreakTheReading() throws {
        var seed = PrinterSeed(state: 20261126)
        let pieces = [#""x""#, "\"\"", "5", "-5", "1.5", "1e300", "true", "false", "null", "[]", "[1,null]", "{}", #"{"state":"idle","temperatures":[null],"alerts":[{}]}"#]
        let keys = ["name", "family", "current", "age_s", "simulator_only", "secret"]
        let statusKeys = ["state", "temperatures", "progress_pct", "remaining_s", "layer", "layers", "job_name", "alerts"]
        for _ in 0..<400 {
            var items: [String] = []
            for n in 0..<seed.below(4) {
                var fields = ["\"id\":\"p\(n)\"", "\"health\":\"online\""]
                for key in keys { if seed.below(2) == 0 { fields.append("\"\(key)\":\(pieces[seed.below(pieces.count)])") } }
                var status: [String] = []
                for key in statusKeys { if seed.below(2) == 0 { status.append("\"\(key)\":\(pieces[seed.below(pieces.count)])") } }
                fields.append("\"status\":{" + status.joined(separator: ",") + "}")
                items.append("{" + fields.joined(separator: ",") + "}")
            }
            let read = try XCTUnwrap(parsePrinters("{\"schema\":\"eh3d.printers.status/1\",\"printers\":[" + items.joined(separator: ",") + "]}"))
            XCTAssertEqual(read.count, items.count)
            XCTAssertTrue(read.allSatisfy { p in p.progressPct.map { (0...100).contains($0) } ?? true })
            XCTAssertTrue(read.allSatisfy { p in p.temperatures.allSatisfy { t in t.currentC.map { (-100...1000).contains($0) } ?? true } })
        }
    }

    func testTheSecretOfAPrinterIsNeverKeptSoItCannotBeShown() throws {
        let read = try XCTUnwrap(parsePrinters(#"{"schema":"eh3d.printers.status/1","printers":[{"id":"a","secret":"KEY-MUST-NOT-SHOW","serial":"SERIAL-MUST-NOT-SHOW","address":"10.0.0.9"}]}"#))
        let text = String(describing: read)
        for word in ["KEY-MUST-NOT-SHOW", "SERIAL-MUST-NOT-SHOW", "10.0.0.9", "secret"] { XCTAssertFalse(text.contains(word), word) }
    }

    // ---- the request

    private func phone() -> Eh3dApi {
        let client = Eh3dApi(origin: "http://sim.test:18200", token: "t_abc", settings: ConnectionSettings(retries: 0), session: PrinterSim.session())
        client.autoRefresh = false
        return client
    }

    func testTheListIsAskedWithOneGetWithTheTokenAndNothingElseIsSent() async throws {
        PrinterSim.answer(200, #"{"schema":"eh3d.printers.status/1","read_only":true,"printers":[{"id":"a","health":"online","current":true,"status":{"state":"idle"}}]}"#)
        let read = try await phone().printers()
        XCTAssertEqual(read.map { $0.state }, ["idle"])
        XCTAssertEqual(PrinterSim.asked, ["GET /api/v1/printers Bearer t_abc"])
    }

    func testAListSwitchedOffAnOlderServerARefusalOrAnotherServiceIsAnErrorWithItsCode() async {
        let cases: [(Int, String, String)] = [
            (501, #"{"error":"printers_off","detail":"off"}"#, "printers_off"), (404, "not found", "http_404"), (403, #"{"error":"forbidden_scope"}"#, "forbidden_scope"),
            (200, "<html>router</html>", "bad_json"), (200, "[]", "bad_json"), (200, #"{"nodes":[]}"#, "bad_json"),
        ]
        for (status, body, code) in cases {
            PrinterSim.answer(status, body)
            do {
                _ = try await phone().printers()
                XCTFail("must fail: \(body)")
            } catch let error as ApiError {
                XCTAssertEqual(error.status, status, body)
                XCTAssertEqual(error.code, code, body)
            } catch {
                XCTFail("another error: \(error)")
            }
        }
    }

    func testTheAppHasNoRequestThatCouldSendAnythingToAPrinter() throws {
        var uses: [String] = []
        for folder in ["App", "Sources"] {
            for case let file as URL in FileManager.default.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil)! where file.pathExtension == "swift" {
                uses += try String(contentsOf: file, encoding: .utf8).split(whereSeparator: { $0.isNewline }).map(String.init).filter { $0.contains("\"/printers") }
            }
        }
        XCTAssertEqual(uses.count, 1)
        XCTAssertTrue(uses.first?.contains("call(\"/printers\")") ?? false)
    }
}
