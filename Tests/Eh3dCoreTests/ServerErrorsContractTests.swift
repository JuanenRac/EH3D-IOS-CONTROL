import XCTest
@testable import Eh3dCore

/// The table of refusal texts against the catalog of the server: every code of docs/error-codes.json of EH3D-SERVER has its text in the eight languages of the suite, and the table has no code that the server
/// no longer has. The checks that need the server repository next to this one are skipped when it is not there (a clone of this repository alone); the ones that do not need it look at the table and at the
/// codes that the server added after the copy of the catalog that the other tests keep. The same cases as the Android app (ServerErrorsContractTest).
final class ServerErrorsContractTests: XCTestCase {
    private let here = URL(fileURLWithPath: #filePath)
    private var repository: URL { here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private var tableFile: URL { repository.appendingPathComponent("Sources/Eh3dCore/Resources/server-errors.json") }
    private var serverCatalog: URL { repository.deletingLastPathComponent().appendingPathComponent("EH3D-SERVER/docs/error-codes.json") }
    private var keptCatalog: URL { here.deletingLastPathComponent().appendingPathComponent("Catalog/error-codes.json") }

    /// The codes that the server added after the first copy of the catalog (the copy in Tests/Eh3dCoreTests/Catalog has them all now): the phone has to tell every one of them.
    private let addedLater: [String] = [
        "air_assist_off", "bad_axis", "bad_feed", "bad_gerber", "bad_heater", "bad_mesh", "bad_operation", "bad_placement_list", "bad_rules", "compat_off", "compat_write_off", "enclosure_open",
        "farm_no_free_printer", "focus_not_checked", "heater_timeout", "input_too_large", "jog_while_running", "laser_estop_latched", "laser_feed_limit", "laser_power_limit", "machine_alarm",
        "missing_layer", "out_of_travel", "pnp_feeder_short", "printer_disconnected", "printer_latched", "printer_untrusted", "program_over_limit", "sensor_fault", "slice_failed", "slice_limit",
        "slice_off", "temperature_over_limit", "test_fire_refused", "thermal_runaway", "unit_unknown",
        "authorization_required", "bad_bgcode", "bad_pnp_node", "bambu_lan_off", "bgcode_unsupported", "pnp_node_disabled", "pnp_node_exists", "pnp_node_not_ready", "pnp_nodes_full", "pnp_nodes_off",
        "stale_authorization", "unknown_pnp_node",
        "bad_printer", "printer_exists", "printers_full", "printers_off", "unknown_printer",
    ]

    override func setUpWithError() throws {
        try super.setUpWithError()
        try ServerErrors.install(String(contentsOf: tableFile, encoding: .utf8))
    }

    private func codes(of file: URL) throws -> [String] {
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]])
        return rows.compactMap { $0["code"] as? String }
    }

    func testEveryCodeOfTheServerHasATextInEachOfTheEightLanguages() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: serverCatalog.path), "the sibling folder EH3D-SERVER is not there")
        let without = try codes(of: serverCatalog).filter { code in ServerErrors.languages.contains { ServerErrors.text(code, language: $0) == nil } }
        XCTAssertEqual(without, [], "a code of the server without its eight texts: run py -3 -I tools/gen_server_errors.py")
    }

    func testTheTableHasNoCodeThatTheServerNoLongerHas() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: serverCatalog.path), "the sibling folder EH3D-SERVER is not there")
        let server = Set(try codes(of: serverCatalog))
        XCTAssertEqual(ServerErrors.codes().subtracting(server).sorted(), [])
    }

    func testTheCodesAddedAfterTheCopyOfTheCatalogHaveTheirEightTexts() {
        let without = addedLater.filter { code in ServerErrors.languages.contains { ServerErrors.text(code, language: $0) == nil } }
        XCTAssertEqual(without, [])
        XCTAssertEqual(addedLater.count, 53)
        XCTAssertEqual(addedLater.count, Set(addedLater).count)
    }

    func testTheTableHasARowForEveryCodeOfTheCatalogThatTheTestsKeepAndForTheOnesAddedLater() throws {
        let kept = try codes(of: keptCatalog)
        let table = ServerErrors.codes()
        XCTAssertTrue((kept + addedLater).allSatisfy { table.contains($0) })
        XCTAssertTrue(addedLater.allSatisfy { kept.contains($0) })
        XCTAssertEqual(table, Set(kept))
    }

    func testTheNewCodesAreToldInEachLanguageAndNotInEnglishAlone() {
        for code in ["laser_estop_latched", "printer_latched", "thermal_runaway", "slice_off"] {
            let english = ServerErrors.text(code, language: "en")
            for language in ["es", "it", "de", "fr", "pt", "zh", "ja"] { XCTAssertNotEqual(ServerErrors.text(code, language: language), english, "\(code) in \(language)") }
        }
    }
}
