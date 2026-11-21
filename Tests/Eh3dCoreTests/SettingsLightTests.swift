import XCTest
#if canImport(CryptoKit)
import CryptoKit
#endif
@testable import Eh3dCore

/// A server of the test for the light view of the settings (`GET /api/v1/settings/values`): it answers with what the test says, writes down every request and can fail like a network. Tests of this file run one
/// at a time.
private final class LightSim: URLProtocol {
    struct Hit: Equatable {
        let method: String
        let path: String
        let authorization: String
        let ifNoneMatch: String?
    }

    struct Reply {
        var status: Int
        var text: String
        var headers: [String: String] = [:]
    }

    static let lock = NSLock()
    static var seen: [Hit] = []
    static var reply: (Hit) -> Reply = { _ in Reply(status: 200, text: "{}") }
    static var failure: Error?

    static func reset(_ reply: @escaping (Hit) -> Reply) {
        lock.lock(); defer { lock.unlock() }
        seen = []
        failure = nil
        self.reply = reply
    }

    static var asked: [Hit] { lock.lock(); defer { lock.unlock() }; return seen }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LightSim.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let hit = Hit(method: request.httpMethod ?? "GET", path: url.path, authorization: request.value(forHTTPHeaderField: "Authorization") ?? "", ifNoneMatch: request.value(forHTTPHeaderField: "If-None-Match"))
        LightSim.lock.lock()
        LightSim.seen.append(hit)
        let failure = LightSim.failure
        let reply = LightSim.reply
        LightSim.lock.unlock()
        if let failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let answer = reply(hit)
        let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !answer.text.isEmpty { client?.urlProtocol(self, didLoad: Data(answer.text.utf8)) }
        client?.urlProtocolDidFinishLoading(self)
    }
}

private struct NotRead: Error {}

/// Readers of one round that answer with the replies given, one per call, and write down every tag that was sent and how many times the full contract was asked.
private final class Script {
    let replies: [() throws -> LightReply]
    var tags: [String?] = []
    var fullCalls = 0
    var lightCalls = 0
    var fullAnswer: () throws -> String = { throw ApiError(status: 403, code: "forbidden", detail: "no") }

    init(_ replies: [() throws -> LightReply]) { self.replies = replies }

    func full() async throws -> String {
        fullCalls += 1
        return try fullAnswer()
    }

    func light(_ tag: String?) async throws -> LightReply {
        tags.append(tag)
        let reply = replies[min(lightCalls, replies.count - 1)]
        lightCalls += 1
        return try reply()
    }
}

private enum CountMember { case auto, absent, value(Int) }

/// The light view of the values in force of the settings: what is read from a good answer, what a secret, a key kept back and a cut value become, the answers that are refused whole (cut, too long, another
/// schema, hostile), the hash of the copy against the one of the server, the ETag that is kept and sent back, the choice between the full contract and the light view by role, the `304`, an old server and a
/// refused login, and the client against a simulated server. The same cases as the Android app (SettingsLightTest). Fixed documents, no clock and no network.
final class SettingsLightTests: XCTestCase {
    private let here = URL(fileURLWithPath: #filePath)
    private var resources: URL { here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/Eh3dCore/Resources") }
    private func copyText() throws -> String { try String(contentsOf: resources.appendingPathComponent("settings-contract.json"), encoding: .utf8) }
    private func embeddedCopy() throws -> SettingsContract { try XCTUnwrap(parseContract(try copyText())) }

    /// One key of the answer: the value as JSON text (or none), with the origin and whether the policy changes it; `extra` is more members.
    private func item(_ v: String? = nil, origin: String = "file", editable: Bool = false, extra: String = "") -> String {
        var parts: [String] = []
        if let v { parts.append("\"v\":\(v)") }
        parts.append("\"origin\":\"\(origin)\"")
        parts.append("\"editable\":\(editable)")
        if !extra.isEmpty { parts.append(extra) }
        return "{" + parts.joined(separator: ",") + "}"
    }

    /// A whole answer made from the keys given; the members the server always sends can be left out.
    private func body(_ entries: [(String, String)] = [], count: CountMember = .auto, schema: String = lightSchema, hash: String? = contractCopyHash, version: String? = "0.2.1") -> String {
        var parts: [String] = ["\"schema\":\"\(schema)\""]
        if let version { parts.append("\"server_version\":\"\(version)\"") }
        if let hash { parts.append("\"contract_hash\":\"\(hash)\"") }
        switch count {
        case .auto: parts.append("\"count\":\(entries.count)")
        case .value(let n): parts.append("\"count\":\(n)")
        case .absent: break
        }
        parts.append("\"settings\":{" + entries.map { "\"" + $0.0 + "\":" + $0.1 }.joined(separator: ",") + "}")
        return "{" + parts.joined(separator: ",") + "}"
    }

    private func good() -> String {
        body([("session_hours", item("12")), ("password_min_len", item("12", origin: "override", editable: true)), ("allow_remote", item("true"))])
    }

    private func read(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws -> LightValues {
        guard case .ok(let light) = parseLight(text) else {
            XCTFail("the answer was not read", file: file, line: line)
            throw NotRead()
        }
        return light
    }

    private func refused(_ text: String) -> Bool { parseLight(text) == .shape }

    private func fresh(_ text: String, _ tag: String? = "\"t1\"") -> () throws -> LightReply {
        return { LightReply.fresh(text: text, etag: tag) }
    }

    private func notModified() -> () throws -> LightReply { return { LightReply.notModified } }

    private func failing(_ error: Error) -> () throws -> LightReply { return { throw error } }

    // ---- a good answer

    func testAGoodAnswerGivesTheValuesTheOriginAndWhetherThePolicyChangesThem() throws {
        let light = try read(good())
        XCTAssertEqual(light.serverVersion, "0.2.1")
        XCTAssertEqual(light.contractHash, contractCopyHash)
        XCTAssertEqual(Set(light.entries.keys), ["session_hours", "password_min_len", "allow_remote"])
        let hours = try XCTUnwrap(light.entries["session_hours"])
        XCTAssertEqual(hours.value, SettingValue.int(12)); XCTAssertFalse(hours.overridden); XCTAssertFalse(hours.editable)
        let minimum = try XCTUnwrap(light.entries["password_min_len"])
        XCTAssertTrue(minimum.overridden); XCTAssertTrue(minimum.editable)
        XCTAssertEqual(light.entries["allow_remote"]?.value, SettingValue.bool(true))
    }

    func testANumberIsAWholeNumberOrADoubleAndATextAndAListAreKept() throws {
        let light = try read(body([("a", item("12")), ("b", item("1.5")), ("c", item("\"text\"")), ("d", item("[\"x\",\"y\"]")), ("e", item("[1,2]")), ("f", item("false"))]))
        XCTAssertEqual(light.entries["a"]?.value, SettingValue.int(12))
        XCTAssertEqual(light.entries["b"]?.value, SettingValue.double(1.5))
        XCTAssertEqual(light.entries["c"]?.value, SettingValue.text("text"))
        XCTAssertEqual(light.entries["d"]?.value, SettingValue.list([.text("x"), .text("y")]))
        XCTAssertEqual(light.entries["e"]?.value, SettingValue.list([.int(1), .int(2)]))
        XCTAssertEqual(light.entries["f"]?.value, SettingValue.bool(false))
    }

    func testAnAnswerWithoutCountOrVersionOrHashIsStillRead() throws {
        let light = try read(body([("a", item("1"))], count: .absent, hash: nil, version: nil))
        XCTAssertNil(light.serverVersion); XCTAssertNil(light.contractHash)
        XCTAssertEqual(light.entries.count, 1)
    }

    func testAnEmptyListOfKeysIsAnAnswer() throws {
        XCTAssertEqual(try read(body()).entries.count, 0)
    }

    func testAVersionOverThirtyTwoCharactersAndAHashThatIsNotASha256AreLeftOut() throws {
        let long = try read(body([("a", item("1"))], hash: "7D42AF90FD90D6E9B1366B02AD2B157E2B415BAE9716432560AA8154E19D9858", version: String(repeating: "9", count: 33)))
        XCTAssertNil(long.serverVersion); XCTAssertNil(long.contractHash)
        XCTAssertNil(try read(body([("a", item("1"))], hash: "abc")).contractHash)
        XCTAssertEqual(try read(body([("a", item("1"))], version: String(repeating: "9", count: 32))).serverVersion, String(repeating: "9", count: 32))
    }

    // ---- secrets, keys kept back, cut values

    func testASecretNeverHasAValueWhateverTheServerSentInItsPlace() throws {
        let light = try read(body([("one", item("\"***\"", extra: "\"secret\":true")), ("two", item("\"***\"")), ("three", item("\"hunter2\"", extra: "\"secret\":true")), ("four", item("[\"a\"]", extra: "\"secret\":true"))]))
        for key in ["one", "two", "three", "four"] {
            let entry = try XCTUnwrap(light.entries[key], key)
            XCTAssertTrue(entry.secret, key); XCTAssertNil(entry.value, key)
        }
        let loaded = loadedFromLight(light, embedded: try embeddedCopy())
        XCTAssertEqual(loaded.secretKeys, ["four", "one", "three", "two"])
        XCTAssertTrue(loaded.values.isEmpty)
    }

    func testAKeyKeptBackHasNoValueAndIsNamedApart() throws {
        let light = try read(body([("data_dir", item(extra: "\"hidden\":true")), ("other", item("\"/home/x\"", extra: "\"hidden\":true")), ("a", item("1"))]))
        XCTAssertEqual(light.entries["data_dir"]?.hidden, true); XCTAssertNil(light.entries["data_dir"]?.value)
        XCTAssertNil(light.entries["other"]?.value)
        let loaded = loadedFromLight(light, embedded: try embeddedCopy())
        XCTAssertEqual(loaded.hiddenKeys, ["data_dir", "other"])
        let expected: [String: SettingValue] = ["a": .int(1)]
        XCTAssertEqual(loaded.values, expected)
    }

    func testACutValueAndAKeyChangedThroughTheSecurityPageAreListed() throws {
        let light = try read(body([("a", item("\"long te\"", extra: "\"truncated\":true")), ("b", item("1", origin: "override")), ("c", item("\"***\"", origin: "override", extra: "\"secret\":true"))]))
        let loaded = loadedFromLight(light, embedded: try embeddedCopy())
        XCTAssertEqual(loaded.truncatedKeys, ["a"])
        XCTAssertEqual(loaded.overriddenKeys, ["b"])
        XCTAssertEqual(loaded.values["a"], SettingValue.text("long te"))
    }

    func testTheLightViewIsTheCopyOfTheAppWithTheValuesAndIsNeitherLiveNorEditable() throws {
        let embedded = try embeddedCopy()
        let loaded = loadedFromLight(try read(good()), embedded: embedded)
        XCTAssertTrue(loaded.light); XCTAssertFalse(loaded.live); XCTAssertNil(loaded.why)
        XCTAssertEqual(loaded.serverVersion, "0.2.1")
        XCTAssertEqual(loaded.hash, HashState.same)
        XCTAssertEqual(loaded.contract, embedded)
        let hours = try XCTUnwrap(embedded.settings.first { $0.key == "session_hours" })
        XCTAssertEqual(valueOf(hours, loaded.values), SettingValue.int(12))
    }

    func testAKeyNobodyDescribedIsDrawnReadOnlyAlsoWhenItIsSecretOrKeptBack() throws {
        let loaded = loadedFromLight(try read(body([("future", item("3")), ("future_secret", item("\"***\"", extra: "\"secret\":true")), ("future_path", item(extra: "\"hidden\":true")), ("session_hours", item("12"))])), embedded: try embeddedCopy())
        let rows = unlistedSettings(loaded.contract, loaded.values, kept: loaded.secretKeys + loaded.hiddenKeys)
        XCTAssertEqual(rows.map { $0.key }, ["future", "future_path", "future_secret"])
        XCTAssertEqual(rows[0].group, "other")
    }

    // ---- the schema and the answers that are refused whole

    func testANewerSchemaOfTheSameFamilyIsToldApartFromOneThatIsNot() {
        XCTAssertEqual(parseLight(body([("a", item("1"))], schema: "eh3d.settings.values/2")), LightParse.newer)
        XCTAssertEqual(parseLight(body([("a", item("1"))], schema: "eh3d.settings.contract/1")), LightParse.shape)
        XCTAssertEqual(parseLight(body([("a", item("1"))], schema: "other")), LightParse.shape)
        XCTAssertEqual(parseLight(#"{"settings":{}}"#), LightParse.shape)
        XCTAssertEqual(parseLight(#"{"schema":7,"settings":{}}"#), LightParse.shape)
    }

    func testAnAnswerThatIsNotAJsonObjectIsRefused() {
        for text in ["", "not json", "[]", "null", "7", "\"text\"", "{", "{\"schema\":"] { XCTAssertTrue(refused(text), text) }
    }

    func testAnAnswerThatWasCutIsRefusedWholeAtEveryLength() {
        let text = good()
        for n in 1..<(text.utf8.count - 1) { XCTAssertTrue(refused(String(text.prefix(n))), "cut at \(n)") }
    }

    func testAnAnswerLongerThanTheLimitIsRefusedEvenWhenItIsAGoodDocument() {
        let big = body((0..<17).map { ("k\($0)", item("\"" + String(repeating: "x", count: 1000) + "\"")) })
        XCTAssertGreaterThan(big.utf8.count, lightMaxBytes)
        XCTAssertTrue(refused(big))
        let padded = body([("a", item("1"))], version: nil) + String(repeating: " ", count: lightMaxBytes)
        XCTAssertTrue(refused(padded))
    }

    func testAKeyThatIsNotANameIsRefused() {
        for key in ["Upper", "with space", "dash-ed", "", String(repeating: "x", count: 49), "__proto__", "constructor", "prototype", "a.b", "é"] {
            XCTAssertTrue(refused(body([(key, item("1"))], count: .value(1))), "[\(key)]")
        }
        XCTAssertFalse(refused(body([(String(repeating: "x", count: 48), item("1"))], count: .value(1))))
    }

    func testAnEntryThatIsNotAnObjectIsRefused() {
        for entry in ["1", "null", "\"text\"", "[]", "true"] { XCTAssertTrue(refused(body([("a", entry)], count: .value(1))), entry) }
    }

    func testAValueThatIsAnObjectOrAnOverlongTextOrListIsRefused() {
        XCTAssertTrue(refused(body([("a", item("{\"x\":1}"))])))
        XCTAssertTrue(refused(body([("a", item("\"" + String(repeating: "x", count: lightMaxText + 1) + "\""))])))
        XCTAssertFalse(refused(body([("a", item("\"" + String(repeating: "x", count: lightMaxText) + "\"")), ("b", item("\"yyyyyyyyyy\""))])))
        func list(_ n: Int) -> String { "[" + Array(repeating: "\"i\"", count: n).joined(separator: ",") + "]" }
        XCTAssertTrue(refused(body([("a", item(list(lightMaxItems + 1)))])))
        XCTAssertFalse(refused(body([("a", item(list(lightMaxItems)))])))
        XCTAssertTrue(refused(body([("a", item("[{\"x\":1}]"))])))
        XCTAssertTrue(refused(body([("a", item("[[1]]"))])))
        XCTAssertTrue(refused(body([("a", item("[\"" + String(repeating: "z", count: lightMaxText + 1) + "\"]"))])))
    }

    func testMoreKeysThanTheLimitAreRefused() {
        let many = (0...lightMaxKeys).map { ("k\($0)", item("1")) }
        XCTAssertEqual(many.count, lightMaxKeys + 1)
        XCTAssertTrue(refused(body(many)))
        XCTAssertFalse(refused(body(Array(many.prefix(lightMaxKeys)), count: .value(lightMaxKeys))))
    }

    func testACountThatIsNotTheNumberOfKeysIsRefused() {
        XCTAssertTrue(refused(body([("a", item("1"))], count: .value(3))))
        XCTAssertTrue(refused(body([("a", item("1"))], count: .value(0))))
        XCTAssertTrue(refused(body([("a", item("1"))], count: .absent).replacingOccurrences(of: "\"settings\"", with: "\"count\":\"1\",\"settings\"")))
        XCTAssertTrue(refused(body([("a", item("1"))], count: .absent).replacingOccurrences(of: "\"settings\"", with: "\"count\":null,\"settings\"")))
        XCTAssertFalse(refused(body([("a", item("1"))], count: .value(1))))
    }

    func testADocumentNestedTooDeepIsRefusedWithoutBeingParsed() {
        let deep = String(repeating: "[", count: 400) + String(repeating: "]", count: 400)
        XCTAssertTrue(refused(body([("a", item(deep))])))
        let nested = "{\"schema\":\"\(lightSchema)\",\"settings\":" + String(repeating: "{\"a\":", count: 300) + "1" + String(repeating: "}", count: 300) + "}"
        XCTAssertTrue(refused(nested))
    }

    func testTheDepthCountsBracketsAndNotTheOnesInsideTexts() {
        XCTAssertEqual(jsonDepth("1"), 0)
        XCTAssertEqual(jsonDepth(#"{"a":[{"b":1}]}"#), 3)
        XCTAssertEqual(jsonDepth(#"{"a":"[[[[ {{{ \" ]]]"}"#), 1)
    }

    // ---- the hash of the copy against the one of the server

    func testTheHashOfTheServerIsComparedWithTheOneOfTheCopy() {
        XCTAssertEqual(compareHash(contractCopyHash), HashState.same)
        XCTAssertEqual(compareHash(String(repeating: "0", count: 64)), HashState.differs)
        XCTAssertEqual(compareHash(nil), HashState.unknown)
        XCTAssertEqual(compareHash(""), HashState.unknown)
        XCTAssertEqual(compareHash(contractCopyHash.uppercased()), HashState.unknown)
        XCTAssertEqual(compareHash(contractCopyHash + "0"), HashState.unknown)
        XCTAssertEqual(compareHash(7), HashState.unknown)
        XCTAssertEqual(compareHash(contractCopyHash + "\n"), HashState.unknown)
    }

    func testAnAnswerSaysWhetherTheCopyIsTheListOfTheServer() throws {
        let embedded = try embeddedCopy()
        XCTAssertEqual(loadedFromLight(try read(good()), embedded: embedded).hash, HashState.same)
        XCTAssertEqual(loadedFromLight(try read(body([("a", item("1"))], hash: String(repeating: "1", count: 64))), embedded: embedded).hash, HashState.differs)
        XCTAssertEqual(loadedFromLight(try read(body([("a", item("1"))], hash: nil)), embedded: embedded).hash, HashState.unknown)
        XCTAssertEqual(loadedFromLight(try read(body([("a", item("1"))], hash: "xyz")), embedded: embedded).hash, HashState.unknown)
    }

    func testTheHashOfTheAppIsTheSha256OfItsCopyWithLfLineEnds() throws {
        #if canImport(CryptoKit)
        let text = try copyText().replacingOccurrences(of: "\r\n", with: "\n")
        let digest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, contractCopyHash)
        XCTAssertTrue(isSha256(contractCopyHash))
        #else
        throw XCTSkip("CryptoKit is not available here")
        #endif
    }

    func testTheLimitsOfTheAppAreTheOnesTheContractOfTheServerSays() throws {
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(try copyText().utf8)) as? [String: Any])
        let light = try XCTUnwrap(root["read_light"] as? [String: Any])
        let limits = try XCTUnwrap(light["limits"] as? [String: Any])
        XCTAssertEqual(light["schema"] as? String, lightSchema)
        XCTAssertEqual((light["path"] as? String)?.replacingOccurrences(of: "/api/v1", with: ""), lightPath)
        XCTAssertEqual(light["secret_mark"] as? String, secretMark)
        XCTAssertEqual(light["role"] as? String, "viewer")
        XCTAssertEqual(limits["max_bytes"] as? Int, lightMaxBytes)
        XCTAssertLessThanOrEqual(try XCTUnwrap(limits["max_text_chars"] as? Int), lightMaxText)
        XCTAssertLessThanOrEqual(try XCTUnwrap(limits["max_list_items"] as? Int), lightMaxItems)
    }

    // ---- the ETag

    func testOnlyAValidEtagIsKept() {
        for tag in ["\"abc\"", "W/\"abc\"", "\"" + String(repeating: "a", count: 96) + "\"", "\"!#~\""] { XCTAssertEqual(validEtag(tag), tag) }
        for tag in ["abc", "\"\"", "\"" + String(repeating: "a", count: 97) + "\"", "\"a b\"", "\"a\"b\"", "\"a\nb\"", "\"é\"", "W/abc", "w/\"abc\"", " \"abc\"", "\"abc\" "] { XCTAssertNil(validEtag(tag), "[\(tag)]") }
        XCTAssertNil(validEtag(nil))
    }

    // ---- one round of reading, by role

    func testALoginThatIsNotAnAdministratorNeverAsksForTheFullContract() async throws {
        let embedded = try embeddedCopy()
        for role in ["viewer", "operator", nil, "hmi", ""] as [String?] {
            let script = Script([fresh(good())])
            let read = await readSettings(role: role, full: script.full, light: script.light, embedded: embedded, cache: LightCache())
            XCTAssertEqual(script.fullCalls, 0)
            XCTAssertTrue(read.loaded.light); XCTAssertTrue(read.changed)
            let expected: [String: SettingValue] = ["session_hours": .int(12), "password_min_len": .int(12), "allow_remote": .bool(true)]
            XCTAssertEqual(read.loaded.values, expected)
        }
    }

    func testAnAdministratorWithTheFullContractDoesNotAskForTheLightView() async throws {
        let script = Script([fresh(good())])
        script.fullAnswer = { #"{"schema":"eh3d.settings.contract/1","groups":[],"settings":[],"values":{"a":true},"server_version":"0.2.1"}"# }
        let cache = LightCache()
        let read = await readSettings(role: "admin", full: script.full, light: script.light, embedded: try embeddedCopy(), cache: cache)
        XCTAssertEqual(script.fullCalls, 1); XCTAssertEqual(script.lightCalls, 0)
        XCTAssertTrue(read.loaded.live); XCTAssertFalse(read.loaded.light); XCTAssertTrue(read.changed)
        XCTAssertNil(cache.etag)
    }

    func testAnAdministratorWhoseTokenCannotReadTheContractFallsBackToTheLightView() async throws {
        let script = Script([fresh(good())])
        let read = await readSettings(role: "admin", full: script.full, light: script.light, embedded: try embeddedCopy(), cache: LightCache())
        XCTAssertEqual(script.fullCalls, 1); XCTAssertEqual(script.lightCalls, 1)
        XCTAssertTrue(read.loaded.light); XCTAssertFalse(read.loaded.live)
        XCTAssertEqual(read.loaded.values["session_hours"], SettingValue.int(12))
    }

    func testAnAdministratorWhoseFullContractIsNotOneAlsoFallsBackToTheLightView() async throws {
        let script = Script([fresh(good())])
        script.fullAnswer = { #"{"schema":"other"}"# }
        let read = await readSettings(role: "admin", full: script.full, light: script.light, embedded: try embeddedCopy(), cache: LightCache())
        XCTAssertTrue(read.loaded.light)
    }

    func testTheTagOfTheLastAnswerIsSentBackAndA304KeepsThePage() async throws {
        let script = Script([fresh(good(), "\"t1\""), notModified()])
        let cache = LightCache()
        let embedded = try embeddedCopy()
        let first = await readSettings(role: "viewer", full: script.full, light: script.light, embedded: embedded, cache: cache)
        XCTAssertTrue(first.changed); XCTAssertEqual(cache.etag, "\"t1\"")
        let second = await readSettings(role: "viewer", full: script.full, light: script.light, embedded: embedded, cache: cache)
        XCTAssertFalse(second.changed)
        XCTAssertEqual(second.loaded, first.loaded)
        XCTAssertEqual(script.tags, [nil, "\"t1\""])
    }

    func testANewAnswerReplacesTheTag() async throws {
        let script = Script([fresh(good(), "\"t1\""), fresh(body([("a", item("1"))]), "\"t2\""), notModified()])
        let cache = LightCache()
        let embedded = try embeddedCopy()
        _ = await readSettings(role: "viewer", full: script.full, light: script.light, embedded: embedded, cache: cache)
        let second = await readSettings(role: "viewer", full: script.full, light: script.light, embedded: embedded, cache: cache)
        XCTAssertTrue(second.changed); XCTAssertEqual(cache.etag, "\"t2\"")
        let third = await readSettings(role: "viewer", full: script.full, light: script.light, embedded: embedded, cache: cache)
        let expected: [String: SettingValue] = ["a": .int(1)]
        XCTAssertFalse(third.changed); XCTAssertEqual(third.loaded.values, expected)
        XCTAssertEqual(script.tags, [nil, "\"t1\"", "\"t2\""])
    }

    func testAnAnswerWithNoTagOrWithATagThatIsNotValidIsNeverCachedOrSentBack() async throws {
        let embedded = try embeddedCopy()
        for tag in [nil, "no quotes", "\"a b\"", ""] as [String?] {
            let script = Script([fresh(good(), tag)])
            let cache = LightCache()
            _ = await readSettings(role: "viewer", full: script.full, light: script.light, embedded: embedded, cache: cache)
            XCTAssertNil(cache.etag, "[\(tag ?? "nil")]"); XCTAssertNil(cache.last)
            _ = await readSettings(role: "viewer", full: script.full, light: script.light, embedded: embedded, cache: cache)
            XCTAssertEqual(script.tags, [nil, nil])
        }
    }

    func testA304ForATagNobodySentIsTheCopyWithAReasonAndNothingIsDrawn() async throws {
        let script = Script([notModified()])
        let read = await readSettings(role: "viewer", full: script.full, light: script.light, embedded: try embeddedCopy(), cache: LightCache())
        XCTAssertFalse(read.loaded.light); XCTAssertFalse(read.loaded.live); XCTAssertEqual(read.loaded.why, "shape")
        XCTAssertTrue(read.loaded.values.isEmpty)
    }

    func testALoginThatChangesForgetsTheTag() async throws {
        let script = Script([fresh(good())])
        let cache = LightCache()
        let embedded = try embeddedCopy()
        _ = await readSettings(role: "viewer", full: script.full, light: script.light, embedded: embedded, cache: cache)
        XCTAssertNotNil(cache.etag)
        cache.clear()
        XCTAssertNil(cache.etag); XCTAssertNil(cache.last)
        _ = await readSettings(role: "operator", full: script.full, light: script.light, embedded: embedded, cache: cache)
        XCTAssertEqual(script.tags, [nil, nil])
    }

    func testAFailedReadForgetsTheTagAndShowsTheCopyWithTheCodeOfTheServer() async throws {
        let script = Script([fresh(good()), failing(ApiError(status: 500, code: "internal", detail: "boom")), fresh(good())])
        let cache = LightCache()
        let embedded = try embeddedCopy()
        _ = await readSettings(role: "viewer", full: script.full, light: script.light, embedded: embedded, cache: cache)
        let failed = await readSettings(role: "viewer", full: script.full, light: script.light, embedded: embedded, cache: cache)
        XCTAssertEqual(failed.loaded.why, "internal"); XCTAssertTrue(failed.changed)
        XCTAssertFalse(failed.loaded.light); XCTAssertTrue(failed.loaded.values.isEmpty)
        XCTAssertNil(cache.etag); XCTAssertNil(cache.last)
        _ = await readSettings(role: "viewer", full: script.full, light: script.light, embedded: embedded, cache: cache)
        XCTAssertEqual(script.tags, [nil, "\"t1\"", nil])
    }

    func testAnOldServerWithoutTheRouteAndARefusedLoginShowTheCopyWithTheirCode() async throws {
        let embedded = try embeddedCopy()
        let old = Script([failing(ApiError(status: 404, code: "not_found", detail: "no route"))])
        let a = await readSettings(role: "viewer", full: old.full, light: old.light, embedded: embedded, cache: LightCache())
        XCTAssertEqual(a.loaded.why, "not_found"); XCTAssertFalse(a.loaded.light); XCTAssertEqual(a.loaded.contract, embedded)
        let login = Script([failing(ApiError(status: 401, code: "unauthorized", detail: "no login"))])
        let b = await readSettings(role: "viewer", full: login.full, light: login.light, embedded: embedded, cache: LightCache())
        XCTAssertEqual(b.loaded.why, "unauthorized")
        let away = Script([failing(URLError(.notConnectedToInternet))])
        let c = await readSettings(role: "viewer", full: away.full, light: away.light, embedded: embedded, cache: LightCache())
        XCTAssertEqual(c.loaded.why, "unreachable")
    }

    func testAnAnswerThatIsHostileOrOfAnotherSchemaIsNotDrawnHalfAndForgetsTheTag() async throws {
        let embedded = try embeddedCopy()
        let cases: [(String, String)] = [
            (String(good().dropLast(7)), "shape"), (body([("a", item("{\"x\":1}"))]), "shape"), (body([("a", item("1"))], schema: "eh3d.settings.values/2"), "newer"), ("<html>", "shape"),
        ]
        for (text, why) in cases {
            let script = Script([fresh(good(), "\"t1\""), fresh(text, "\"t2\"")])
            let cache = LightCache()
            _ = await readSettings(role: "viewer", full: script.full, light: script.light, embedded: embedded, cache: cache)
            let read = await readSettings(role: "viewer", full: script.full, light: script.light, embedded: embedded, cache: cache)
            XCTAssertEqual(read.loaded.why, why)
            XCTAssertFalse(read.loaded.light); XCTAssertTrue(read.loaded.values.isEmpty); XCTAssertEqual(read.loaded.contract, embedded)
            XCTAssertNil(cache.etag); XCTAssertNil(cache.last)
        }
    }

    func testTheKeysOfTheCopyThatTheAnswerDoesNotHaveHaveNoValueAndNothingIsHidden() throws {
        let embedded = try embeddedCopy()
        let loaded = loadedFromLight(try read(body([("session_hours", item("12"))])), embedded: embedded)
        let minimum = try XCTUnwrap(embedded.settings.first { $0.key == "password_min_len" })
        XCTAssertNil(valueOf(minimum, loaded.values))
        XCTAssertEqual(loaded.contract.settings.count, embedded.settings.count)
    }

    // ---- the client, against a simulated server

    private func client(_ origin: String = "http://sim.test:18300") -> Eh3dApi {
        let api = Eh3dApi(origin: origin, token: "tok", settings: ConnectionSettings(retries: 0), session: LightSim.session())
        api.autoRefresh = false
        return api
    }

    private func apiError(_ work: () async throws -> Void) async -> ApiError? {
        do { try await work() } catch let error as ApiError { return error } catch {}
        return nil
    }

    func testTheClientAsksForTheLightViewWithTheLoginAndTheTagAndReadsTheTagBack() async throws {
        let text = good()
        LightSim.reset { hit in hit.ifNoneMatch == "\"abc\"" ? LightSim.Reply(status: 304, text: "") : LightSim.Reply(status: 200, text: text, headers: ["ETag": "\"abc\""]) }
        let api = client()
        let first = try await api.settingsValues(etag: nil)
        XCTAssertEqual(first, LightReply.fresh(text: text, etag: "\"abc\""))
        let second = try await api.settingsValues(etag: "\"abc\"")
        XCTAssertEqual(second, LightReply.notModified)
        let asked = LightSim.asked
        XCTAssertEqual(asked.map { $0.method + " " + $0.path + " " + $0.authorization }, ["GET /api/v1/settings/values Bearer tok", "GET /api/v1/settings/values Bearer tok"])
        XCTAssertEqual(asked.map { $0.ifNoneMatch }, [nil, "\"abc\""])
    }

    func testAWholeRoundOverTheWireGivesTheValuesThenKeepsThePageOnA304() async throws {
        let text = good()
        LightSim.reset { hit in hit.ifNoneMatch == "\"abc\"" ? LightSim.Reply(status: 304, text: "") : LightSim.Reply(status: 200, text: text, headers: ["ETag": "\"abc\""]) }
        let api = client()
        let cache = LightCache()
        let embedded = try embeddedCopy()
        let first = await readSettings(role: "operator", full: { try await api.settingsContract() }, light: { try await api.settingsValues(etag: $0) }, embedded: embedded, cache: cache)
        XCTAssertTrue(first.loaded.light); XCTAssertTrue(first.changed)
        XCTAssertEqual(first.loaded.values["session_hours"], SettingValue.int(12))
        let second = await readSettings(role: "operator", full: { try await api.settingsContract() }, light: { try await api.settingsValues(etag: $0) }, embedded: embedded, cache: cache)
        XCTAssertFalse(second.changed); XCTAssertEqual(second.loaded, first.loaded)
        XCTAssertEqual(LightSim.asked.map { $0.path }, ["/api/v1/settings/values", "/api/v1/settings/values"])
    }

    func testAnAnswerWithoutAnEtagIsReadWithNoTag() async throws {
        let text = good()
        LightSim.reset { _ in LightSim.Reply(status: 200, text: text) }
        let reply = try await client().settingsValues(etag: nil)
        XCTAssertEqual(reply, LightReply.fresh(text: text, etag: nil))
    }

    func testAnOldServerThatDoesNotKnowTheRouteIsARefusalWithItsStatusAndCode() async {
        LightSim.reset { _ in LightSim.Reply(status: 404, text: #"{"error":"not_found","detail":"no route"}"#) }
        let api = client()
        let error = await apiError { _ = try await api.settingsValues(etag: nil) }
        XCTAssertEqual(error?.status, 404); XCTAssertEqual(error?.code, "not_found")
    }

    func testARefusedLoginIsAnErrorAndTheClientForgetsTheToken() async {
        LightSim.reset { _ in LightSim.Reply(status: 401, text: #"{"error":"unauthorized","detail":"no login"}"#) }
        let api = client()
        let error = await apiError { _ = try await api.settingsValues(etag: nil) }
        XCTAssertEqual(error?.unauthorized, true); XCTAssertEqual(error?.code, "unauthorized")
        XCTAssertEqual(api.token, "")
    }

    func testAnAnswerLongerThanTheLimitIsNotKeptWhetherTheServerSaysItsLengthOrNot() async {
        let big = String(repeating: "x", count: lightMaxBytes + 500)
        for declared in [true, false] {
            LightSim.reset { _ in LightSim.Reply(status: 200, text: big, headers: declared ? ["Content-Length": String(big.utf8.count), "ETag": "\"big\""] : ["ETag": "\"big\""]) }
            let api = client()
            let error = await apiError { _ = try await api.settingsValues(etag: nil) }
            XCTAssertEqual(error?.code, "download_too_big", "declared \(declared)")
        }
    }

    func testAnAnswerOfExactlyTheLimitIsStillRead() async throws {
        let edge = String(repeating: "x", count: lightMaxBytes)
        LightSim.reset { _ in LightSim.Reply(status: 200, text: edge, headers: ["ETag": "\"edge\""]) }
        let reply = try await client().settingsValues(etag: nil)
        XCTAssertEqual(reply, LightReply.fresh(text: edge, etag: "\"edge\""))
    }

    func testATooBigAnswerOverTheWireEndsAsTheCopyWithTheReasonAndNoTag() async throws {
        let big = String(repeating: "x", count: lightMaxBytes + 1)
        LightSim.reset { _ in LightSim.Reply(status: 200, text: big, headers: ["ETag": "\"big\"", "Content-Length": String(big.utf8.count)]) }
        let api = client()
        let cache = LightCache()
        let read = await readSettings(role: "viewer", full: { try await api.settingsContract() }, light: { try await api.settingsValues(etag: $0) }, embedded: try embeddedCopy(), cache: cache)
        XCTAssertEqual(read.loaded.why, "download_too_big"); XCTAssertFalse(read.loaded.light); XCTAssertNil(cache.etag)
    }

    func testAServerThatIsNotThereIsTheCopyWithTheReasonUnreachable() async throws {
        LightSim.reset { _ in LightSim.Reply(status: 200, text: "{}") }
        LightSim.lock.lock(); LightSim.failure = URLError(.cannotConnectToHost); LightSim.lock.unlock()
        let api = client()
        let read = await readSettings(role: "viewer", full: { try await api.settingsContract() }, light: { try await api.settingsValues(etag: $0) }, embedded: try embeddedCopy(), cache: LightCache())
        XCTAssertEqual(read.loaded.why, "unreachable")
    }
}
