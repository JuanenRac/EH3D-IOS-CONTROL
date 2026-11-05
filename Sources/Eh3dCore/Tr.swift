// EH3D-IOS-CONTROL - the languages of the app: 37, the eight of the EH3D programs (English, Spanish, Italian, German, French, Portuguese of Portugal, Chinese, Japanese) and 29 more, the same list and the same order as the programs on the computer.
// The source text is Spanish and each phrase is looked up by it in a table per language (Resources/i18n/<code>.json: Spanish phrase -> translation), the same scheme and the same tables as the Android app.
// A phrase with a hole is written with %s (or %d) and filled by `trf`. A variant (Brazilian Portuguese, Canadian French) holds only the phrases that differ from its main language and takes the rest from it.
// A phrase that a language does not have is shown in English, and in Spanish only if the English table does not have it either; a test keeps every phrase in every table.
// The 29 added languages are translated by the model and wait for a review by native speakers. None of the 37 is written right to left.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

public final class Translator: @unchecked Sendable {
    /// The languages, in the order of the picker: code and its name in itself.
    public static let languages: [(code: String, name: String)] = [
        ("en", "English"), ("es", "Español"), ("it", "Italiano"), ("de", "Deutsch"), ("fr", "Français"), ("pt", "Português"), ("zh", "中文"), ("ja", "日本語"),
        ("bg", "Български"), ("hr", "Hrvatski"), ("cs", "Čeština"), ("da", "Dansk"), ("nl", "Nederlands"), ("et", "Eesti"), ("fi", "Suomi"), ("el", "Ελληνικά"),
        ("hu", "Magyar"), ("ga", "Gaeilge"), ("lv", "Latviešu"), ("lt", "Lietuvių"), ("mt", "Malti"), ("pl", "Polski"), ("ro", "Română"), ("sk", "Slovenčina"),
        ("sl", "Slovenščina"), ("sv", "Svenska"), ("no", "Norsk"), ("is", "Íslenska"), ("uk", "Українська"), ("ru", "Русский"), ("sr", "Српски"), ("sq", "Shqip"),
        ("ca", "Català"), ("gl", "Galego"), ("eu", "Euskara"), ("pt-br", "Português (Brasil)"), ("fr-ca", "Français (Canada)"),
    ]
    /// A variant takes the phrases it does not change from its main language.
    public static let fallbacks: [String: String] = ["pt-br": "pt", "fr-ca": "fr"]
    public typealias Loader = (String) -> [String: String]?

    private let lock = NSLock()
    private let loader: Loader
    private var tables: [String: [String: String]] = [:]
    private var current = "es"

    public init(language: String = "es", loader: @escaping Loader = Translator.bundled) {
        self.loader = loader
        select(language)
    }

    public var language: String { lock.lock(); defer { lock.unlock() }; return current }

    /// Chooses a language; a code that is not one of the 37 becomes English.
    public func select(_ code: String) {
        let chosen = Translator.languages.contains { $0.code == code } ? code : "en"
        lock.lock(); defer { lock.unlock() }
        current = chosen
        for name in Translator.chain(chosen) where tables[name] == nil { tables[name] = loader(name) ?? [:] }
    }

    /// The one to use: a saved code that is one of the 37, else the phone's if it is, else English.
    public static func pick(saved: String?, phone: String) -> String {
        if let saved, languages.contains(where: { $0.code == saved }) { return saved }
        if languages.contains(where: { $0.code == phone }) { return phone }
        return "en"
    }

    /// The code of the language of the phone from its tag (`pt-BR`, `fr-CA`, `zh-Hans-CN`): the language and the region when the pair is a variant of the list, else the language alone (`es-MX` is `es`; `nb` and `nn` are `no`).
    public static func phoneCode(tag: String) -> String {
        let parts = tag.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        guard let first = parts.first?.lowercased() else { return "en" }
        let lang = (first == "nb" || first == "nn") ? "no" : first
        let region = parts.dropFirst().first(where: { part in part.count == 2 && part.allSatisfy { $0.isLetter } })?.lowercased()
        if let region, languages.contains(where: { $0.code == "\(lang)-\(region)" }) { return "\(lang)-\(region)" }
        return lang
    }

    /// The tables to look a phrase up in, in order: the language, its main language if it is a variant, and English.
    public static func chain(_ code: String) -> [String] {
        var out: [String] = []
        for name in [code, fallbacks[code] ?? code, "en"] where name != "es" && !out.contains(name) { out.append(name) }
        return out
    }

    /// The phrase (written in Spanish in the source) in the language of the app.
    public func tr(_ es: String) -> String {
        lock.lock(); defer { lock.unlock() }
        if current == "es" { return es }
        for name in Translator.chain(current) { if let text = tables[name]?[es] { return text } }
        return es
    }

    /// The same for a phrase with holes (%s, %d), filled in order with the text of the arguments.
    public func trf(_ es: String, _ args: Any...) -> String {
        Translator.fill(tr(es), args)
    }

    /// Fills `%s` and `%d` in order, and `%1$s`, `%2$d`... by position (a translation may need to put the holes in another order).
    public static func fill(_ template: String, _ args: [Any]) -> String {
        let chars = Array(template)
        var out = ""
        var index = 0
        var i = 0
        while i < chars.count {
            let c = chars[i]
            guard c == "%", i + 1 < chars.count else { out.append(c); i += 1; continue }
            // %% is a percent sign
            if chars[i + 1] == "%" { out.append("%"); i += 2; continue }
            // %s or %d
            if chars[i + 1] == "s" || chars[i + 1] == "d" {
                if index < args.count { out += String(describing: args[index]); index += 1 }
                i += 2; continue
            }
            // %.Nf: a number with N decimals, always with a point
            if chars[i + 1] == "." {
                var k = i + 2
                var places = ""
                while k < chars.count, chars[k].isASCII, chars[k].isNumber { places.append(chars[k]); k += 1 }
                if !places.isEmpty, k < chars.count, chars[k] == "f", let n = Int(places), n <= 9 {
                    if index < args.count {
                        let value = (args[index] as? Double) ?? (args[index] as? Float).map { Double($0) } ?? (args[index] as? Int).map { Double($0) } ?? 0
                        out += String(format: "%.\(n)f", locale: Locale(identifier: "en_US_POSIX"), value)
                        index += 1
                    }
                    i = k + 1; continue
                }
            }
            // %N$s or %N$d
            var j = i + 1
            var digits = ""
            while j < chars.count, chars[j].isASCII, chars[j].isNumber { digits.append(chars[j]); j += 1 }
            if !digits.isEmpty, j + 1 < chars.count, chars[j] == "$", chars[j + 1] == "s" || chars[j + 1] == "d" {
                if let position = Int(digits), position >= 1, position <= args.count { out += String(describing: args[position - 1]) }
                i = j + 2; continue
            }
            out.append(c); i += 1
        }
        return out
    }

    /// The tables shipped inside the package.
    public static func bundled(_ code: String) -> [String: String]? {
        guard let url = Bundle.module.url(forResource: code, withExtension: "json", subdirectory: "i18n"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return nil }
        return object
    }
}
