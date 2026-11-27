// EH3D-IOS-CONTROL - the orders that set a machine going: sent once, never from old data, and an order with no answer or a plan that comes back late are not taken for what they are not.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import XCTest
@testable import Eh3dCore

final class OrdersTests: XCTestCase {
    func testAnOrderIsNotSentAgainWhileOnItsWayNorAMomentAfterItWasTaken() {
        var gate = OrderGate()
        XCTAssertTrue(gate.take("answer a", nowMs: 10_000))
        XCTAssertFalse(gate.take("answer a", nowMs: 10_000))
        XCTAssertFalse(gate.take("answer a", nowMs: 70_000))
        gate.done("answer a", taken: true, nowMs: 70_000)
        XCTAssertFalse(gate.take("answer a", nowMs: 70_999))
        XCTAssertTrue(gate.take("answer a", nowMs: 71_000))
    }

    func testARefusedOrLostOrderIsFreeAtOnceAndAnotherJobIsNotHeld() {
        var gate = OrderGate()
        XCTAssertTrue(gate.take("start a", nowMs: 0))
        XCTAssertTrue(gate.take("start b", nowMs: 0))
        gate.done("start a", taken: false, nowMs: 0)
        XCTAssertTrue(gate.take("start a", nowMs: 0))
    }

    func testAnOrderWithNoAnswerMayHaveArrivedAndOneThatNeverLeftDidNot() {
        XCTAssertTrue(mayHaveArrived(status: 0, neverSent: false))
        XCTAssertTrue(mayHaveArrived(status: 502, neverSent: false))
        XCTAssertTrue(mayHaveArrived(status: 504, neverSent: false))
        XCTAssertFalse(mayHaveArrived(status: 0, neverSent: true))
        XCTAssertFalse(mayHaveArrived(status: 409, neverSent: false))
        XCTAssertFalse(mayHaveArrived(status: 500, neverSent: false))
    }

    func testNothingIsSetGoingFromOldDataOrByAViewer() {
        XCTAssertTrue(mayOrder(operator: true, link: .connected))
        for state in [LinkState.stale, .offline, .wrongServer] { XCTAssertFalse(mayOrder(operator: true, link: state)) }
        XCTAssertFalse(mayOrder(operator: false, link: .connected))
    }

    func testARefusedProgramKeepsTheLineAndTheReasonOfTheServer() {
        XCTAssertEqual(withDetail("No", code: "bad_gcode", detail: " line 3: a canned cycle "), "No (line 3: a canned cycle)")
        XCTAssertEqual(withDetail("No", code: "bad_gcode", detail: "bad_gcode"), "No")
        XCTAssertEqual(withDetail("No", code: "bad_gcode", detail: ""), "No")
    }

    func testAPlanAskedForOtherFilesIsNotTaken() {
        let asked = SideState(fileName: "a.ncd", text: "T1")
        var now = asked
        now.off = [1]
        XCTAssertTrue(Prepare.samePlanInput(asked, now))
        now.text = "T2"
        XCTAssertFalse(Prepare.samePlanInput(asked, now))
        XCTAssertFalse(Prepare.samePlanInput(asked, SideState(text: "T1", tableText: "x")))
        XCTAssertFalse(Prepare.samePlanInput(asked, SideState()))
    }
}
