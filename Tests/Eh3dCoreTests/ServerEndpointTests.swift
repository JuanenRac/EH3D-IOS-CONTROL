import XCTest
@testable import Eh3dCore

/// The rules for the address of the server, the same cases as the Android app: TLS or a private LAN only, no secret in the address, and a name that only looks private is not.
final class ServerEndpointTests: XCTestCase {
    func testAcceptsTlsAndPrivateLanOriginsOnly() {
        XCTAssertEqual(ServerEndpoint.parse("https://eh3d.example:8443")?.origin, "https://eh3d.example:8443")
        XCTAssertEqual(ServerEndpoint.parse("http://192.168.0.80:8080")?.origin, "http://192.168.0.80:8080")
        XCTAssertNil(ServerEndpoint.parse("http://example.com:8080"))
        XCTAssertNil(ServerEndpoint.parse("https://token@example.com"))
    }

    func testBuildsOnlyPrivateLanHostAndPortEntries() {
        XCTAssertEqual(ServerEndpoint.fromHostAndPort("192.168.0.80", "8080")?.origin, "http://192.168.0.80:8080")
        XCTAssertEqual(ServerEndpoint.fromHostAndPort("https://eh3d.example", "8443")?.origin, "https://eh3d.example:8443")
        XCTAssertNil(ServerEndpoint.fromHostAndPort("example.com", "8080"))
        XCTAssertNil(ServerEndpoint.fromHostAndPort("192.168.0.80", "70000"))
        XCTAssertNil(ServerEndpoint.fromHostAndPort("192.168.0.80", "0"))
        XCTAssertNil(ServerEndpoint.fromHostAndPort("192.168.0.80", "abc"))
        XCTAssertNil(ServerEndpoint.fromHostAndPort("192.168.0.80", ""))
    }

    /// A host name that merely starts like a private address must never receive a password in clear text.
    func testAHostNameThatLooksPrivateIsNotPrivate() {
        for host in ["10.attacker.example", "192.168.evil.com", "172.16.0.1.example.com", "10.0.0.1.nip.io", "127.0.0.1.evil.net"] {
            XCTAssertNil(ServerEndpoint.parse("http://\(host):8080"), host)
        }
    }

    func testRecognisesEveryPrivateRangeAndNothingElse() {
        for host in ["10.0.0.1", "10.255.255.255", "172.16.0.1", "172.31.255.255", "192.168.0.180", "127.0.0.1", "127.1.2.3", "localhost"] {
            XCTAssertTrue(ServerEndpoint.isPrivateLanHost(host), host)
        }
        for host in ["172.15.0.1", "172.32.0.1", "192.169.0.1", "11.0.0.1", "8.8.8.8", "256.1.1.1", "1.2.3", "1.2.3.4.5", "", "eh3d.local", "1.2.3.4x"] {
            XCTAssertFalse(ServerEndpoint.isPrivateLanHost(host), host)
        }
    }

    /// Some resolvers read a leading zero as octal: "010.0.0.1" is then the public address 8.0.0.1.
    func testRefusesAddressesWithLeadingZeros() {
        for host in ["010.0.0.1", "10.00.0.1", "192.168.000.5", "0177.0.0.1"] {
            XCTAssertFalse(ServerEndpoint.isPrivateLanHost(host), host)
        }
        XCTAssertNil(ServerEndpoint.octets("010.0.0.1"))
        XCTAssertEqual(ServerEndpoint.octets("0.0.0.0") ?? [], [0, 0, 0, 0])
    }

    func testTheFourNumbersOfAnAddressMustBeWholeNumbersFromZeroTo255() {
        XCTAssertEqual(ServerEndpoint.octets("192.168.0.180") ?? [], [192, 168, 0, 180])
        XCTAssertEqual(ServerEndpoint.octets("255.255.255.255") ?? [], [255, 255, 255, 255])
        for bad in ["256.0.0.1", "1.2.3", "1.2.3.4.5", "1..3.4", "a.b.c.d", "1.2.3.-4", "1.2.3.1000", " 1.2.3.4", "1.2.3.4 ", ""] {
            XCTAssertNil(ServerEndpoint.octets(bad), bad)
        }
    }

    func testRejectsQueriesFragmentsAndOtherSchemes() {
        XCTAssertNil(ServerEndpoint.parse("http://192.168.0.5:8080?x=1"))
        XCTAssertNil(ServerEndpoint.parse("http://192.168.0.5:8080#frag"))
        XCTAssertNil(ServerEndpoint.parse("ftp://192.168.0.5"))
        XCTAssertNil(ServerEndpoint.parse("not a url"))
        XCTAssertNil(ServerEndpoint.parse(""))
    }

    /// An address of the house is stable; a public one lasts until the operator changes it, so the sign-in suggests a name.
    func testAPublicIpAddressIsToldFromANameAndFromTheHouse() {
        XCTAssertTrue(ServerEndpoint.usesPublicIpAddress("203.0.113.9"))
        XCTAssertTrue(ServerEndpoint.usesPublicIpAddress("https://203.0.113.9:8443/"))
        XCTAssertFalse(ServerEndpoint.usesPublicIpAddress("192.168.0.180"))
        XCTAssertFalse(ServerEndpoint.usesPublicIpAddress("http://10.0.0.5"))
        XCTAssertFalse(ServerEndpoint.usesPublicIpAddress("casa.duckdns.org"))
        XCTAssertFalse(ServerEndpoint.usesPublicIpAddress("https://casa.duckdns.org"))
        XCTAssertFalse(ServerEndpoint.usesPublicIpAddress("999.1.1.1"))
        XCTAssertFalse(ServerEndpoint.usesPublicIpAddress("  "))
    }

    func testAnAddressOutsideTheHouseWithoutTlsNeedsASecureConnectionAndTheRestDoesNot() {
        XCTAssertTrue(ServerEndpoint.needsSecureConnection("example.com"))
        XCTAssertTrue(ServerEndpoint.needsSecureConnection("http://example.com:8080"))
        XCTAssertTrue(ServerEndpoint.needsSecureConnection("203.0.113.9"))
        XCTAssertTrue(ServerEndpoint.needsSecureConnection("10.attacker.example"))
        XCTAssertFalse(ServerEndpoint.needsSecureConnection("https://example.com"))
        XCTAssertFalse(ServerEndpoint.needsSecureConnection("HTTPS://example.com"))
        XCTAssertFalse(ServerEndpoint.needsSecureConnection("192.168.0.5"))
        XCTAssertFalse(ServerEndpoint.needsSecureConnection("localhost"))
        XCTAssertFalse(ServerEndpoint.needsSecureConnection(""))
        XCTAssertFalse(ServerEndpoint.needsSecureConnection("   "))
    }

    func testNormalisesTheOriginItKeeps() {
        XCTAssertEqual(ServerEndpoint.parse("  http://192.168.0.5:18080/  ")?.origin, "http://192.168.0.5:18080")
        XCTAssertEqual(ServerEndpoint.parse("https://eh3d.example")?.origin, "https://eh3d.example")
    }

    func testThePortRangeIsFromOneToSixtyFiveThousandFiveHundredAndThirtyFive() {
        for port in ["1", "80", "65535", " 8080 "] {
            XCTAssertNotNil(ServerEndpoint.fromHostAndPort("192.168.0.5", port), port)
        }
        for port in ["0", "-1", "65536", "1e3", "8 0"] {
            XCTAssertNil(ServerEndpoint.fromHostAndPort("192.168.0.5", port), port)
        }
    }

    func testAHostTypedWithAPathOrAPortInItKeepsOnlyTheHost() {
        XCTAssertEqual(ServerEndpoint.fromHostAndPort("http://192.168.0.5:9999/some/path", "8080")?.origin, "http://192.168.0.5:8080")
        XCTAssertEqual(ServerEndpoint.fromHostAndPort("192.168.0.5/", "8080")?.origin, "http://192.168.0.5:8080")
    }
}
