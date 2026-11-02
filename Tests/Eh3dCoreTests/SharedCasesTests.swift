import XCTest
@testable import Eh3dCore

/// The cases that both phone apps read: the files of `Cases` are the same, byte for byte, in EH3D-ANDROID-CONTROL and EH3D-IOS-CONTROL, and each app has a test that walks them,
/// so the two cannot differ in what the summary says, how the link is judged, what a stop became, what is told when a machine changes, which addresses are safe or which fields are read.
final class SharedCasesTests: XCTestCase {
    private typealias Obj = [String: Any]

    private func text(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Cases").appendingPathComponent("\(name).json")
        return try String(contentsOf: url, encoding: .utf8)  // read from the folder of this file, like the examples of the server
    }

    private func any(_ name: String) throws -> Any { try JSONSerialization.jsonObject(with: Data(try text(name).utf8)) }
    private func array(_ name: String) throws -> [Obj] { try XCTUnwrap(try any(name) as? [Obj]) }
    private func object(_ name: String) throws -> Obj { try XCTUnwrap(try any(name) as? Obj) }
    private func strings(_ o: Obj, _ key: String) -> [String] { (o[key] as? [String]) ?? [] }
    private func string(_ o: Obj, _ key: String) -> String? { o[key] as? String }
    private func jsonText(_ value: Any) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self) }

    // ---- the summary before a job starts
    func testTheSummaryOfEveryCaseSaysWhatTheCaseExpects() throws {
        let cases = try array("summary_cases")
        XCTAssertGreaterThanOrEqual(cases.count, 5)
        for c in cases {
            let name = c["name"] as? String ?? ""
            let view = viewOf(try XCTUnwrap(c["view"] as? Obj))
            let s = startSummary(view)
            let e = try XCTUnwrap(c["expect"] as? Obj)
            XCTAssertEqual(s.count, e["count"] as? Int, name)
            XCTAssertEqual(s.tools, e["tools"] as? Int, name)
            if let size = e["size"] as? [Double] {
                let got = try XCTUnwrap(s.sizeMm, name)
                XCTAssertEqual(got[0], size[0], accuracy: 1e-9, name)
                XCTAssertEqual(got[1], size[1], accuracy: 1e-9, name)
            } else { XCTAssertNil(s.sizeMm, name) }
            if let seconds = e["seconds"] as? Double { XCTAssertEqual(try XCTUnwrap(s.seconds, name), seconds, accuracy: 1e-9, name) } else { XCTAssertNil(s.seconds, name) }
            XCTAssertEqual(s.outOfCourse, e["out_of_course"] as? Bool, name)
            XCTAssertEqual(s.reach.map { reachLine($0) }, e["reach"] as? String, name)
            let warnings = try XCTUnwrap(e["warnings"] as? [Obj])
            XCTAssertEqual(s.warnings.count, warnings.count, name)
            for (want, got) in zip(warnings, s.warnings) {
                XCTAssertEqual(got.code, want["code"] as? String, name)
                XCTAssertEqual(warningArgs(got), strings(want, "args"), name)
            }
        }
    }

    // ---- the link
    func testTheLinkIsJudgedAsEveryCaseSays() throws {
        let root = try object("link_cases")
        let p = try XCTUnwrap(root["policy"] as? Obj)
        let policy = LinkPolicy(offlineAfter: try XCTUnwrap(p["offline_after"] as? Int), staleAfterS: try XCTUnwrap(p["stale_after_s"] as? Int), retryMs: try XCTUnwrap(p["retry_ms"] as? [Int]))
        XCTAssertEqual(policy, LinkPolicy())   // the numbers of the cases are the numbers the app starts with
        for c in try XCTUnwrap(root["cases"] as? [Obj]) {
            var link = ServerLink()
            for step in try XCTUnwrap(c["steps"] as? [Obj]) {
                let t = Int64(try XCTUnwrap(step["t"] as? Int))
                switch step["event"] as? String {
                case "ok": link = link.succeeded(nowMs: t)
                case "unreachable": link = link.failed(.unreachable, nowMs: t)
                case "wrong_server": link = link.failed(.wrongServer, nowMs: t)
                default: XCTFail("event")
                }
                let where_ = "\(c["name"] as? String ?? "") at \(t)"
                let state: String
                switch link.state(policy) { case .connected: state = "connected"; case .stale: state = "stale"; case .offline: state = "offline"; case .wrongServer: state = "wrong_server" }
                XCTAssertEqual(state, step["state"] as? String, where_)
                XCTAssertEqual(link.failures, step["failures"] as? Int, where_)
                XCTAssertEqual(link.ageS(), (step["age_s"] as? Int).map { Int64($0) }, where_)
                XCTAssertEqual(policy.retryDelayMs(link.failures), step["retry_ms"] as? Int, where_)
            }
        }
    }

    func testAFailureIsToldAsTheLinkOrAsTheServerAnsweringAsItself() throws {
        for c in try array("failure_cases") {
            let want: LinkFailure? = (c["failure"] as? String) == "unreachable" ? .unreachable : (c["failure"] as? String) == "wrong_server" ? .wrongServer : nil
            XCTAssertEqual(classifyFailure(status: try XCTUnwrap(c["status"] as? Int), code: try XCTUnwrap(c["code"] as? String)), want, "\(c)")
        }
    }

    // ---- a stop
    private func machine(_ id: String, _ state: String, _ jobState: String?) -> Obj {
        var m: Obj = ["id": id, "name": "Machine \(id)", "model": "m", "station": "s", "connection": "node", "state": state, "ready": 0]
        if let jobState {
            m["job"] = ["id": "j-\(id)", "name": "job", "kind": "drill", "state": jobState, "by": "juan", "items_done": 1, "items_total": 4, "holes_done": 1, "holes_total": 4, "percent": 25, "estimate_s": 10.0] as Obj
        } else { m["job"] = NSNull() }
        return m
    }

    func testAStopBecomesSentThenConfirmedOrStillWorkingAsEveryCaseSays() throws {
        let root = try object("stop_cases")
        let keep = Int64(try XCTUnwrap(root["keep_ms"] as? Int)), grace = Int64(try XCTUnwrap(root["grace_ms"] as? Int))
        for c in try XCTUnwrap(root["cases"] as? [Obj]) {
            let stop = try XCTUnwrap(c["stop"] as? Obj)
            var notes = [StopNote(machineId: try XCTUnwrap(stop["machine"] as? String), machineName: try XCTUnwrap(stop["name"] as? String), atMs: Int64(try XCTUnwrap(stop["at"] as? Int)))]
            for look in try XCTUnwrap(c["looks"] as? [Obj]) {
                let kind = look["machine"] as? String ?? ""
                let machines: [Obj] = kind == "missing" ? [] : kind == "busy" ? [machine("m1", "busy", "running")] : [machine("m1", "idle", nil)]
                let fleet = try parseFleet(try jsonText(["machines": machines]))
                let now = Int64(try XCTUnwrap(look["now"] as? Int))
                notes = followStops(notes, fleet: fleet, askedMs: Int64(try XCTUnwrap(look["asked"] as? Int)), nowMs: now, keepMs: keep, graceMs: grace)
                let got: String
                switch notes.first?.outcome { case nil: got = "gone"; case .sent?: got = "sent"; case .confirmed?: got = "confirmed"; case .stillWorking?: got = "still_working" }
                XCTAssertEqual(got, look["expect"] as? String, "\(c["name"] as? String ?? "") at \(now)")
            }
        }
    }

    // ---- what is told when a machine changes
    func testAChangeInTheFleetTellsWhatEveryCaseSays() throws {
        for c in try array("transition_cases") {
            let before = try XCTUnwrap(c["before"] as? [String: String])
            let fleet = try parseFleet(try jsonText(["machines": try XCTUnwrap(c["machines"] as? [Obj])]))
            let got = fleetNotices(before: before, now: fleet).map { "\($0.machineId):\($0.kind == .waiting ? "waiting" : "ended")" }
            let want = try XCTUnwrap(c["expect"] as? [Obj]).map { "\($0["machine"] as? String ?? ""):\($0["kind"] as? String ?? "")" }
            XCTAssertEqual(got, want, c["name"] as? String ?? "")
        }
    }

    // ---- the address of the server
    func testTheAddressesAreJudgedAsEveryCaseSays() throws {
        let root = try object("endpoint_cases")
        for c in try XCTUnwrap(root["from_host_and_port"] as? [Obj]) {
            XCTAssertEqual(ServerEndpoint.fromHostAndPort(c["host"] as? String ?? "", c["port"] as? String ?? "")?.origin, c["origin"] as? String, "\(c)")
        }
        for c in try XCTUnwrap(root["parse"] as? [Obj]) { XCTAssertEqual(ServerEndpoint.parse(c["value"] as? String ?? "")?.origin, c["origin"] as? String, "\(c)") }
        for c in try XCTUnwrap(root["private_lan"] as? [Obj]) { XCTAssertEqual(ServerEndpoint.isPrivateLanHost(c["host"] as? String ?? ""), c["private"] as? Bool, "\(c)") }
        for c in try XCTUnwrap(root["needs_secure"] as? [Obj]) { XCTAssertEqual(ServerEndpoint.needsSecureConnection(c["host"] as? String ?? ""), c["value"] as? Bool, "\(c)") }
        for c in try XCTUnwrap(root["public_ip"] as? [Obj]) { XCTAssertEqual(ServerEndpoint.usesPublicIpAddress(c["host"] as? String ?? ""), c["value"] as? Bool, "\(c)") }
    }

    // ---- the fields of the answers
    private func keys(of value: Any, into out: inout Set<String>) {
        if let o = value as? Obj { for (k, v) in o { out.insert(k); keys(of: v, into: &out) } }
        else if let a = value as? [Any] { for v in a { keys(of: v, into: &out) } }
    }

    /// A field that an example of the server carries and that the app neither reads nor says it ignores fails here; so does a field the app says it reads and whose name is nowhere in its code.
    func testEveryFieldOfTheExamplesIsReadOrSaidToBeIgnoredAndTheReadOnesAreInTheCode() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources")
        var code = ""
        for case let file as URL in FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)! where file.pathExtension == "swift" { code += try String(contentsOf: file, encoding: .utf8) + "\n" }
        let examples = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Examples")
        for g in try XCTUnwrap(try object("api_fields")["groups"] as? [Obj]) {
            let read = Set(strings(g, "read")), ignored = Set(strings(g, "ignored"))
            if let example = g["example"] as? String {
                let raw = try Data(contentsOf: examples.appendingPathComponent("\(example).json"))
                var found = Set<String>()
                keys(of: try JSONSerialization.jsonObject(with: raw), into: &found)
                XCTAssertEqual(found.subtracting(read).subtracting(ignored), [], "\(example): fields that the app neither reads nor ignores")
            }
            for field in read { XCTAssertTrue(code.contains("\"\(field)\""), "the code never reads \"\(field)\"") }
        }
    }
}
