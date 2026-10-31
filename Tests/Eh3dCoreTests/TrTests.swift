import XCTest
@testable import Eh3dCore

/// The app is in eight languages: every phrase of the source has its text in the seven tables, with the same holes (the tables are the ones of the Android app).
final class TrTests: XCTestCase {
    private let codes = ["en", "de", "fr", "it", "ja", "zh", "pt"]

    private func table(_ code: String) throws -> [String: String] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: code, withExtension: "json", subdirectory: "i18n"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: String])
    }

    func testTheSevenTablesHaveTheSamePhrases() throws {
        let first = Set(try table("en").keys)
        XCTAssertGreaterThan(first.count, 100)
        for code in codes { XCTAssertEqual(Set(try table(code).keys), first, code) }
    }

    func testTheSensorPhrasesTheModelPicksAreInEveryTable() throws {
        let phrases = ["valid", "signal_low", "sigma_high", "out_of_range", "sensor_fault", "none", "other"].map { laserStatusPhrase($0) } + ["good", "noisy", "none"].map { rpmQualityPhrase($0) }
        for code in codes {
            let t = try table(code)
            for phrase in phrases { XCTAssertFalse((t[phrase] ?? "").isEmpty, "\(code): \(phrase)") }
        }
    }

    func testEveryPhraseOfTheScreensIsInEveryTable() throws {
        let used = try phrasesInSources()
        XCTAssertGreaterThan(used.count, 60)
        for code in codes {
            let t = try table(code)
            for phrase in used { XCTAssertNotNil(t[phrase], "\(code): \(phrase)") }
        }
    }

    func testTheLanguageIsTheSavedOneThenThePhonesThenEnglish() {
        XCTAssertEqual(Translator.pick(saved: "de", phone: "fr"), "de")
        XCTAssertEqual(Translator.pick(saved: nil, phone: "fr"), "fr")
        XCTAssertEqual(Translator.pick(saved: nil, phone: "ru"), "en")
        XCTAssertEqual(Translator.pick(saved: "xx", phone: "ru"), "en")
    }

    func testAPhraseIsSpokenInTheLanguageOfTheAppAndFallsBackToSpanish() {
        let t = Translator(language: "en", loader: { _ in ["Máquinas": "Machines", "%s máquinas": "%s machines"] })
        XCTAssertEqual(t.tr("Máquinas"), "Machines")
        XCTAssertEqual(t.trf("%s máquinas", 3), "3 machines")
        XCTAssertEqual(t.tr("Sin traducción"), "Sin traducción")
        t.select("es")
        XCTAssertEqual(t.tr("Máquinas"), "Máquinas")
    }

    /// Every Spanish phrase written as tr("...") or trf("...") in the screens of the app.
    private func phrasesInSources() throws -> Set<String> {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App")
        let pattern = try NSRegularExpression(pattern: #"\btrf?\(\s*"((?:[^"\\]|\\.)*)""#)
        var out = Set<String>()
        for case let file as URL in FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)! where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for m in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let r = Range(m.range(at: 1), in: text) { out.insert(String(text[r]).replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\\"", with: "\"")) }
            }
        }
        return out
    }
}
