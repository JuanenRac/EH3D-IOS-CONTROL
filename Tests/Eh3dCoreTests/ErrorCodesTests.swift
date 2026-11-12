import XCTest

/// Every refusal code of the catalog of the server has a text in the app, or a stated reason why it has none. The catalog is a copy of docs/error-codes.json of EH3D-SERVER.
/// The texts live in the app target, which the package does not build, so the sources are read as text, like the phrases of the screens.
final class ErrorCodesTests: XCTestCase {
    private let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    private var app: URL { folder.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App") }

    private func catalog() throws -> [String] {
        let data = try Data(contentsOf: folder.appendingPathComponent("Catalog").appendingPathComponent("error-codes.json"))
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        return rows.compactMap { $0["code"] as? String }
    }

    private func codes(in file: String, pattern: String) throws -> Set<String> {
        let text = try String(contentsOf: app.appendingPathComponent(file), encoding: .utf8)
        let expression = try NSRegularExpression(pattern: pattern)
        return Set(expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m in Range(m.range(at: 1), in: text).map { String(text[$0]) } })
    }

    /// The refusals of the files that the app does not send: the message of the server, which names the line or the field, is shown as it comes.
    private let showsTheMessage: Set<String> = [
        "bad_board", "bad_dcf", "bad_hole", "bad_ncd", "bad_path", "bad_picture", "bad_profile", "bad_samples", "bad_sorting", "bad_tool",
        "both_sources", "store", "too_many_holes", "unknown_tool",
        // the message of the server is shown as it comes: the phone never builds these requests itself
        "bad_rack", "not_supported", "plugin_failed", "too_many_clients",
    ]

    /// The codes of the artifacts, projects, tasks and uploads of the design programs: the control app never asks for any of them.
    private let neverAskedByThePhone: Set<String> = [
        "artifact_in_use", "bad_artifact", "bad_params", "bad_scope", "bad_share", "bad_template", "bad_upload", "blob_damaged", "engine_missing",
        "forbidden_scope", "hash_mismatch", "idempotency_conflict", "no_project", "queue_full", "quota", "shares_off", "stale_parent", "store_full",
        "task_active", "tasks_off", "unknown_artifact", "unknown_kind", "unknown_project", "unknown_task", "unknown_upload", "upload_conflict", "upload_incomplete",
        // the files of a project, the catalogs, the plugins, the design program and the switches of security: the phone has no page for them
        "bad_app", "bad_catalog", "bad_container", "bad_design_request", "bad_filename", "bad_plugin_request", "bad_policy", "catalog_readonly", "design_run_unavailable", "file_too_big", "locked", "not_locked", "precondition_failed", "precondition_required", "project_quota", "unknown_catalog", "unknown_file", "unknown_item", "unknown_plugin", "unknown_session", "unknown_version", "weak_confirm_required",
    ]

    func testEveryCodeOfTheCatalogHasATextOrAReason() throws {
        let own = try codes(in: "ErrorTexts.swift", pattern: #"case "([a-z0-9_]+)":"#)
        let model = try codes(in: "AppModel.swift", pattern: #"e\.code == "([a-z0-9_]+)""#)
        let left = try catalog().filter { !own.contains($0) && !model.contains($0) && !showsTheMessage.contains($0) && !neverAskedByThePhone.contains($0) }
        XCTAssertEqual(left, [], "a code of the server without a text in the app: add it to ErrorTexts or list it with its reason")
    }

    func testTheReasonsListOnlyCodesThatExist() throws {
        let known = Set(try catalog())
        XCTAssertEqual(showsTheMessage.union(neverAskedByThePhone).filter { !known.contains($0) }, [])
    }

    func testACodeHasOneKindOfAnswerOnly() throws {
        let own = try codes(in: "ErrorTexts.swift", pattern: #"case "([a-z0-9_]+)":"#)
        let model = try codes(in: "AppModel.swift", pattern: #"e\.code == "([a-z0-9_]+)""#)
        XCTAssertGreaterThan(own.count, 20)
        XCTAssertEqual(own.intersection(model), [])
        XCTAssertEqual(own.intersection(showsTheMessage.union(neverAskedByThePhone)), [])
    }
}
