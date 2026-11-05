import XCTest
@testable import Eh3dCore

/// The app is in 37 languages: every phrase of the source has its text in the 34 complete tables (all but Spanish, which is the source, and the two variants), with the same holes (the tables are the ones of the Android app);
/// the variants (Brazilian Portuguese, Canadian French) hold only what differs and take the rest from their main language; and the choice of language falls back to English.
final class TrTests: XCTestCase {
    private let codes = [
        "en", "it", "de", "fr", "pt", "zh", "ja",
        "bg", "hr", "cs", "da", "nl", "et", "fi", "el", "hu", "ga", "lv", "lt", "mt", "pl", "ro", "sk", "sl", "sv", "no", "is", "uk", "ru", "sr", "sq", "ca", "gl", "eu",
    ]
    private let variants = ["pt-br", "fr-ca"]
    private let hole = try! NSRegularExpression(pattern: #"%(?:\d+\$)?[-#+ 0,(]*\d*(?:\.\d+)?[a-zA-Z]"#)

    private func table(_ code: String) throws -> [String: String] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: code, withExtension: "json", subdirectory: "i18n"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: String])
    }

    private func holes(_ text: String) -> [String] {
        let clean = text.replacingOccurrences(of: "%%", with: "")
        let found = hole.matches(in: clean, range: NSRange(clean.startIndex..., in: clean)).compactMap { Range($0.range, in: clean).map { String(clean[$0]) } }
        return found.map { $0.replacingOccurrences(of: #"\d+\$"#, with: "", options: .regularExpression) }.sorted()
    }

    func testTheListHasThe37LanguagesOfThePrograms() throws {
        let listed = Translator.languages.map { $0.code }
        XCTAssertEqual(listed.count, 37)
        XCTAssertEqual(Set(listed).count, 37)
        XCTAssertEqual(Array(listed.prefix(8)), ["en", "es", "it", "de", "fr", "pt", "zh", "ja"])
        XCTAssertTrue(Translator.languages.allSatisfy { !$0.name.isEmpty })
        XCTAssertEqual(Set(listed).subtracting(["es"]), Set(codes + variants))
        XCTAssertEqual(Translator.fallbacks, ["pt-br": "pt", "fr-ca": "fr"])
        for code in codes + variants { _ = try table(code) }
    }

    func testTheCompleteTablesHaveTheSamePhrases() throws {
        let first = Set(try table("en").keys)
        XCTAssertGreaterThan(first.count, 100)
        for code in codes { XCTAssertEqual(Set(try table(code).keys), first, code) }
    }

    func testATranslationKeepsTheHolesOfTheSpanishPhrase() throws {
        for code in codes + variants {
            for (key, text) in try table(code) { XCTAssertEqual(holes(key), holes(text), "\(code): \(key)") }
        }
    }

    func testAVariantHoldsOnlyPhrasesOfTheSourceAndNoBlankText() throws {
        let known = Set(try table("en").keys)
        for code in variants {
            let t = try table(code)
            XCTAssertFalse(t.isEmpty, code)
            for (key, text) in t {
                XCTAssertTrue(known.contains(key), "\(code): \(key) is not a phrase of the source")
                XCTAssertFalse(text.trimmingCharacters(in: .whitespaces).isEmpty, "\(code): \(key) is blank")
            }
        }
    }

    func testNoLanguageLeavesTheEnglishTextAsItIs() throws {
        let english = try table("en")
        for code in codes.dropFirst() {
            let t = try table(code)
            let same = english.keys.filter { t[$0] == english[$0] }.count
            XCTAssertLessThanOrEqual(same, 30, "\(code) keeps \(same) English texts")
        }
    }

    func testTheSensorPhrasesTheModelPicksAreInEveryTable() throws {
        let phrases = ["valid", "signal_low", "sigma_high", "out_of_range", "sensor_fault", "none", "other"].map { laserStatusPhrase($0) } + ["good", "noisy", "none"].map { rpmQualityPhrase($0) }
        for code in codes {
            let t = try table(code)
            for phrase in phrases { XCTAssertFalse((t[phrase] ?? "").isEmpty, "\(code): \(phrase)") }
        }
    }

    func testEveryPhraseOfTheScreensIsInEveryCompleteTable() throws {
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
        XCTAssertEqual(Translator.pick(saved: nil, phone: "pt-br"), "pt-br")
        XCTAssertEqual(Translator.pick(saved: "fr-ca", phone: "de"), "fr-ca")
        XCTAssertEqual(Translator.pick(saved: nil, phone: "pl"), "pl")
        XCTAssertEqual(Translator.pick(saved: nil, phone: "ar"), "en")
        XCTAssertEqual(Translator.pick(saved: "xx", phone: "ar"), "en")
    }

    func testThePhoneAsksForAVariantOnlyWhenTheRegionIsOne() {
        XCTAssertEqual(Translator.phoneCode(tag: "pt-BR"), "pt-br")
        XCTAssertEqual(Translator.phoneCode(tag: "pt-PT"), "pt")
        XCTAssertEqual(Translator.phoneCode(tag: "fr-CA"), "fr-ca")
        XCTAssertEqual(Translator.phoneCode(tag: "fr-BE"), "fr")
        XCTAssertEqual(Translator.phoneCode(tag: "es-MX"), "es")
        XCTAssertEqual(Translator.phoneCode(tag: "zh-Hans-CN"), "zh")
        XCTAssertEqual(Translator.phoneCode(tag: "nb-NO"), "no")
        XCTAssertEqual(Translator.phoneCode(tag: "nn"), "no")
        XCTAssertEqual(Translator.phoneCode(tag: "sr"), "sr")
    }

    func testAPhraseIsSpokenInTheLanguageOfTheAppAndFallsBackToSpanish() {
        let t = Translator(language: "en", loader: { _ in ["Máquinas": "Machines", "%s máquinas": "%s machines"] })
        XCTAssertEqual(t.tr("Máquinas"), "Machines")
        XCTAssertEqual(t.trf("%s máquinas", 3), "3 machines")
        XCTAssertEqual(t.tr("Sin traducción"), "Sin traducción")
        t.select("es")
        XCTAssertEqual(t.tr("Máquinas"), "Máquinas")
    }

    func testAVariantTakesTheRestFromItsMainLanguageAndEverythingFromEnglishAtTheEnd() {
        let all: [String: [String: String]] = ["en": ["c": "C-en", "a": "A-en"], "pt": ["a": "A-pt", "b": "B-pt"], "pt-br": ["a": "A-br"]]
        let t = Translator(language: "pt-br", loader: { all[$0] })
        XCTAssertEqual(t.tr("a"), "A-br")
        XCTAssertEqual(t.tr("b"), "B-pt")
        XCTAssertEqual(t.tr("c"), "C-en")
        XCTAssertEqual(t.tr("d"), "d")
        t.select("de")
        XCTAssertEqual(t.tr("a"), "A-en")
        XCTAssertEqual(t.tr("b"), "b")
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
