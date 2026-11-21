// EH3D-IOS-CONTROL - the light view of the values in force of the settings of the server (`GET /api/v1/settings/values`, docs/CLIENT_SYNC.md of EH3D-SERVER): read only, for any login (viewer, operator or
// administrator), a few kilobytes and never more than 16 KiB, with an ETag. A login that is not an administrator cannot read the full contract, so the page draws the labels of the copy kept in the app and
// puts on them the values of this answer. Nothing half-understood is drawn: an answer that is cut, too long, of another schema or hostile is refused whole and the page shows the copy with the reason. A secret
// never has a value here, whatever the server sent in its place. The same rules and the same cases as the Android app (model/SettingsLight.kt) and as EH3D-STUDIO (src/services/settingscontract.ts).
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

/// The version of the light answer that the app understands (`eh3d.settings.values/2` would be a newer one: the app says so and shows its copy).
public let lightSchema = "eh3d.settings.values/1"

/// The route of the light view, without the `/api/v1` that the client adds.
public let lightPath = "/settings/values"

/// The server never sends more than this of the light view; the app refuses to read more.
public let lightMaxBytes = 16 * 1024

/// What the app accepts of one answer: more keys, a longer text, a longer list or a deeper document is one it does not trust.
public let lightMaxKeys = 256
public let lightMaxText = 1024
public let lightMaxItems = 64
public let lightMaxDepth = 16

/// What stands in the place of the value of a secret key.
public let secretMark = "***"

private let unsafeKeys: Set<String> = ["__proto__", "constructor", "prototype"]

/// Whether the contract of the server is the copy the app keeps: its `contract_hash` against the hash of the copy (`unknown`: the server gave none, or one that is not a SHA-256).
public enum HashState: Equatable, Sendable { case same, differs, unknown }

/// A SHA-256 as the server writes it: 64 lower-case hexadecimal characters.
public func isSha256(_ x: Any?) -> Bool {
    guard let text = x as? String, text.utf8.count == 64 else { return false }
    return text.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }
}

/// The `contract_hash` of the server against the hash of the copy of the app.
public func compareHash(_ serverHash: Any?, copyHash: String = contractCopyHash) -> HashState {
    guard isSha256(serverHash), let text = serverHash as? String else { return .unknown }
    return text == copyHash ? .same : .differs
}

/// The ETag of an answer if it is one the app keeps and sends back (a quoted tag of printable characters, at most 96; `W/` may come first); nil for anything else, so a hostile tag is never repeated to the server.
public func validEtag(_ tag: String?) -> String? {
    guard let tag else { return nil }
    var bytes = Array(tag.utf8)
    if bytes.count >= 2 && bytes[0] == 87 && bytes[1] == 47 { bytes.removeFirst(2) }
    guard bytes.count >= 3, bytes.count <= 98, bytes[0] == 34, bytes[bytes.count - 1] == 34 else { return nil }
    let inner = bytes[1..<(bytes.count - 1)]
    return inner.allSatisfy { $0 == 0x21 || ($0 >= 0x23 && $0 <= 0x7e) } ? tag : nil
}

/// One key of the light answer. `value` is nil for a secret, a key kept back or a null.
public struct LightEntry: Equatable, Sendable {
    public let value: SettingValue?
    public let secret: Bool
    public let hidden: Bool
    public let truncated: Bool
    public let overridden: Bool
    public let editable: Bool
}

public struct LightValues: Equatable, Sendable {
    public let serverVersion: String?
    public let contractHash: String?
    public let entries: [String: LightEntry]
}

/// What reading the light answer gave: the values, an answer of a newer schema, or a document that is not to be trusted.
public enum LightParse: Equatable, Sendable {
    case ok(LightValues)
    case newer
    case shape
}

/// How deep the brackets of a JSON text go (the brackets inside texts do not count).
public func jsonDepth(_ text: String) -> Int {
    var depth = 0
    var deepest = 0
    var inText = false
    var escaped = false
    for byte in text.utf8 {
        if inText {
            if escaped { escaped = false }
            else if byte == 92 { escaped = true }
            else if byte == 34 { inText = false }
        } else if byte == 34 {
            inText = true
        } else if byte == 123 || byte == 91 {
            depth += 1
            if depth > deepest { deepest = depth }
        } else if byte == 125 || byte == 93 {
            depth -= 1
        }
    }
    return deepest
}

private func lightRoot(_ text: String) -> [String: Any]? {
    guard let data = text.data(using: .utf8), let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
    return root
}

private func isKeyName(_ key: String) -> Bool {
    let bytes = Array(key.utf8)
    guard (1...48).contains(bytes.count) else { return false }
    return bytes.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 95 }
}

private func isBoolean(_ number: NSNumber) -> Bool { String(cString: number.objCType) == "c" }

private func flag(_ any: Any?) -> Bool {
    guard let number = any as? NSNumber, isBoolean(number) else { return false }
    return number.boolValue
}

/// A value of the answer as plain data, or nil when the app does not accept it: an object, a text or a list that is too long, a list inside a list, a number that is not finite.
private func lightValue(_ raw: Any) -> SettingValue? {
    if raw is [String: Any] { return nil }
    if let text = raw as? String { return text.utf16.count > lightMaxText ? nil : .text(text) }
    if let items = raw as? [Any] {
        if items.count > lightMaxItems { return nil }
        var out: [SettingValue] = []
        for item in items {
            if item is [String: Any] || item is [Any] { return nil }
            if let text = item as? String, text.utf16.count > lightMaxText { return nil }
            if let plain = plainValue(item) { out.append(plain) }
        }
        return .list(out)
    }
    if let number = raw as? NSNumber {
        if isBoolean(number) { return .bool(number.boolValue) }
        return number.doubleValue.isFinite ? plainValue(number) : nil
    }
    return nil
}

/// Reads the answer of `GET /settings/values`. Nothing half-understood is kept: a text over `lightMaxBytes`, a document nested deeper than `lightMaxDepth`, a key that is not a name of lower-case letters,
/// digits and underscores (or one that would touch the prototype of a script), an entry that is not an object, a value that is an object, a text or list longer than the app accepts, more than `lightMaxKeys`
/// keys or a `count` that is not the number of keys make the whole answer `.shape`; another schema of the same family is `.newer`. A secret (`secret: true`, or the mark `***` as a value) and a key kept back
/// (`hidden`) never have a value.
public func parseLight(_ text: String) -> LightParse {
    if text.utf8.count > lightMaxBytes { return .shape }
    if jsonDepth(text) > lightMaxDepth { return .shape }
    guard let root = lightRoot(text) else { return .shape }
    let schema = root["schema"] as? String
    if schema != lightSchema {
        if let family = schema, family.hasPrefix("eh3d.settings.values/") { return .newer }
        return .shape
    }
    guard let settings = root["settings"] as? [String: Any] else { return .shape }
    if settings.count > lightMaxKeys { return .shape }
    if let count = root["count"] {
        guard let number = count as? NSNumber, !isBoolean(number), number.doubleValue == Double(settings.count) else { return .shape }
    }
    var entries: [String: LightEntry] = [:]
    for key in settings.keys.sorted() {
        guard isKeyName(key), !unsafeKeys.contains(key), let object = settings[key] as? [String: Any] else { return .shape }
        var secret = flag(object["secret"])
        let hidden = flag(object["hidden"])
        let raw = object["v"]
        if let mark = raw as? String, mark == secretMark { secret = true }
        var value: SettingValue?
        if let raw, !(raw is NSNull), !secret, !hidden {
            guard let plain = lightValue(raw) else { return .shape }
            value = plain
        }
        entries[key] = LightEntry(value: value, secret: secret, hidden: hidden, truncated: flag(object["truncated"]), overridden: (object["origin"] as? String) == "override", editable: flag(object["editable"]))
    }
    var version: String?
    if let given = root["server_version"] as? String, given.utf16.count <= 32 { version = given }
    var hash: String?
    if let given = root["contract_hash"] as? String, isSha256(given) { hash = given }
    return .ok(LightValues(serverVersion: version, contractHash: hash, entries: entries))
}

/// What the page uses for a light answer: the copy of the app for the texts and the values of the answer; the keys kept back, secret, cut or changed through the security page are listed apart.
public func loadedFromLight(_ light: LightValues, embedded: SettingsContract) -> LoadedContract {
    var values: [String: SettingValue] = [:]
    var secretKeys: [String] = []
    var hiddenKeys: [String] = []
    var truncatedKeys: [String] = []
    var overriddenKeys: [String] = []
    for key in light.entries.keys.sorted() {
        guard let entry = light.entries[key] else { continue }
        if entry.secret { secretKeys.append(key) }
        else if entry.hidden { hiddenKeys.append(key) }
        else if let plain = entry.value { values[key] = plain }
        if entry.truncated && !entry.secret && !entry.hidden { truncatedKeys.append(key) }
        if entry.overridden && !entry.secret { overriddenKeys.append(key) }
    }
    return LoadedContract(
        contract: embedded, live: false, values: values, serverVersion: light.serverVersion, why: nil, light: true, hash: compareHash(light.contractHash),
        secretKeys: secretKeys, hiddenKeys: hiddenKeys, truncatedKeys: truncatedKeys, overriddenKeys: overriddenKeys)
}

/// The reply to a request for the light view: a new answer with its ETag header (as the server wrote it, not yet checked), or `304` (nothing changed since the tag that was sent).
public enum LightReply: Equatable, Sendable {
    case fresh(text: String, etag: String?)
    case notModified
}

/// The last light answer and its ETag: the next request carries the tag, and a `304` gives the answer back with nothing to read. A failure forgets it.
public final class LightCache: @unchecked Sendable {
    private let lock = NSLock()
    private var tag: String?
    private var loaded: LoadedContract?

    public init() {}

    public var etag: String? { lock.lock(); defer { lock.unlock() }; return tag }
    public var last: LoadedContract? { lock.lock(); defer { lock.unlock() }; return loaded }

    public func remember(_ newTag: String?, _ value: LoadedContract) {
        lock.lock(); defer { lock.unlock() }
        tag = newTag
        loaded = newTag == nil ? nil : value
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        tag = nil
        loaded = nil
    }
}

/// What a round of reading the settings gave: the page's data and whether it is new (false: the server said `304`, what the page shows is still right).
public struct SettingsRead: Equatable, Sendable {
    public let loaded: LoadedContract
    public let changed: Bool
}

private func copyOnly(_ embedded: SettingsContract, _ why: String) -> LoadedContract {
    LoadedContract(contract: embedded, live: false, values: [:], serverVersion: nil, why: why)
}

/// One round of reading the settings of the server for a login of `role`. An administrator asks for the full contract first (it holds the texts and the values); anybody else, and an administrator whose
/// full contract could not be read (a token without the scope of the policy), asks for the light view with the tag of the last answer. The copy of the app is what remains, with the reason. A login that
/// is not an administrator never asks for the full contract: the server would refuse it. `full` and `light` are the requests, so a test can stand in for the server.
public func readSettings(role: String?, full: () async throws -> String, light: (String?) async throws -> LightReply, embedded: SettingsContract, cache: LightCache) async -> SettingsRead {
    if role == "admin" {
        let attempt = await loadContract(read: full, embedded: embedded)
        if attempt.live {
            cache.clear()
            return SettingsRead(loaded: attempt, changed: true)
        }
    }
    do {
        switch try await light(cache.etag) {
        case .notModified:
            if let last = cache.last { return SettingsRead(loaded: last, changed: false) }
            return SettingsRead(loaded: copyOnly(embedded, "shape"), changed: true)   // a 304 for a tag nobody sent
        case .fresh(let text, let tag):
            switch parseLight(text) {
            case .ok(let values):
                let loaded = loadedFromLight(values, embedded: embedded)
                cache.remember(validEtag(tag), loaded)
                return SettingsRead(loaded: loaded, changed: true)
            case .newer:
                cache.clear()
                return SettingsRead(loaded: copyOnly(embedded, "newer"), changed: true)
            case .shape:
                cache.clear()
                return SettingsRead(loaded: copyOnly(embedded, "shape"), changed: true)
            }
        }
    } catch let error as ApiError {
        cache.clear()
        return SettingsRead(loaded: copyOnly(embedded, error.code), changed: true)
    } catch {
        cache.clear()
        return SettingsRead(loaded: copyOnly(embedded, "unreachable"), changed: true)
    }
}
