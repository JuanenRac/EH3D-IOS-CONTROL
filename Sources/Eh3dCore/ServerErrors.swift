// EH3D-IOS-CONTROL - the text of every refusal code of the server in the eight languages of the suite (English, Spanish, Italian, German, French, European Portuguese, Chinese, Japanese).
// The table is Resources/server-errors.json, written by tools/gen_server_errors.py from the catalog of EH3D-SERVER and the rows `err_<code>` of Studio, so the app says what Studio says. A language the
// table does not have (the other 29 of the app) shows the English text; a code a newer server has and this table does not is not hidden: the caller shows the message of the server.
// The same table and the same rules as the Android app (ServerErrors.kt).
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

public enum ServerErrors {
    /// The languages of the table, in the order of the texts of a row.
    public static let languages = ["en", "es", "it", "de", "fr", "pt", "zh", "ja"]

    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var rows: [String: [String]] = [:]
        func get() -> [String: [String]] { lock.lock(); defer { lock.unlock() }; return rows }
        func set(_ value: [String: [String]]) { lock.lock(); defer { lock.unlock() }; rows = value }
    }

    private static let store = Store()

    /// True once a table has been installed.
    public static var loaded: Bool { !store.get().isEmpty }

    /// The table of the JSON text `{"code": [eight texts]}`; a row that does not have eight texts is left out.
    public static func parse(_ json: String) throws -> [String: [String]] {
        guard let data = json.data(using: .utf8), let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ApiError(status: 0, code: "bad_json", detail: "not a JSON object") }
        var out: [String: [String]] = [:]
        for (code, value) in root {
            guard let row = value as? [Any], row.count == languages.count else { continue }
            out[code] = row.map { ($0 as? String) ?? "" }
        }
        return out
    }

    /// Puts a table in place (the tests do it without a bundle); a text that is not a table throws and leaves the one that was there.
    public static func install(_ json: String) throws { store.set(try parse(json)) }

    /// Loads the table once with `read`; a table that cannot be read leaves the app with the texts it already has.
    public static func ensureLoaded(_ read: () throws -> String) {
        if loaded { return }
        if let text = try? read() { try? install(text) }
    }

    /// The table shipped inside the package.
    public static func bundledText() throws -> String {
        guard let url = Bundle.module.url(forResource: "server-errors", withExtension: "json") else { throw ApiError(status: 0, code: "missing_table", detail: "server-errors.json") }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Loads the table of the package once.
    public static func ensureBundled() { ensureLoaded(bundledText) }

    /// The codes of the table.
    public static func codes() -> Set<String> { Set(store.get().keys) }

    /// The index of the text for a language of the app: the language, its main language for a variant (`pt-br`, `fr-ca`), else English.
    public static func indexOf(_ language: String) -> Int {
        let main = language.lowercased().split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        return languages.firstIndex(of: main) ?? 0
    }

    /// The text of a code in the language of the app, or nil when the table does not have the code or a blank text.
    public static func text(_ code: String, language: String) -> String? {
        guard let row = store.get()[code] else { return nil }
        let index = indexOf(language)
        guard index < row.count, !row[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return row[index]
    }
}
