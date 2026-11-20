import XCTest
@testable import Eh3dCore

/// The table of the refusal texts in eight languages: it has the 8 texts of every code, it is the catalog of the server (when the sibling folder of the server is there), and the language of the app picks the right one.
/// The same cases as the Android app.
final class ServerErrorsTests: XCTestCase {
    private let here = URL(fileURLWithPath: #filePath)
    private var repository: URL { here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private var tableFile: URL { repository.appendingPathComponent("Sources/Eh3dCore/Resources/server-errors.json") }

    override func setUpWithError() throws {
        try super.setUpWithError()
        try ServerErrors.install(String(contentsOf: tableFile, encoding: .utf8))
    }

    override func tearDownWithError() throws {
        // the tests below install small tables: the next test starts from the real one
        try ServerErrors.install(String(contentsOf: tableFile, encoding: .utf8))
        try super.tearDownWithError()
    }

    func testEveryCodeHasEightTextsAndNoneIsBlank() throws {
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: tableFile)) as? [String: [String]])
        XCTAssertGreaterThan(root.count, 100)
        for (code, row) in root {
            XCTAssertEqual(row.count, 8, code)
            for (index, text) in row.enumerated() { XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(code) #\(index) is blank") }
        }
    }

    func testTheTableOfThePackageIsTheOneThatIsInstalled() throws {
        XCTAssertEqual(try ServerErrors.parse(try ServerErrors.bundledText()), try ServerErrors.parse(try String(contentsOf: tableFile, encoding: .utf8)))
        XCTAssertTrue(ServerErrors.loaded)
    }

    func testACodeIsLowerCaseLettersDigitsAndUnderscores() {
        let allowed = try! NSRegularExpression(pattern: "^[a-z0-9_]+$")
        for code in ServerErrors.codes() { XCTAssertNotNil(allowed.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)), code) }
    }

    func testTheTableIsTheCatalogOfTheServer() throws {
        let catalog = repository.deletingLastPathComponent().appendingPathComponent("EH3D-SERVER/docs/error-codes.json")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: catalog.path), "the sibling folder EH3D-SERVER is not there")
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as? [[String: Any]])
        let codes = Set(rows.compactMap { $0["code"] as? String })
        XCTAssertEqual(codes.subtracting(ServerErrors.codes()), [], "a code of the server without text: run tools/gen_server_errors.py")
        XCTAssertEqual(ServerErrors.codes().subtracting(codes), [], "a text of a code the server no longer has: run tools/gen_server_errors.py")
    }

    func testTheNewCodesOfThePluginsAreInTheTable() {
        for code in ["laser_power_limit", "machine_alarm", "temperature_over_limit", "program_over_limit", "pnp_feeder_short", "thermal_runaway", "laser_estop_latched", "unit_unknown"] {
            XCTAssertTrue(ServerErrors.codes().contains(code), code)
        }
    }

    func testTheLanguageOfTheAppPicksItsText() throws {
        let english = try XCTUnwrap(ServerErrors.text("machine_alarm", language: "en"))
        let spanish = try XCTUnwrap(ServerErrors.text("machine_alarm", language: "es"))
        let german = try XCTUnwrap(ServerErrors.text("machine_alarm", language: "de"))
        XCTAssertNotEqual(english, spanish)
        XCTAssertNotEqual(spanish, german)
        XCTAssertTrue(english.hasPrefix("An emergency stop"))
        XCTAssertTrue(spanish.hasPrefix("Una parada de emergencia"))
        XCTAssertTrue(german.hasPrefix("Ein Not-Halt"))
    }

    func testAVariantTakesTheTextOfItsMainLanguageAndALanguageWithoutATableTakesEnglish() {
        XCTAssertEqual(ServerErrors.text("machine_alarm", language: "pt"), ServerErrors.text("machine_alarm", language: "pt-br"))
        XCTAssertEqual(ServerErrors.text("machine_alarm", language: "fr"), ServerErrors.text("machine_alarm", language: "fr-ca"))
        XCTAssertEqual(ServerErrors.text("machine_alarm", language: "en"), ServerErrors.text("machine_alarm", language: "pl"))
        XCTAssertEqual(ServerErrors.text("machine_alarm", language: "en"), ServerErrors.text("machine_alarm", language: "no"))
        XCTAssertEqual(ServerErrors.text("machine_alarm", language: "ja"), ServerErrors.text("machine_alarm", language: "JA"))
    }

    func testEveryLanguageOfTheAppHasATextForACode() {
        for language in Translator.languages.map({ $0.code }) {
            XCTAssertNotNil(ServerErrors.text("machine_alarm", language: language), language)
        }
    }

    func testACodeTheTableDoesNotHaveHasNoText() {
        XCTAssertNil(ServerErrors.text("no_such_code", language: "en"))
    }

    func testTheEightLanguagesAreInTheOrderOfTheSuite() {
        XCTAssertEqual(ServerErrors.languages, ["en", "es", "it", "de", "fr", "pt", "zh", "ja"])
        XCTAssertEqual(ServerErrors.indexOf("xx"), 0)
        XCTAssertEqual(ServerErrors.indexOf("pt"), 5)
        XCTAssertEqual(ServerErrors.indexOf(""), 0)
    }

    func testARowThatDoesNotHaveEightTextsIsLeftOutAndADamagedTableInstallsNothing() throws {
        let parsed = try ServerErrors.parse(#"{"ok":["1","2","3","4","5","6","7","8"],"short":["1","2"],"notalist":"x"}"#)
        XCTAssertEqual(Set(parsed.keys), ["ok"])
        try ServerErrors.install(#"{"ok":["1","2","3","4","5","6","7","8"]}"#)
        XCTAssertEqual(ServerErrors.text("ok", language: "fr"), "5")
        XCTAssertEqual(ServerErrors.text("ok", language: "xx"), "1")
        XCTAssertThrowsError(try ServerErrors.install("not json"))
        XCTAssertEqual(ServerErrors.text("ok", language: "fr"), "5", "a table that cannot be read leaves the one that was there")
    }

    func testABlankTextOfARowIsNoText() throws {
        try ServerErrors.install(#"{"a":["", " ","3","4","5","6","7","8"]}"#)
        XCTAssertNil(ServerErrors.text("a", language: "en"))
        XCTAssertNil(ServerErrors.text("a", language: "es"))
        XCTAssertEqual(ServerErrors.text("a", language: "it"), "3")
    }

    func testLoadingIsDoneOnceAndATableThatCannotBeReadIsNoFailure() throws {
        try ServerErrors.install(#"{"a":["1","2","3","4","5","6","7","8"]}"#)
        ServerErrors.ensureLoaded { throw ApiError(status: 0, code: "x", detail: "not read: a table is already there") }
        XCTAssertEqual(ServerErrors.text("a", language: "en"), "1")
        try ServerErrors.install("{}")
        ServerErrors.ensureLoaded { "not json" }
        XCTAssertFalse(ServerErrors.loaded)
        ServerErrors.ensureLoaded { throw ApiError(status: 0, code: "x", detail: "cannot read") }
        XCTAssertFalse(ServerErrors.loaded)
        ServerErrors.ensureBundled()
        XCTAssertTrue(ServerErrors.loaded)
    }
}
