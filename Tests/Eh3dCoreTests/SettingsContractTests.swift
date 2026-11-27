import XCTest
@testable import Eh3dCore

/// A server of the test that gives the contract of the settings and takes the writes of a key: the first write of a key without `confirm_weak` is asked again (409), the one with it is taken. It writes down
/// what it was asked. Tests of this file run one at a time.
private final class SettingsSim: URLProtocol {
    struct Seen: Equatable {
        let method: String
        let path: String
        let authorization: String
        let body: String
    }

    static let lock = NSLock()
    static var seen: [Seen] = []
    static var contract = ""

    static func reset(contract text: String) {
        lock.lock(); defer { lock.unlock() }
        seen = []
        contract = text
    }

    static var asked: [Seen] { lock.lock(); defer { lock.unlock() }; return seen }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SettingsSim.self]
        return URLSession(configuration: configuration)
    }

    private static func body(of request: URLRequest) -> String {
        if let data = request.httpBody { return String(decoding: data, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func answer(_ seen: Seen) -> (Int, String) {
        lock.lock(); defer { lock.unlock() }
        self.seen.append(seen)
        if seen.method == "GET" && seen.path == "/api/v1/settings/contract" { return (200, contract) }
        if seen.method == "PUT" && seen.path == "/api/v1/auth/policy" {
            if seen.body.contains("\"confirm_weak\"") { return (200, #"{"changed":{"key":"a","from":false,"to":true,"apply":"now","restart_required":false}}"#) }
            return (409, #"{"error":"weak_confirm_required","detail":"looser than recommended"}"#)
        }
        return (404, #"{"error":"not_found"}"#)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let seen = Seen(method: request.httpMethod ?? "GET", path: url.path, authorization: request.value(forHTTPHeaderField: "Authorization") ?? "", body: SettingsSim.body(of: request))
        let (status, text) = SettingsSim.answer(seen)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private struct Down: Error {}

/// The page of the settings of the server: the contract it is drawn from (the copy kept in the app and a small one made here), the groups, the control of each type, the default that can be restored, who may
/// write, what is checked before anything is sent, a secret that is never shown, the restart that is told, the refusal of the server by its code, the live contract against the copy, the texts in eight
/// languages and the client against a simulated server. The same cases as the Android app (SettingsContractTest). The copy is Resources/settings-contract.json, the file docs/settings-contract.json of EH3D-SERVER.
final class SettingsContractTests: XCTestCase {
    private let here = URL(fileURLWithPath: #filePath)
    private var repository: URL { here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private var resources: URL { repository.appendingPathComponent("Sources/Eh3dCore/Resources") }

    private func copyText() throws -> String { try String(contentsOf: resources.appendingPathComponent("settings-contract.json"), encoding: .utf8) }
    private func textsText() throws -> String { try String(contentsOf: resources.appendingPathComponent("settings-texts.json"), encoding: .utf8) }
    private func contractCopy() throws -> SettingsContract { try XCTUnwrap(parseContract(try copyText())) }

    private func words(_ text: String) -> String { contractLanguages.map { "\"\($0)\":\"\(text) \($0)\"" }.joined(separator: ",") }

    /// One setting of a small contract written here; `extra` is more members, written as JSON (`"min":1,"max":9`).
    private func entry(_ key: String, extra: String = "", group: String = "network", type: String = "boolean", defaultValue: String = "false", apply: String = "now",
                       write: String = #"{"via":"policy","method":"PUT","path":"/api/v1/auth/policy"}"#, role: String = "\"admin\"", secret: Bool = false, risk: String = "none") -> String {
        let more = extra.isEmpty ? "" : "," + extra
        return "{\"key\":\"\(key)\",\"group\":\"\(group)\",\"type\":\"\(type)\",\"default\":\(defaultValue),\"apply\":\"\(apply)\",\"write\":\(write),\"role\":\(role),\"scope\":\"admin:policy\","
            + "\"confirm_when_looser\":false,\"secret\":\(secret),\"risk\":\"\(risk)\",\"label\":{\(words("label"))},\"help\":{\(words("help"))},\"warning\":{\(words("warning"))}\(more)}"
    }

    private func contractOf(_ entries: String..., extra: String = "") -> String {
        "{\"schema\":\"eh3d.settings.contract/1\",\"languages\":[\"en\",\"es\",\"de\",\"fr\",\"it\",\"ja\",\"zh\",\"pt\"],"
            + "\"groups\":[{\"id\":\"network\",\"label\":{\(words("Network"))}},{\"id\":\"security\",\"label\":{\(words("Security"))}}],\"settings\":[\(entries.joined(separator: ","))]\(extra)}"
    }

    private func settings(_ entries: String...) throws -> [Setting] { try XCTUnwrap(parseContract(contractOf(entries.joined(separator: ",")))).settings }

    private func one(_ entry: String) throws -> Setting { try XCTUnwrap(try settings(entry).first) }

    private func number() throws -> Setting { try one(entry("n", extra: "\"min\":1,\"max\":9", type: "integer", defaultValue: "3")) }

    // ---- the copy of the app

    func testTheCopyIsTheContractOfTheServerWith106SettingsInSeventeenGroups() throws {
        let contract = try contractCopy()
        XCTAssertEqual(contract.schema, "eh3d.settings.contract/1")
        XCTAssertEqual(contract.settings.count, 106)
        XCTAssertEqual(contract.groups.count, 17)
        XCTAssertEqual(contract.languages, contractLanguages)
        XCTAssertEqual(Set(contract.settings.map { $0.key }).count, contract.settings.count)
    }

    func testTheSettingsOfTheStopAndTheResumeAreInTheCopyAndEveryUnitCanBeWritten() throws {
        let contract = try contractCopy()
        let keys = Set(contract.settings.map { $0.key })
        for key in ["grbl_stop_wait_s", "resume_safe_z_mm", "resume_spindle_wait_s", "resume_plunge_feed_mm_min", "resume_position_tolerance_um"] { XCTAssertTrue(keys.contains(key), key) }
        let written: Set<String> = ["", "days", "gigabytes", "hours", "kilobytes", "lines", "megabytes", "mm", "\u{00b5}m", "mm/min", "places", "seconds"]
        for s in contract.settings { XCTAssertTrue(written.contains(unitText(s.unit)), "\(s.key) \(s.unit ?? "")") }
        XCTAssertEqual(unitText("millimetres"), "mm")
        XCTAssertEqual(unitText("micrometres"), "\u{00b5}m")
        XCTAssertEqual(unitText(nil), "")
    }

    func testOnlyAResumeTheServerDoesNotDoByItselfKeepsItsReason() {
        XCTAssertEqual(resumeRefusal(status: 422, code: "bad_request", detail: " the stop was not confirmed "), "the stop was not confirmed")
        XCTAssertNil(resumeRefusal(status: 422, code: "bad_request", detail: "  "))
        XCTAssertNil(resumeRefusal(status: 422, code: "bad_request", detail: "bad_request"))
        XCTAssertNil(resumeRefusal(status: 422, code: "no_work", detail: "every hole is done"))
        XCTAssertNil(resumeRefusal(status: 409, code: "not_stopped", detail: "the job is running"))
    }

    func testEveryTextOfTheCopyIsInTheEightLanguages() throws {
        let contract = try contractCopy()
        for s in contract.settings {
            for (field, table) in [("label", s.label), ("help", s.help), ("warning", s.warning)] {
                for lang in contractLanguages { XCTAssertFalse((table[lang] ?? "").trimmingCharacters(in: .whitespaces).isEmpty, "\(s.key) \(field) \(lang)") }
            }
        }
        for g in contract.groups { for lang in contractLanguages { XCTAssertFalse((g.label[lang] ?? "").isEmpty, "group \(g.id) \(lang)") } }
    }

    func testTheNineteenKeysOfThePolicyHaveTheirRouteAndTheOthersAreSetInTheFile() throws {
        let contract = try contractCopy()
        let policy = contract.settings.filter { $0.write.via == "policy" }
        let file = contract.settings.filter { $0.write.via == "file" }
        XCTAssertEqual(policy.count, 19)
        XCTAssertEqual(file.count, 87)
        XCTAssertTrue(policy.allSatisfy { $0.write.method == "PUT" && writePath($0) == "/auth/policy" && $0.role == "admin" })
        XCTAssertTrue(file.allSatisfy { $0.write.path == nil && $0.write.file == "server.cfg" })
    }

    func testAnAdministratorCanChangeEveryKeyOfThePolicyAndNoKeyOfTheFile() throws {
        for s in try contractCopy().settings { XCTAssertEqual(canWriteSetting(role: "admin", s), s.write.via == "policy", s.key) }
    }

    func testTheCopyIsDrawnInItsSeventeenGroupsInOrder() throws {
        let contract = try contractCopy()
        let groups = groupSettings(contract)
        XCTAssertEqual(groups.map { $0.id }, contract.groups.map { $0.id })
        XCTAssertEqual(groups.reduce(0) { $0 + $1.settings.count }, contract.settings.count)
        XCTAssertTrue(groups.allSatisfy { g in g.settings.allSatisfy { $0.group == g.id } })
    }

    func testTheBundledCopyAndTextsAreTheOnesOfTheRepository() throws {
        XCTAssertEqual(try EmbeddedContract.bundledText(), try copyText())
        XCTAssertEqual(try SettingsTexts.bundledText(), try textsText())
        EmbeddedContract.ensureBundled()
        SettingsTexts.ensureBundled()
        XCTAssertTrue(EmbeddedContract.loaded)
        XCTAssertTrue(SettingsTexts.loaded)
        XCTAssertEqual(EmbeddedContract.get().settings.count, 106)
    }

    // ---- the groups

    func testASettingOfAGroupTheContractDoesNotListGoesIntoAGroupMadeFromItsIdAfterTheOthers() throws {
        let contract = try XCTUnwrap(parseContract(contractOf(entry("a"), entry("z", group: "future"))))
        let groups = groupSettings(contract)
        XCTAssertEqual(groups.map { $0.id }, ["network", "future"])
        XCTAssertEqual(groups.last?.label, ["en": "future"])
    }

    func testAGroupWithNoSettingsIsLeftOut() throws {
        let groups = groupSettings(try XCTUnwrap(parseContract(contractOf(entry("a")))))
        XCTAssertEqual(groups.map { $0.id }, ["network"])
    }

    // ---- the controls

    func testEachTypeIsDrawnWithItsControl() throws {
        let list = try settings(
            entry("on"), entry("n", extra: "\"min\":1,\"max\":9", type: "integer", defaultValue: "3"), entry("free", type: "integer"), entry("t", type: "string", defaultValue: "\"x\""),
            entry("l", type: "list", defaultValue: "[]"), entry("e", extra: "\"values\":[\"a\",\"b\"]", type: "enum", defaultValue: "\"a\""), entry("e2", type: "enum"), entry("odd", type: "float"))
        let kinds = Dictionary(uniqueKeysWithValues: list.map { ($0.key, controlKind($0)) })
        XCTAssertEqual(kinds, ["on": .toggle, "n": .number, "free": .text, "t": .text, "l": .list, "e": .select, "e2": .text, "odd": .generic])
        XCTAssertEqual(list.first { $0.key == "e" }?.choices, ["a", "b"])
    }

    func testEveryTypeOfTheCopyHasAControlTheAppKnows() throws {
        let contract = try contractCopy()
        XCTAssertTrue(contract.settings.allSatisfy { controlKind($0) != .generic })
        XCTAssertEqual(Set(contract.settings.map { $0.type }), ["boolean", "integer", "string", "list"])
    }

    func testARangeAnUnitAndADefaultAreKept() throws {
        let n = try one(entry("n", extra: "\"min\":1,\"max\":9,\"unit\":\"s\",\"max_length\":4,\"format\":\"address\"", type: "integer", defaultValue: "3"))
        XCTAssertEqual(n.min, 1); XCTAssertEqual(n.max, 9); XCTAssertEqual(n.unit, "s"); XCTAssertEqual(n.defaultValue, .int(3)); XCTAssertEqual(n.maxLength, 4); XCTAssertEqual(n.format, "address")
        XCTAssertEqual(n.confirmWhenLooser, false)
        XCTAssertEqual(n.scope, "admin:policy")
    }

    func testTheRiskOfSecurityExposureMachineAndDataNeedsTheSecondTouch() throws {
        for risk in ["security", "exposure", "machine", "data"] { XCTAssertTrue(isHighRisk(try one(entry("k", risk: risk))), risk) }
        XCTAssertFalse(isHighRisk(try one(entry("k", risk: "none"))))
        XCTAssertFalse(isHighRisk(try one(entry("k", risk: "capacity"))))
        XCTAssertTrue(try contractCopy().settings.contains { isHighRisk($0) })
    }

    // ---- restore, roles and secrets

    func testTheDefaultCanBeRestoredOnlyWhenItIsEditableDiffersAndThereIsOne() throws {
        let s = try number()
        XCTAssertTrue(canRestore(editable: true, s, current: .int(5)))
        XCTAssertFalse(canRestore(editable: true, s, current: .int(3)))
        XCTAssertFalse(canRestore(editable: false, s, current: .int(5)))
        XCTAssertFalse(canRestore(editable: true, s, current: nil))
        XCTAssertFalse(canRestore(editable: true, try one(entry("n", defaultValue: "null")), current: .bool(true)))
        XCTAssertFalse(canRestore(editable: true, try one(entry("p", type: "string", defaultValue: "\"\"", secret: true)), current: .text("x")))
    }

    func testARoleBelowTheOneTheContractAsksForSeesTheSettingReadOnly() throws {
        let s = try one(entry("a"))
        XCTAssertFalse(canWriteSetting(role: "viewer", s))
        XCTAssertFalse(canWriteSetting(role: "operator", s))
        XCTAssertTrue(canWriteSetting(role: "admin", s))
        XCTAssertFalse(canWriteSetting(role: "", s))
        XCTAssertTrue(canWriteSetting(role: "viewer", try one(entry("a", role: "null"))))
    }

    func testTheRolesAreOrdered() {
        XCTAssertTrue(roleAtLeast("admin", "viewer")); XCTAssertTrue(roleAtLeast("operator", "operator")); XCTAssertFalse(roleAtLeast("viewer", "operator"))
        XCTAssertFalse(roleAtLeast("stranger", "viewer")); XCTAssertFalse(roleAtLeast("admin", "stranger"))
    }

    func testAKeySetInTheFileAndAGenericOneAreNeverWritten() throws {
        let file = try one(entry("f", apply: "restart", write: #"{"via":"file","method":null,"path":null,"file":"server.cfg"}"#))
        XCTAssertFalse(canWriteSetting(role: "admin", file))
        XCTAssertFalse(canWriteSetting(role: "admin", try one(entry("odd", type: "float"))))
        XCTAssertFalse(canWriteSetting(role: "admin", genericSetting("whatever", .bool(true))))
    }

    func testASecretIsNeverShownNorWritten() async throws {
        let s = try one(entry("token_like", type: "string", defaultValue: "\"\"", secret: true))
        XCTAssertNil(valueOf(s, ["token_like": .text("hunter2")]))
        XCTAssertFalse(canWriteSetting(role: "admin", s))
        do {
            _ = try await saveSetting(send: { _, _, _ in "{}" }, s, value: .text("x"), confirmWeak: false)
            XCTFail("a secret is never written")
        } catch let error as ApiError { XCTAssertEqual(error.code, "not_writable") }
    }

    func testTheValueInForceIsTheLiveOneAndAKeyThatIsNotThereHasNone() throws {
        let s = try one(entry("a"))
        XCTAssertEqual(valueOf(s, ["a": .bool(true)]), .bool(true))
        XCTAssertNil(valueOf(s, [:]))
        XCTAssertNil(valueOf(s, ["other": .bool(true)]))
    }

    // ---- what is checked before anything is sent

    func testANumberIsCheckedAgainstItsRange() throws {
        let s = try number()
        XCTAssertEqual(parseTyped(s, " 5 "), .ok(.int(5)))
        XCTAssertEqual(parseTyped(s, "1"), .ok(.int(1)))
        XCTAssertEqual(parseTyped(s, "9"), .ok(.int(9)))
        for bad in ["0", "10", "-3", "x", "", "-", "1.5", "99999999999999999"] { XCTAssertEqual(parseTyped(s, bad), .bad(.number), bad) }
    }

    func testAnIntegerWithNoRangeIsStillAWholeNumber() throws {
        let s = try one(entry("free", type: "integer"))
        XCTAssertEqual(parseTyped(s, "42"), .ok(.int(42)))
        XCTAssertEqual(parseTyped(s, "4.2"), .bad(.number))
    }

    func testATextIsCheckedAgainstItsLength() throws {
        let s = try one(entry("t", extra: "\"max_length\":5", type: "string", defaultValue: "\"\""))
        XCTAssertEqual(parseTyped(s, "12345"), .ok(.text("12345")))
        XCTAssertEqual(parseTyped(s, "123456"), .bad(.text))
        XCTAssertEqual(parseTyped(s, ""), .ok(.text("")))
    }

    func testAChoiceMustBeOneOfTheOnesOffered() throws {
        let s = try one(entry("e", extra: "\"values\":[\"a\",\"b\"]", type: "enum", defaultValue: "\"a\""))
        XCTAssertEqual(parseTyped(s, "b"), .ok(.text("b")))
        XCTAssertEqual(parseTyped(s, "c"), .bad(.choice))
    }

    func testAListIsSplitAtTheCommasAndTheEmptyItemsDropped() throws {
        let s = try one(entry("l", type: "list", defaultValue: "[]"))
        XCTAssertEqual(parseTyped(s, " a, b c ,, d ,"), .ok(.list([.text("a"), .text("b c"), .text("d")])))
        XCTAssertEqual(parseTyped(s, " "), .ok(.list([])))
    }

    func testASwitchTakesNothingTyped() throws {
        XCTAssertEqual(parseTyped(try one(entry("a")), "true"), .bad(.text))
    }

    func testTheValuesAreSaidAsLines() {
        XCTAssertEqual(shownValue(nil), "")
        XCTAssertEqual(shownValue(.list([.text("a"), .int(2)])), "a, 2")
        XCTAssertEqual(shownValue(.int(5)), "5")
        XCTAssertEqual(shownValue(.bool(true)), "true")
        XCTAssertEqual(shownValue(.bool(false)), "false")
        XCTAssertEqual(shownValue(.double(2.5)), "2.5")
        XCTAssertEqual(shownValue(.text("x")), "x")
    }

    func testJsonValuesBecomePlainData() throws {
        let live = try XCTUnwrap(parseLiveContract(contractOf(entry("a"), extra: #","values":{"b":true,"i":5,"d":2.5,"t":"x","l":["p","q"],"n":null}"#)))
        XCTAssertEqual(live.values, ["b": .bool(true), "i": .int(5), "d": .double(2.5), "t": .text("x"), "l": .list([.text("p"), .text("q")])])
    }

    func testAValueThatIsAnObjectIsKeptAsTextAndANumberWithDecimalsStaysANumber() throws {
        let live = try XCTUnwrap(parseLiveContract(contractOf(entry("a"), extra: #","values":{"o":{"x":1},"f":2.5}"#)))
        guard case .text(_)? = live.values["o"] else { return XCTFail("an object is kept as text") }
        XCTAssertEqual(live.values["f"], .double(2.5))
    }

    // ---- the write

    func testTheBodyCarriesTheKeyTheValueAndThePermissionToBeLooserOnlyWhenGiven() throws {
        let s = try one(entry("a"))
        XCTAssertEqual(writeBody(s, .bool(true), confirmWeak: false), #"{"key":"a","value":true}"#)
        XCTAssertEqual(writeBody(s, .bool(true), confirmWeak: true), #"{"confirm_weak":true,"key":"a","value":true}"#)
        XCTAssertEqual(writeBody(s, .int(7), confirmWeak: false), #"{"key":"a","value":7}"#)
        XCTAssertEqual(writeBody(s, .list([.text("x"), .text("y")]), confirmWeak: false), #"{"key":"a","value":["x","y"]}"#)
        XCTAssertEqual(writeBody(s, .text("a/b"), confirmWeak: false), #"{"key":"a","value":"a/b"}"#)
        XCTAssertEqual(writeBody(s, .double(2.5), confirmWeak: false), #"{"key":"a","value":2.5}"#)
    }

    func testAChangeIsSentByTheMethodAndTheRouteOfItsEntry() async throws {
        let s = try one(entry("a"))
        var sent: [[String]] = []
        let result = try await saveSetting(send: { method, path, body in sent.append([method, path, body]); return #"{"changed":{"key":"a","restart_required":false}}"# }, s, value: .bool(true), confirmWeak: false)
        XCTAssertEqual(result, .saved(restartRequired: false))
        XCTAssertEqual(sent, [["PUT", "/auth/policy", #"{"key":"a","value":true}"#]])
    }

    func testTheRestartIsToldFromTheAnswerAndElseFromTheContract() throws {
        let now = try one(entry("a"))
        let later = try one(entry("b", apply: "restart"))
        XCTAssertTrue(restartRequired(#"{"changed":{"restart_required":true}}"#, now))
        XCTAssertFalse(restartRequired(#"{"changed":{"restart_required":false}}"#, later))
        XCTAssertTrue(restartRequired("{}", later))
        XCTAssertFalse(restartRequired("{}", now))
        XCTAssertTrue(restartRequired("not json", later))
    }

    func testTheServerAskingForConfirmationIsAskedAgainAndNothingIsSentTwiceByItself() async throws {
        let s = try one(entry("a", risk: "security"))
        var calls = 0
        let result = try await saveSetting(send: { _, _, _ in calls += 1; throw ApiError(status: 409, code: "weak_confirm_required", detail: "looser") }, s, value: .bool(false), confirmWeak: false)
        XCTAssertEqual(result, .needsWeakConfirm)
        XCTAssertEqual(calls, 1)
    }

    func testARefusalComesBackWithItsCodeAndStatus() async throws {
        let s = try one(entry("a"))
        for (status, code) in [(422, "bad_policy"), (403, "forbidden"), (403, "forbidden_scope"), (401, "unauthorized"), (500, "internal")] {
            let result = try await saveSetting(send: { _, _, _ in throw ApiError(status: status, code: code, detail: "detail of \(code)") }, s, value: .bool(true), confirmWeak: false)
            XCTAssertEqual(result, .refused(ApiError(status: status, code: code, detail: "detail of \(code)")))
        }
    }

    func testAServerOutOfReachIsARefusalWithNoStatus() async throws {
        let s = try one(entry("a"))
        let result = try await saveSetting(send: { _, _, _ in throw ApiError(status: 0, code: "unreachable", detail: "no answer") }, s, value: .bool(true), confirmWeak: false)
        guard case .refused(let error) = result else { return XCTFail("a refusal") }
        XCTAssertEqual(error.status, 0)
    }

    func testAFailureThatIsNotOfTheServerIsPassedOn() async throws {
        let s = try one(entry("a"))
        do {
            _ = try await saveSetting(send: { _, _, _ in throw Down() }, s, value: .bool(true), confirmWeak: false)
            XCTFail("it is passed on")
        } catch is Down {}
    }

    // ---- the live contract and the copy

    private func live() -> String {
        contractOf(entry("a"), entry("n", extra: "\"min\":1,\"max\":9", type: "integer", defaultValue: "3"), extra: #","values":{"a":true,"n":5,"extra":"x"},"server_version":"0.2.0""#)
    }

    func testTheLiveContractCarriesTheValuesAndTheVersionOfTheServer() async throws {
        let embedded = try contractCopy()
        let text = live()
        let loaded = await loadContract(read: { text }, embedded: embedded)
        XCTAssertTrue(loaded.live)
        XCTAssertNil(loaded.why)
        XCTAssertEqual(loaded.serverVersion, "0.2.0")
        XCTAssertEqual(loaded.values, ["a": .bool(true), "n": .int(5), "extra": .text("x")])
        XCTAssertEqual(loaded.contract.settings.count, 2)
    }

    func testAKeyTheServerReportsAndTheContractDoesNotListIsDrawnReadOnly() throws {
        let loaded = try XCTUnwrap(parseLiveContract(live()))
        let unlisted = unlistedSettings(loaded.contract, loaded.values)
        XCTAssertEqual(unlisted.map { $0.key }, ["extra"])
        XCTAssertFalse(canWriteSetting(role: "admin", unlisted[0]))
        XCTAssertEqual(valueOf(unlisted[0], loaded.values), .text("x"))
        XCTAssertEqual(genericSetting("k", .bool(true)).type, "boolean")
        XCTAssertEqual(genericSetting("k", .int(1)).type, "integer")
        XCTAssertEqual(genericSetting("k", nil).type, "unknown")
    }

    func testTheCopyIsUsedReadOnlyWhenTheServerRefusesAnOrdinaryUser() async throws {
        let embedded = try contractCopy()
        let loaded = await loadContract(read: { throw ApiError(status: 403, code: "forbidden", detail: "no") }, embedded: embedded)
        XCTAssertFalse(loaded.live)
        XCTAssertEqual(loaded.why, "forbidden")
        XCTAssertTrue(loaded.values.isEmpty)
        XCTAssertNil(loaded.serverVersion)
        XCTAssertEqual(loaded.contract, embedded)
    }

    func testTheCopyIsUsedWhenTheServerIsOutOfReachOrAnswersWhatIsNotAContract() async throws {
        let embedded = try contractCopy()
        let other = contractOf(entry("a")).replacingOccurrences(of: "eh3d.settings.contract/1", with: "eh3d.settings.contract/9")
        let down = await loadContract(read: { throw Down() }, embedded: embedded)
        let refused = await loadContract(read: { throw ApiError(status: 0, code: "unreachable", detail: "down") }, embedded: embedded)
        let schema = await loadContract(read: { #"{"schema":"other"}"# }, embedded: embedded)
        let list = await loadContract(read: { "[]" }, embedded: embedded)
        let future = await loadContract(read: { other }, embedded: embedded)
        XCTAssertEqual([down.why, refused.why, schema.why, list.why, future.why], ["unreachable", "unreachable", "shape", "shape", "shape"])
    }

    func testADocumentThatIsNotAContractIsRefused() throws {
        XCTAssertNil(parseContract("not json"))
        XCTAssertNil(parseContract(#"{"schema":"eh3d.settings.contract/1","groups":[]}"#))
        XCTAssertNil(parseContract(#"{"schema":"eh3d.settings.contract/1","groups":[],"settings":[{"key":"a"}]}"#))
        XCTAssertNil(parseContract(#"{"schema":"eh3d.settings.contract/1","groups":[],"settings":[{"write":{}}]}"#))
        XCTAssertNotNil(parseContract(contractOf(entry("a"))))
    }

    // ---- the texts

    func testATextIsInTheLanguageOfThePersonThenItsMainLanguageThenEnglish() {
        let map = ["en": "house", "es": "casa", "pt": "casa PT"]
        XCTAssertEqual(contractText(map, "es"), "casa")
        XCTAssertEqual(contractText(map, "pt-br"), "casa PT")
        XCTAssertEqual(contractText(map, "nl"), "house")
        XCTAssertEqual(contractText(["es": "casa"], "de"), "casa")
        XCTAssertEqual(contractText([:], "en"), "")
        XCTAssertEqual(contractText(["en": "house", "es": " "], "es"), "house")
    }

    func testEverySentenceOfThePageIsInTheEightLanguagesWithTheSameHoles() throws {
        let table = try SettingsTexts.parse(try textsText())
        let hole = try NSRegularExpression(pattern: #"\{[a-z_]+\}"#)
        func holes(_ text: String) -> [String] { hole.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }.sorted() }
        XCTAssertGreaterThanOrEqual(table.count, 30)
        for (key, row) in table {
            XCTAssertEqual(Set(row.keys), Set(contractLanguages), key)
            for lang in contractLanguages {
                XCTAssertFalse((row[lang] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(key) \(lang)")
                XCTAssertEqual(holes(row[lang] ?? ""), holes(row["en"] ?? ""), "\(key) \(lang)")
            }
        }
    }

    func testEverySentenceTheScreenAsksForIsInTheTable() throws {
        try SettingsTexts.install(try textsText())
        let app = repository.appendingPathComponent("App")
        let expression = try NSRegularExpression(pattern: #""(ssc_[a-z_]+)""#)
        var used = Set<String>()
        for name in try FileManager.default.contentsOfDirectory(atPath: app.path) where name.hasSuffix(".swift") {
            let text = try String(contentsOf: app.appendingPathComponent(name), encoding: .utf8)
            for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) { if let range = Range(match.range(at: 1), in: text) { used.insert(String(text[range])) } }
        }
        XCTAssertGreaterThanOrEqual(used.count, 20)
        XCTAssertEqual(used.filter { !SettingsTexts.keys().contains($0) }, [])
    }

    func testASentenceIsInTheLanguageOfTheAppAndFillsItsHolesAndOtherLanguagesReadEnglish() throws {
        try SettingsTexts.install(try textsText())
        XCTAssertEqual(SettingsTexts.text("ssc_live", language: "en", vars: ["v": "0.2.0"]), "Contract read from the server 0.2.0.")
        XCTAssertEqual(SettingsTexts.text("ssc_live", language: "pt", vars: ["v": "0.2.0"]), "Contrato lido do servidor 0.2.0.")
        XCTAssertEqual(SettingsTexts.text("ssc_live", language: "pt-br", vars: ["v": "0.2.0"]), "Contrato lido do servidor 0.2.0.")
        XCTAssertEqual(SettingsTexts.text("ssc_live", language: "nl", vars: ["v": "0.2.0"]), "Contract read from the server 0.2.0.")
        XCTAssertEqual(SettingsTexts.text("ssc_nothing", language: "en"), "ssc_nothing")
    }

    func testATableThatIsNotJsonThrowsAndLeavesTheOneThatWasThere() throws {
        try SettingsTexts.install(try textsText())
        XCTAssertThrowsError(try SettingsTexts.install("not json"))
        XCTAssertTrue(SettingsTexts.loaded)
        XCTAssertFalse(SettingsTexts.keys().isEmpty)
    }

    // ---- the client, against a simulated server

    func testTheClientReadsTheContractAndWritesAKeyByTheRouteOfTheContract() async throws {
        SettingsSim.reset(contract: live())
        let api = Eh3dApi(origin: "http://sim.test:18200", token: "tok", settings: ConnectionSettings(retries: 0), session: SettingsSim.session())
        api.autoRefresh = false
        let embedded = try contractCopy()
        let loaded = await loadContract(read: { try await api.settingsContract() }, embedded: embedded)
        XCTAssertTrue(loaded.live)
        let s = try XCTUnwrap(loaded.contract.settings.first { $0.key == "a" })
        let first = try await saveSetting(send: { m, p, b in try await api.writeSetting(method: m, path: p, body: b) }, s, value: .bool(true), confirmWeak: false)
        XCTAssertEqual(first, .needsWeakConfirm)
        let second = try await saveSetting(send: { m, p, b in try await api.writeSetting(method: m, path: p, body: b) }, s, value: .bool(true), confirmWeak: true)
        XCTAssertEqual(second, .saved(restartRequired: false))
        let asked = SettingsSim.asked
        XCTAssertEqual(asked.map { $0.method + " " + $0.path + " " + $0.authorization }, ["GET /api/v1/settings/contract Bearer tok", "PUT /api/v1/auth/policy Bearer tok", "PUT /api/v1/auth/policy Bearer tok"])
        XCTAssertEqual(asked[1].body, #"{"key":"a","value":true}"#)
        XCTAssertEqual(asked[2].body, #"{"confirm_weak":true,"key":"a","value":true}"#)
    }
}
