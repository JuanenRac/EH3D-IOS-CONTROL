import XCTest
@testable import Eh3dCore

final class SessionVaultTests: XCTestCase {
    private let origin = "http://192.168.0.180:18200"

    private func make() -> (SessionVault, MemorySecrets) {
        let secrets = MemorySecrets()
        return (SessionVault(secrets: secrets, prefs: MemoryStore()), secrets)
    }

    func testKeepsTheTokenAndGivesItBack() {
        let (vault, _) = make()
        let now = Date(timeIntervalSince1970: 1_000)
        vault.saveSession(SessionCookie(name: "token", value: "abc123"), origin: origin, now: now)
        XCTAssertEqual(vault.loadSession(origin: origin, now: now.addingTimeInterval(10))?.value, "abc123")
    }

    func testTheTokenExpiresThirtyDaysAfterTheSignInAndIsDropped() {
        let (vault, secrets) = make()
        let now = Date(timeIntervalSince1970: 0)
        vault.saveSession(SessionCookie(name: "token", value: "abc123"), origin: origin, now: now)
        XCTAssertNotNil(vault.loadSession(origin: origin, now: now.addingTimeInterval(sessionTimeToLive - 1)))
        XCTAssertNil(vault.loadSession(origin: origin, now: now.addingTimeInterval(sessionTimeToLive)))
        XCTAssertTrue(secrets.items.isEmpty)
    }

    func testASessionKeptBeforeTheExpiryExistedIsDropped() {
        let (vault, secrets) = make()
        secrets.write("session_cookie", [origin, "token", "abc123"].joined(separator: "\u{1F}"), tiedToUnlock: false)
        XCTAssertNil(vault.loadSession(origin: origin, now: Date(timeIntervalSince1970: 5)))
        XCTAssertTrue(secrets.items.isEmpty)
    }

    func testTheUserAndThePasswordAnEarlierVersionKeptAreDeleted() {
        let (vault, secrets) = make()
        secrets.write("remembered_login", [origin, "ana", "secret pass"].joined(separator: "\u{1F}"), tiedToUnlock: false)
        XCTAssertTrue(vault.purgeLegacy())
        XCTAssertEqual(secrets.read("remembered_login"), .absent)
        XCTAssertFalse(vault.purgeLegacy())
    }

    func testATokenForAnotherServerIsNotGivenToThisOne() {
        let (vault, _) = make()
        let now = Date(timeIntervalSince1970: 0)
        vault.saveSession(SessionCookie(name: "token", value: "abc123"), origin: origin, now: now)
        XCTAssertNil(vault.loadSession(origin: "http://10.0.0.5:18200", now: now.addingTimeInterval(1)))
    }
}
