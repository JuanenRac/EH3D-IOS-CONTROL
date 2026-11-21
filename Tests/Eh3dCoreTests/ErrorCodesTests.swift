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
        "hash_mismatch", "idempotency_conflict", "no_project", "queue_full", "quota", "shares_off", "stale_parent", "store_full",
        "task_active", "tasks_off", "unknown_artifact", "unknown_kind", "unknown_project", "unknown_task", "unknown_upload", "upload_conflict", "upload_incomplete",
        // the files of a project, the catalogs, the plugins, the design program and the switches of security: the phone has no page for them
        "bad_app", "bad_catalog", "bad_container", "bad_design_request", "bad_filename", "bad_plugin_request", "catalog_readonly", "design_run_unavailable", "file_too_big", "locked", "not_locked", "precondition_failed", "precondition_required", "project_quota", "unknown_catalog", "unknown_file", "unknown_item", "unknown_plugin", "unknown_session", "unknown_version",
    ]

    /// The codes the server added after the first copy of the catalog: the app tells them from the table of eight languages (Resources/server-errors.json), which ServerErrorsContractTests checks against the server.
    private let toldByTheTable: Set<String> = [
        "air_assist_off", "bad_axis", "bad_feed", "bad_gerber", "bad_heater", "bad_mesh",
        "bad_operation", "bad_placement_list", "bad_rules", "compat_off", "compat_write_off", "enclosure_open",
        "farm_no_free_printer", "focus_not_checked", "heater_timeout", "input_too_large", "jog_while_running", "laser_estop_latched",
        "laser_feed_limit", "laser_power_limit", "machine_alarm", "missing_layer", "out_of_travel", "pnp_feeder_short",
        "printer_disconnected", "printer_latched", "printer_untrusted", "program_over_limit", "sensor_fault", "slice_failed",
        "slice_limit", "slice_off", "temperature_over_limit", "test_fire_refused", "thermal_runaway", "unit_unknown",
        "authorization_required", "bad_bgcode", "bad_pnp_node", "bambu_lan_off", "bgcode_unsupported", "pnp_node_disabled",
        "pnp_node_exists", "pnp_node_not_ready", "pnp_nodes_full", "pnp_nodes_off", "stale_authorization", "unknown_pnp_node",
    ]

    func testEveryCodeOfTheCatalogHasATextOrAReason() throws {
        let own = try codes(in: "ErrorTexts.swift", pattern: #"case "([a-z0-9_]+)":"#)
        let model = try codes(in: "AppModel.swift", pattern: #"e\.code == "([a-z0-9_]+)""#)
        let left = try catalog().filter { !own.contains($0) && !model.contains($0) && !showsTheMessage.contains($0) && !neverAskedByThePhone.contains($0) && !toldByTheTable.contains($0) }
        XCTAssertEqual(left, [], "a code of the server without a text in the app: add it to ErrorTexts or list it with its reason")
    }

    func testTheRefusalsOfTheSettingsPageAreAnsweredByTheModel() throws {
        let model = try codes(in: "AppModel.swift", pattern: #"e\.code == "([a-z0-9_]+)""#)
        let known = Set(try catalog())
        for code in ["bad_policy", "weak_confirm_required", "forbidden_scope"] {
            XCTAssertTrue(model.contains(code), code)
            XCTAssertTrue(known.contains(code), code)
            XCTAssertFalse(neverAskedByThePhone.contains(code), code)
        }
    }

    func testTheReasonsListOnlyCodesThatExist() throws {
        let known = Set(try catalog())
        XCTAssertEqual(showsTheMessage.union(neverAskedByThePhone).union(toldByTheTable).filter { !known.contains($0) }, [])
    }

    func testTheCodesToldByTheTableAreInTheTableWithTheirEightTexts() throws {
        let file = folder.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/Eh3dCore/Resources/server-errors.json")
        let table = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: [String]])
        XCTAssertEqual(toldByTheTable.filter { table[$0]?.count != 8 }.sorted(), [])
    }

    func testACodeHasOneKindOfAnswerOnly() throws {
        let own = try codes(in: "ErrorTexts.swift", pattern: #"case "([a-z0-9_]+)":"#)
        let model = try codes(in: "AppModel.swift", pattern: #"e\.code == "([a-z0-9_]+)""#)
        XCTAssertGreaterThan(own.count, 20)
        XCTAssertEqual(own.intersection(model), [])
        XCTAssertEqual(own.intersection(showsTheMessage.union(neverAskedByThePhone).union(toldByTheTable)), [])
        XCTAssertEqual(model.intersection(toldByTheTable), [])
    }
}
