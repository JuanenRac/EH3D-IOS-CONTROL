import XCTest
@testable import Eh3dCore

/// The rules of the connection as plain logic: the settings and their ranges, the pauses and which requests may be sent again, when a login is renewed, the logins and the machines of the plugins that the server
/// lists, and the servers found on the local network. The same cases as the Android app.
final class ConnectionTests: XCTestCase {
    // ---- the settings

    func testTheSettingsStartAtTheDefaultsOfTheSuiteWithTheSearchOff() {
        let settings = ConnectionSettings()
        XCTAssertEqual(settings.timeoutS, 15)
        XCTAssertEqual(settings.retries, 2)
        XCTAssertFalse(settings.mdns)
        XCTAssertEqual([ConnectionSettings.keyTimeout, ConnectionSettings.keyRetries, ConnectionSettings.keyMdns], ["server_timeout_s", "server_retries", "server_mdns"])
    }

    func testAValueOutOfItsRangeIsBroughtToTheNearestEnd() {
        XCTAssertEqual(ConnectionSettings(timeoutS: 0).timeoutS, 1)
        XCTAssertEqual(ConnectionSettings(timeoutS: 500).timeoutS, 120)
        XCTAssertEqual(ConnectionSettings(retries: -3).retries, 0)
        XCTAssertEqual(ConnectionSettings(retries: 9).retries, 5)
        XCTAssertEqual(ConnectionSettings(timeoutS: 1, retries: 0).timeoutS, 1)
        XCTAssertEqual(ConnectionSettings(timeoutS: 120, retries: 5).retries, 5)
    }

    func testAChangeKeepsTheOtherValuesAndStaysInRange() {
        let base = ConnectionSettings(timeoutS: 30, retries: 3, mdns: true)
        XCTAssertEqual(base.withTimeout(200), ConnectionSettings(timeoutS: 120, retries: 3, mdns: true))
        XCTAssertEqual(base.withRetries(-1), ConnectionSettings(timeoutS: 30, retries: 0, mdns: true))
        XCTAssertEqual(base.withMdns(false), ConnectionSettings(timeoutS: 30, retries: 3, mdns: false))
    }

    func testTheSavedSettingsAreReadAndWhatIsNotSavedIsTheDefault() {
        let empty = ConnectionSettings.read(int: { _, fallback in fallback }, bool: { _, fallback in fallback })
        XCTAssertEqual(empty, ConnectionSettings())
        let saved = ConnectionSettings.read(int: { key, _ in key == "server_timeout_s" ? 999 : -4 }, bool: { _, _ in true })
        XCTAssertEqual(saved, ConnectionSettings(timeoutS: 120, retries: 0, mdns: true))
    }

    // ---- the tries again

    func testThePausesAre200And400And800AndSoOnUpToTwoSeconds() {
        XCTAssertEqual((0...6).map { RetryRules.delayMs($0) }, [200, 400, 800, 1600, 2000, 2000, 2000])
        XCTAssertEqual(RetryRules.delayMs(-5), 200)
    }

    func testARequestThatDoesNoHarmTwiceIsTriedAgainAfterATimeOutOrAGatewayFailure() {
        for method in ["GET", "HEAD", "PUT", "DELETE", "OPTIONS", "get"] {
            XCTAssertTrue(RetryRules.mayRepeat(method: method, status: 0, neverSent: false), method)
            for status in [502, 503, 504] { XCTAssertTrue(RetryRules.mayRepeat(method: method, status: status, neverSent: false), "\(method) \(status)") }
        }
    }

    func testAPostIsNeverTriedAgainExceptWhenNothingWentOut() {
        XCTAssertFalse(RetryRules.mayRepeat(method: "POST", status: 0, neverSent: false))
        for status in [502, 503, 504] { XCTAssertFalse(RetryRules.mayRepeat(method: "POST", status: status, neverSent: false)) }
        XCTAssertTrue(RetryRules.mayRepeat(method: "POST", status: 0, neverSent: true))
        XCTAssertTrue(RetryRules.mayRepeat(method: "PATCH", status: 0, neverSent: true))
    }

    func testAnAnswerThatIsNotAGatewayFailureIsFinal() {
        for status in [200, 400, 401, 403, 404, 409, 429, 500, 501] {
            XCTAssertFalse(RetryRules.mayRepeat(method: "GET", status: status, neverSent: false), "\(status)")
        }
    }

    // ---- the renewal

    func testALoginIsRenewedInTheLastQuarterOfItsLife() {
        XCTAssertFalse(RefreshRule.due(totalS: 1000, leftS: 751))
        XCTAssertTrue(RefreshRule.due(totalS: 1000, leftS: 250))
        XCTAssertTrue(RefreshRule.due(totalS: 1000, leftS: 1))
    }

    func testALoginOfUnknownLifeOrOneThatIsOverIsNotRenewedHere() {
        XCTAssertFalse(RefreshRule.due(totalS: 0, leftS: 10))
        XCTAssertFalse(RefreshRule.due(totalS: -5, leftS: 10))
        XCTAssertFalse(RefreshRule.due(totalS: 1000, leftS: 0))
        XCTAssertFalse(RefreshRule.due(totalS: 1000, leftS: -20))
    }

    // ---- the open logins

    func testTheLoginsOfTheAnswerAreRead() throws {
        let list = try parseSessions(#"{"sessions":[{"id":"s1","name":"ana","role":"admin","app":"ios","ip":"10.0.0.2","current":true},{"id":"s2","name":"ana"}]}"#)
        XCTAssertEqual(list, [
            AuthSession(id: "s1", name: "ana", role: "admin", app: "ios", ip: "10.0.0.2", current: true),
            AuthSession(id: "s2", name: "ana", role: "viewer", app: "", ip: "", current: false),
        ])
    }

    func testAnItemWithoutAnIdIsLeftOutAndAnythingThatIsNotAListIsEmpty() throws {
        XCTAssertEqual(try parseSessions(#"{"sessions":[{"name":"x"},{"id":""},"text",7,{"id":"ok"}]}"#).map { $0.id }, ["ok"])
        XCTAssertEqual(try parseSessions(#"{"sessions":"none"}"#), [])
        XCTAssertEqual(try parseSessions("{}"), [])
    }

    func testACurrentFlagIsABooleanOrTheWordTrueAndNothingElse() throws {
        XCTAssertEqual(try parseSessions(#"{"sessions":[{"id":"a","current":1},{"id":"b","current":"True"},{"id":"c","current":true},{"id":"d","current":"yes"}]}"#).map { $0.current }, [false, true, true, false])
    }

    func testAnAnswerThatIsNotJsonIsTheWrongServer() {
        XCTAssertThrowsError(try parseSessions("<html>router</html>")) { XCTAssertEqual(($0 as? ApiError)?.code, "bad_json") }
        XCTAssertThrowsError(try parseWorkMachines("[]")) { XCTAssertEqual(($0 as? ApiError)?.code, "bad_json") }
    }

    // ---- the machines of the plugins

    func testTheMachinesOfTheOtherPluginsAreReadAndTheBungardOnesAreLeftToTheFleet() throws {
        let list = try parseWorkMachines(#"{"machines":[{"id":"l1","name":"Laser","plugin":"laser","state":"busy"},{"id":"d1","plugin":"bungard","state":"idle"},{"name":"no id","plugin":"x"},{"id":"p1","plugin":"pnp"}]}"#)
        XCTAssertEqual(list.map { $0.id }, ["l1", "p1"])
        XCTAssertEqual(list[0].name, "Laser")
        XCTAssertEqual(list[0].state, "busy")
        XCTAssertEqual(list[1].name, "p1")
        XCTAssertEqual(list[1].state, "idle")
        XCTAssertEqual(list[1].detail, [])
        XCTAssertFalse(list[1].latched)
    }

    func testTheDetailIsFlattenedInOrderOfTheKeysWithNestedObjectsAsAPathAndListsBySize() throws {
        let list = try parseWorkMachines(#"{"machines":[{"id":"m","plugin":"laser","detail":{"z":1,"a":{"b":"x","c":{"d":2.5,"e":true}},"list":[1,2,3],"none":null,"text":"hi"}}]}"#)
        XCTAssertEqual(list[0].detail, [
            DetailLine("a.b", "x"), DetailLine("a.c.d", "2.5"), DetailLine("a.c.e", "true"), DetailLine("list", "[3]"), DetailLine("text", "hi"), DetailLine("z", "1"),
        ])
    }

    func testAnObjectDeeperThanTwoLevelsIsShownAsBraces() throws {
        let list = try parseWorkMachines(#"{"machines":[{"id":"m","plugin":"p","detail":{"a":{"b":{"c":{"d":1}}}}}]}"#)
        XCTAssertEqual(list[0].detail, [DetailLine("a.b.c", "{…}")])
    }

    func testNoMoreThan24LinesOfDetailAreKept() throws {
        let keys = (0..<40).map { "\"k\(String(format: "%02d", $0))\":\($0)" }.joined(separator: ",")
        let list = try parseWorkMachines("{\"machines\":[{\"id\":\"m\",\"plugin\":\"p\",\"detail\":{\(keys)}}]}")
        XCTAssertEqual(list[0].detail.count, 24)
        XCTAssertEqual(list[0].detail.first, DetailLine("k00", "0"))
    }

    func testAMachineIsLatchedByAnEmergencyStopOrAnAlarmOrTheLatchItself() throws {
        for key in ["latched", "estop_latched", "alarm"] {
            let list = try parseWorkMachines("{\"machines\":[{\"id\":\"m\",\"plugin\":\"p\",\"detail\":{\"\(key)\":true}}]}")
            XCTAssertTrue(list[0].latched, key)
        }
        let quiet = try parseWorkMachines(#"{"machines":[{"id":"m","plugin":"p","detail":{"latched":false,"alarm":0,"estop_latched":"no"}}]}"#)
        XCTAssertFalse(quiet[0].latched)
    }

    // ---- the search on the local network

    func testAServerFoundOnTheNetworkIsListedOnceAndNoMoreThanEight() {
        var found: [Candidate] = []
        found = addCandidate(found, host: "192.168.0.5", port: 18200)
        found = addCandidate(found, host: "192.168.0.5", port: 18200)
        XCTAssertEqual(found, [Candidate(host: "192.168.0.5", port: 18200)])
        XCTAssertEqual(found[0].label, "192.168.0.5:18200")
        for last in 6..<30 { found = addCandidate(found, host: "192.168.0.\(last)", port: 18200) }
        XCTAssertEqual(found.count, maxCandidates)
        XCTAssertEqual(maxCandidates, 8)
    }

    func testAnAnswerThatIsNotAHostAndAPortIsNotListed() {
        let start: [Candidate] = []
        XCTAssertEqual(addCandidate(start, host: nil, port: 18200), [])
        XCTAssertEqual(addCandidate(start, host: "  ", port: 18200), [])
        XCTAssertEqual(addCandidate(start, host: "a b", port: 18200), [])
        XCTAssertEqual(addCandidate(start, host: "host/path", port: 18200), [])
        XCTAssertEqual(addCandidate(start, host: "10.0.0.1", port: 0), [])
        XCTAssertEqual(addCandidate(start, host: "10.0.0.1", port: 70000), [])
        XCTAssertEqual(addCandidate(start, host: " eh3d.local. ", port: 1), [Candidate(host: "eh3d.local", port: 1)])
    }

    func testTheServiceTheServerAnnouncesIsTheEh3dTcpOne() {
        XCTAssertEqual(serviceType, "_eh3d._tcp")
    }
}
