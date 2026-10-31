// EH3D-IOS-CONTROL - the small pieces the rest of the package leans on: the session token of the server and the places where preferences are kept.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

/// What is kept of a sign-in: the name of the token (always "token" for EH3D-SERVER) and its value.
public struct SessionCookie: Equatable, Sendable {
    public let name: String
    public let value: String
    public init(name: String, value: String) { self.name = name; self.value = value }
}

/// A place for small text preferences (UserDefaults in the app, a dictionary in a test).
public protocol KeyValueStore: AnyObject {
    func get(_ key: String) -> String?
    func put(_ key: String, _ value: String)
    func remove(_ key: String)
}

public final class MemoryStore: KeyValueStore {
    public var values: [String: String] = [:]
    public init() {}
    public func get(_ key: String) -> String? { values[key] }
    public func put(_ key: String, _ value: String) { values[key] = value }
    public func remove(_ key: String) { values[key] = nil }
}

/// A version number of a release (`0.0.4`, `v0.8.0.1`): compared number by number, a missing fourth number counting as 0; anything else is not a version.
public enum SemanticVersion {
    public static func parse(_ text: String) -> [Int]? {
        var t = text.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("v") { t.removeFirst() }
        let parts = t.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard (3...4).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) && ($0 == "0" || !$0.hasPrefix("0")) }) else { return nil }
        return parts.map { Int($0) ?? 0 } + (parts.count == 3 ? [0] : [])
    }

    /// True when `candidate` is a version higher than `installed`; false for a version that cannot be read.
    public static func isNewer(_ candidate: String, than installed: String) -> Bool {
        guard let a = parse(candidate), let b = parse(installed) else { return false }
        return a.lexicographicallyPrecedes(b) == false && a != b
    }
}
