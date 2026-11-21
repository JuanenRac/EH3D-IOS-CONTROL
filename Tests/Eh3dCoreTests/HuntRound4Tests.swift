import XCTest
@testable import Eh3dCore

/// Bug hunt: the address that is typed, the tools of a file with a damaged header, names that are cut and the requests of the files, with the same cases as the Android app.
final class HuntRound4Tests: XCTestCase {
    private func origin(_ host: String, _ port: String) -> String? { ServerEndpoint.fromHostAndPort(host, port)?.origin }

    private func object(_ text: String) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]) }

    // ---- the address of the server

    func testTheSchemeIsReadWhateverItsCase() {
        XCTAssertEqual(origin("HTTP://192.168.0.80", "8080"), "http://192.168.0.80:8080")
        XCTAssertEqual(origin("Http://10.0.0.5", "80"), "http://10.0.0.5:80")
        XCTAssertEqual(origin("HTTPS://eh3d.example", "8443"), "https://eh3d.example:8443")
        XCTAssertEqual(origin("hTtPs://eh3d.example", "8443"), "https://eh3d.example:8443")
    }

    func testAPortIsPlainDigitsFromOneToSixtyFiveThousandFiveHundredAndThirtyFive() {
        for port in ["", " ", "+80", "-1", "0", "65536", "\u{FF18}\u{FF10}\u{FF18}\u{FF10}", "80 80", "8e3", "0x50", "99999999999999999999", "\u{0668}\u{0660}", "80.0", "08x"] {
            XCTAssertNil(origin("192.168.0.80", port), port)
        }
        XCTAssertEqual(origin("192.168.0.80", "1"), "http://192.168.0.80:1")
        XCTAssertEqual(origin("192.168.0.80", "65535"), "http://192.168.0.80:65535")
        XCTAssertEqual(origin("192.168.0.80", " 8080 "), "http://192.168.0.80:8080")
        XCTAssertEqual(origin("192.168.0.80", "0080"), "http://192.168.0.80:80")
    }

    func testANameOrAPasswordBeforeTheHostIsRefusedWhicheverWayItIsTyped() {
        XCTAssertNil(origin("192.168.0.80@evil.example", "8080"))
        XCTAssertNil(origin("user:pw@192.168.0.80", "8080"))
        XCTAssertNil(ServerEndpoint.parse("http://user@192.168.0.5"))
        XCTAssertNil(ServerEndpoint.parse("https://a:b@example.com"))
        XCTAssertNil(ServerEndpoint.parse("http://192.168.0.5@evil.example"))
    }

    func testAPathAfterTheHostIsNotPartOfAnOriginAndTheSlashIs() {
        XCTAssertNil(ServerEndpoint.parse("http://192.168.0.5:8080/api"))
        XCTAssertNil(ServerEndpoint.parse("https://eh3d.example/a/b"))
        XCTAssertEqual(ServerEndpoint.parse("http://192.168.0.5:8080/")?.origin, "http://192.168.0.5:8080")
        XCTAssertEqual(ServerEndpoint.parse("http://192.168.0.5:8080")?.origin, "http://192.168.0.5:8080")
    }

    func testThePortOfAnAddressIsRealOrNone() {
        XCTAssertNil(ServerEndpoint.parse("http://192.168.0.5:0"))
        XCTAssertNil(ServerEndpoint.parse("http://192.168.0.5:65536"))
        XCTAssertEqual(ServerEndpoint.parse("http://192.168.0.5:65535")?.origin, "http://192.168.0.5:65535")
        XCTAssertEqual(ServerEndpoint.parse("http://192.168.0.5:1")?.origin, "http://192.168.0.5:1")
    }

    func testSpacesAndLineBreaksAroundAnAddressAreLeftOut() {
        XCTAssertEqual(ServerEndpoint.parse("\thttp://192.168.0.5:8080\n")?.origin, "http://192.168.0.5:8080")
        XCTAssertEqual(origin("192.168.0.80\n", "8080"), "http://192.168.0.80:8080")
        XCTAssertEqual(ServerEndpoint.parse("  https://eh3d.example \r\n")?.origin, "https://eh3d.example")
    }

    func testAnAddressOfTheVersionSixIsKeptBetweenBracketsOrRefusedWhenItIsPlain() {
        XCTAssertEqual(ServerEndpoint.parse("https://[fe80::1]:8443")?.origin, "https://[fe80::1]:8443")
        XCTAssertNil(ServerEndpoint.parse("http://[::1]:8080"))
    }

    func testAnAddressWithADotAtTheEndIsNotPrivate() {
        XCTAssertNil(ServerEndpoint.parse("http://192.168.0.5.:8080"))
        XCTAssertFalse(ServerEndpoint.isPrivateLanHost("192.168.0.5."))
        XCTAssertFalse(ServerEndpoint.isPrivateLanHost("localhost."))
    }

    func testEveryOriginIsItsOwnFixedPoint() throws {
        for value in ["http://192.168.0.5:8080", "https://eh3d.example:8443", "https://eh3d.example", "http://localhost:18080", "https://[fe80::1]:8443"] {
            let once = try XCTUnwrap(ServerEndpoint.parse(value), value)
            XCTAssertEqual(once.origin, value)
            XCTAssertEqual(ServerEndpoint.parse(once.origin)?.origin, value)
        }
    }

    func testTheHousePrivateRangesAreExactAtTheirEdges() {
        for host in ["172.16.0.0", "172.31.255.255", "10.0.0.0", "192.168.255.255", "127.255.255.255"] { XCTAssertTrue(ServerEndpoint.isPrivateLanHost(host), host) }
        for host in ["172.15.255.255", "172.32.0.0", "192.167.255.255", "192.169.0.0", "11.0.0.0", "9.255.255.255", "0.0.0.0", "255.255.255.255", " 10.0.0.1", "10.0.0.1\n", "\u{FF11}\u{FF10}.0.0.1"] { XCTAssertFalse(ServerEndpoint.isPrivateLanHost(host), host) }
    }

    func testTheNumbersOfAnAddressAreFourPlainWholeNumbersWithoutLeadingZeros() {
        XCTAssertEqual(ServerEndpoint.octets("10.0.0.1"), [10, 0, 0, 1])
        XCTAssertEqual(ServerEndpoint.octets("255.255.255.255"), [255, 255, 255, 255])
        for host in ["", "1.2.3", "1.2.3.4.5", "256.1.1.1", "01.2.3.4", "1.2.3.", ".1.2.3", "1..2.3", "a.b.c.d", "1.2.3.4x", "-1.2.3.4", "1.2.3.\u{0664}"] { XCTAssertNil(ServerEndpoint.octets(host), host) }
    }

    func testTheSecureConnectionIsAskedForAnythingThatIsNotTheHouseWhateverTheScheme() {
        XCTAssertFalse(ServerEndpoint.needsSecureConnection("HTTP://192.168.0.5"))
        XCTAssertFalse(ServerEndpoint.needsSecureConnection("HTTPS://example.com"))
        XCTAssertTrue(ServerEndpoint.needsSecureConnection("HTTP://example.com"))
        XCTAssertTrue(ServerEndpoint.needsSecureConnection("192.168.0.5@evil.example"))
        XCTAssertTrue(ServerEndpoint.needsSecureConnection("10.attacker.example"))
        XCTAssertFalse(ServerEndpoint.needsSecureConnection("localhost"))
        XCTAssertFalse(ServerEndpoint.needsSecureConnection(""))
        XCTAssertFalse(ServerEndpoint.needsSecureConnection("   "))
        XCTAssertFalse(ServerEndpoint.needsSecureConnection("\n192.168.0.5\n"))
    }

    func testAPublicIpAddressIsToldFromANameWhateverTheScheme() {
        XCTAssertTrue(ServerEndpoint.usesPublicIpAddress("HTTP://203.0.113.9"))
        XCTAssertTrue(ServerEndpoint.usesPublicIpAddress("HTTPS://203.0.113.9:8443/"))
        XCTAssertFalse(ServerEndpoint.usesPublicIpAddress("203.0.113.9@evil.example"))
        XCTAssertFalse(ServerEndpoint.usesPublicIpAddress("203.000.113.9"))
        XCTAssertFalse(ServerEndpoint.usesPublicIpAddress("256.1.1.1"))
        XCTAssertFalse(ServerEndpoint.usesPublicIpAddress("10.0.0.1"))
        XCTAssertFalse(ServerEndpoint.usesPublicIpAddress(""))
    }

    func testTheAddressToUseFollowsThePlaceAndFallsBackToTheOnlyOne() throws {
        let home = try XCTUnwrap(ServerEndpoint.parse("http://192.168.0.5:8080"))
        let away = try XCTUnwrap(ServerEndpoint.parse("https://eh3d.example"))
        let both = DualEndpoint(home: home, away: away)
        XCTAssertEqual(both.chosen(for: .home), home)
        XCTAssertEqual(both.chosen(for: .away), away)
        XCTAssertEqual(both.chosen(for: .unknown), home)
        XCTAssertEqual(DualEndpoint(home: nil, away: away).chosen(for: .home), away)
        XCTAssertEqual(DualEndpoint(home: home, away: nil).chosen(for: .away), home)
        XCTAssertNil(DualEndpoint(home: nil, away: nil).chosen(for: .unknown))
    }

    func testTheOtherAddressIsOfferedOnlyWhenThereIsAnotherOne() throws {
        let home = try XCTUnwrap(ServerEndpoint.parse("http://192.168.0.5:8080"))
        let away = try XCTUnwrap(ServerEndpoint.parse("https://eh3d.example"))
        let stranger = try XCTUnwrap(ServerEndpoint.parse("https://other.example"))
        XCTAssertEqual(DualEndpoint(home: home, away: away).alternative(to: home), away)
        XCTAssertEqual(DualEndpoint(home: home, away: away).alternative(to: away), home)
        XCTAssertNil(DualEndpoint(home: home, away: away).alternative(to: stranger))
        XCTAssertNil(DualEndpoint(home: home, away: home).alternative(to: home))
        XCTAssertNil(DualEndpoint(home: home, away: nil).alternative(to: home))
    }

    // ---- preparing a job

    func testTheDiametersOfTheHeaderAreReadAndTheFirstOneOfAToolWins() {
        let d = Prepare.declaredDiameters("M48\nT01C0.80\nT02C1.00\nT01C9.9\n  T3 C.5\nT4C\n%\n")
        XCTAssertEqual(d, [1: 0.8, 2: 1.0, 3: 0.5])
        XCTAssertEqual(Array(Prepare.declaredDiameters("T0001C0.8").keys), [1])
    }

    func testAToolNumberTooBigForThirtyTwoBitsIsSkippedAndNeverEndsInAnException() {
        let d = Prepare.declaredDiameters("T99999999999C0.8\nT2147483648C0.3\nT1C0.5\nT2147483647C0.7\n")
        XCTAssertEqual(d, [1: 0.5, 2147483647: 0.7])
        XCTAssertTrue(Prepare.declaredDiameters("T" + String(repeating: "9", count: 5000) + "C1").isEmpty)
    }

    func testDigitsOfOtherScriptsAreNotAToolOrADiameter() {
        XCTAssertTrue(Prepare.declaredDiameters("T\u{0661}C0.8\nT1C\u{0660}.8\n").isEmpty)
    }

    func testOnlyTheFirstTwentyThousandCharactersOfTheFileAreLookedAt() {
        let padding = String(repeating: "; ", count: 10_000)
        XCTAssertTrue(Prepare.declaredDiameters(padding + "\nT1C0.8\n").isEmpty)
        XCTAssertEqual(Prepare.declaredDiameters("T1C0.8\n" + padding).count, 1)
        XCTAssertTrue(Prepare.declaredDiameters("").isEmpty)
    }

    func testTheNameOfAJobIsCutBetweenCharactersAndNeverInsideAPicture() {
        let name = Prepare.jobName(String(repeating: "\u{1F600}", count: 61) + ".ncd")
        XCTAssertEqual(name.count, 60)
        XCTAssertEqual(name, String(repeating: "\u{1F600}", count: 60))
        XCTAssertEqual(Prepare.jobName(String(repeating: "a", count: 80) + ".ncd"), String(repeating: "a", count: 60))
        XCTAssertEqual(Prepare.jobName(String(repeating: "a", count: 60) + ".ncd"), String(repeating: "a", count: 60))
    }

    func testTheNameOfAJobIsTheFileWithoutItsLastExtension() {
        XCTAssertEqual(Prepare.jobName("a.b.c"), "a.b")
        XCTAssertEqual(Prepare.jobName("noext"), "noext")
        XCTAssertEqual(Prepare.jobName(""), "")
    }

    func testTheLinesOfAProgramAreCountedTheWayTheServerNumbersThem() {
        let cases: [(String, Int)] = [("", 0), ("a", 1), ("a\n", 1), ("a\n\n", 2), ("a\r\nb\r\n", 2), ("\n", 1), ("\r\n", 1), ("a\nb", 2)]
        for (text, lines) in cases { XCTAssertEqual(Prepare.lineCount(text), lines, text.debugDescription) }
    }

    func testTheLineToGoOnFromStaysInsideTheProgram() {
        XCTAssertEqual(Prepare.resumeSkip(line: -5, total: 10), 0)
        XCTAssertEqual(Prepare.resumeSkip(line: 99, total: 10), 10)
        XCTAssertEqual(Prepare.resumeSkip(line: 4, total: 10), 4)
        XCTAssertEqual(Prepare.resumeSkip(line: 5, total: -3), 0)
        XCTAssertEqual(Prepare.resumeSkip(line: Int.max, total: 0), 0)
        XCTAssertEqual(Prepare.resumeSkip(line: Int.max, total: 7), 7)
        XCTAssertEqual(Prepare.resumeSkip(line: Int.min, total: 7), 0)
    }

    func testTheToolsToLeaveOutAreTheSwitchedOffOnesAndTheOnesBeforeTheStart() {
        XCTAssertEqual(Prepare.skipTools(order: [1, 2, 3], off: [2], startAt: 3), [1, 2])
        XCTAssertEqual(Prepare.skipTools(order: [1, 2, 3], off: [2], startAt: 9), [2])
        XCTAssertEqual(Prepare.skipTools(order: [1], off: [9, 5], startAt: nil), [5, 9])
        XCTAssertEqual(Prepare.skipTools(order: [], off: [], startAt: 4), [])
        XCTAssertEqual(Prepare.skipTools(order: [3, 1], off: [], startAt: 1), [3])
    }

    func testNothingIsLeftOnlyWhenAFileHasToolsAndEveryOneIsOut() {
        XCTAssertFalse(Prepare.nothingLeft(order: [], skipped: []))
        XCTAssertFalse(Prepare.nothingLeft(order: [], skipped: [1]))
        XCTAssertTrue(Prepare.nothingLeft(order: [1, 2], skipped: [1, 2]))
        XCTAssertTrue(Prepare.nothingLeft(order: [1, 2], skipped: [2, 1, 7]))
        XCTAssertFalse(Prepare.nothingLeft(order: [1, 2], skipped: [1]))
    }

    func testTheToggleOfTheStartAndOfASwitchedOffToolFollowTheirRules() {
        XCTAssertEqual(Prepare.toggleStartAt(current: nil, tool: 3, off: []), 3)
        XCTAssertNil(Prepare.toggleStartAt(current: 3, tool: 3, off: []))
        XCTAssertEqual(Prepare.toggleStartAt(current: 2, tool: 3, off: [3]), 2)
        XCTAssertNil(Prepare.toggleStartAt(current: nil, tool: 3, off: [3]))
        XCTAssertEqual(Prepare.toggleOff([1], tool: 1), [])
        XCTAssertEqual(Prepare.toggleOff([1], tool: 2), [1, 2])
    }

    func testAMachineTakesTheWorkItsConnectionCanDo() {
        XCTAssertEqual(Prepare.works("grbl"), [.gcode])
        XCTAssertEqual(Prepare.works("node"), [.drill, .route, .both])
        for connection in ["demo", "", "unknown", "NODE"] { XCTAssertEqual(Prepare.works(connection), Work.allCases, connection) }
    }

    func testTheRequestOfAFileHoldsTheTextExactlyWhateverIsInIt() throws {
        let text = "M48\r\n\"quoted\" \\ back\0slash \u{00E9}\u{65E5}\u{1F600}\n"
        let body = try object(Prepare.fileBody(side: .drill, name: "board", text: text, tableText: "   ", skipTools: []))
        XCTAssertEqual(body["kind"] as? String, "drill")
        let files = try XCTUnwrap(body["files"] as? [String: Any])
        XCTAssertEqual(files["ncd"] as? String, text)
        XCTAssertNil(files["dtd"])
        XCTAssertNil(body["skip_tools"])
        XCTAssertEqual(body["name"] as? String, "board")
    }

    func testTheRequestOfARoutingFileUsesItsOwnNamesAndLeavesOutABlankName() throws {
        let body = try object(Prepare.fileBody(side: .route, name: " \n ", text: "IN;", tableText: "table", skipTools: [2, 5]))
        XCTAssertEqual(body["kind"] as? String, "route")
        let files = try XCTUnwrap(body["files"] as? [String: Any])
        XCTAssertEqual(files["plt"] as? String, "IN;")
        XCTAssertEqual(files["rtd"] as? String, "table")
        XCTAssertNil(body["name"])
        XCTAssertEqual((body["skip_tools"] as? [Int]) ?? [], [2, 5])
    }

    func testTheRequestOfAProgramNeverHasANegativeSkipOrABlankName() throws {
        let body = try object(Prepare.gcodeBody(name: "\n", gcode: "G0 X1\n", skip: -7, restoreOutputs: true))
        XCTAssertEqual(body["skip"] as? Int, 0)
        XCTAssertEqual(body["restore_outputs"] as? Bool, true)
        XCTAssertNil(body["name"])
        XCTAssertEqual(body["gcode"] as? String, "G0 X1\n")
        let plain = try object(Prepare.gcodeBody(name: "n", gcode: "", skip: 5, restoreOutputs: false))
        XCTAssertEqual(plain["skip"] as? Int, 5)
        XCTAssertEqual(plain["restore_outputs"] as? Bool, false)
        XCTAssertEqual(plain["name"] as? String, "n")
    }
}
