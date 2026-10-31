import XCTest
@testable import Eh3dCore

final class GeometryTests: XCTestCase {
    private let drill = JobView(kind: "drill", name: "d", tools: [], holes: [Hole(tool: 1, x: 10, y: 10), Hole(tool: 1, x: 20, y: 10), Hole(tool: 1, x: 30, y: 20)], paths: [], bounds: [10, 10, 30, 20], items: 34, holeEnds: [14, 17, 24], estimateS: 28.8, travelMm: 10)
    private let route = JobView(kind: "route", name: "r", tools: [], holes: [], paths: [PathView(pen: 1, points: [Spot(x: 0, y: 0), Spot(x: 10, y: 0), Spot(x: 10, y: 10), Spot(x: 0, y: 10)])], bounds: [0, 0, 10, 10], items: 4, holeEnds: [], estimateS: 3, travelMm: 30)

    func testAHoleIsDoneWhenTheMachineHasReachedItsEndItem() {
        XCTAssertEqual(holesDone(drill, itemsDone: 0), 0)
        XCTAssertEqual(holesDone(drill, itemsDone: 13), 0)
        XCTAssertEqual(holesDone(drill, itemsDone: 14), 1)
        XCTAssertEqual(holesDone(drill, itemsDone: 20), 2)
        XCTAssertEqual(holesDone(drill, itemsDone: 34), 3)
    }

    func testTheHeadOfADrillingJobIsAtTheNextHoleAndAtTheLastWhenAllAreDone() {
        XCTAssertEqual(headSpot(drill, itemsDone: 0, itemsTotal: 34)?.x, 10)
        XCTAssertEqual(headSpot(drill, itemsDone: 14, itemsTotal: 34)?.x, 20)
        XCTAssertEqual(headSpot(drill, itemsDone: 34, itemsTotal: 34), Spot(x: 30, y: 20))
        XCTAssertNil(headSpot(.empty, itemsDone: 3, itemsTotal: 10))
    }

    func testTheHeadOfARoutingJobGoesAlongItsPathsInProportionToTheItemsDone() {
        XCTAssertEqual(headSpot(route, itemsDone: 0, itemsTotal: 4)?.x ?? -1, 0, accuracy: 1e-9)
        let third = headSpot(route, itemsDone: 1, itemsTotal: 3)!
        XCTAssertEqual(third.x, 10, accuracy: 1e-9); XCTAssertEqual(third.y, 0, accuracy: 1e-9)
        let half = headSpot(route, itemsDone: 3, itemsTotal: 6)!
        XCTAssertEqual(half.x, 10, accuracy: 1e-9); XCTAssertEqual(half.y, 5, accuracy: 1e-9)
        XCTAssertEqual(headSpot(route, itemsDone: 99, itemsTotal: 4)!.y, 10, accuracy: 1e-9)
    }

    func testThePointsReachedAreCountedAlongAllThePaths() {
        XCTAssertEqual(pointsReached(route, itemsDone: 0, itemsTotal: 4), 0)
        XCTAssertEqual(pointsReached(route, itemsDone: 2, itemsTotal: 4), 2)
        XCTAssertEqual(pointsReached(route, itemsDone: 40, itemsTotal: 4), 4)
        XCTAssertEqual(pointsReached(drill, itemsDone: 5, itemsTotal: 34), 0)
    }

    func testAJobWithNoWorkStillHasATableToDrawAndTheBoxHasAMargin() {
        let box = drawingBox(.empty)
        XCTAssertGreaterThan(box[2] - box[0], 100)
        XCTAssertEqual(drawingBox(drill, marginMm: 4), [6, 6, 34, 24])
    }

    func testAMillimetreBecomesAPointWithYGoingUpAndTheBoxCentred() {
        let plan = Plan(box: [0, 0, 100, 50], width: 200, height: 200)
        XCTAssertEqual(plan.scale, 2)
        XCTAssertEqual(plan.x(0), 0); XCTAssertEqual(plan.x(100), 200)
        XCTAssertEqual(plan.y(0), 150); XCTAssertEqual(plan.y(50), 50)
    }

    func testTheIsometricViewTurnsTheTableAndFitsItInTheCanvas() {
        let iso = Iso(cx: 50, cy: 25, yaw: 0, pitch: .pi / 2)
        XCTAssertEqual(iso.project(60, 25).sx, 10, accuracy: 1e-9)
        XCTAssertEqual(iso.project(50, 35).sy, -10, accuracy: 1e-9)
        XCTAssertEqual(iso.project(50, 25, 40).sy, 0, accuracy: 1e-9)
        let seen = Iso(cx: 50, cy: 25, yaw: 0.6, pitch: 0.85)
        let scale = seen.fit(tableW: 100, tableD: 50, zMax: 40, width: 400, height: 300)
        let pts = [(0.0, 0.0), (100.0, 0.0), (100.0, 50.0), (0.0, 50.0)].flatMap { [seen.project($0.0, $0.1, 0), seen.project($0.0, $0.1, 40)] }
        XCTAssertLessThanOrEqual(((pts.map(\.sx).max() ?? 0) - (pts.map(\.sx).min() ?? 0)) * scale, 400 - 24 + 0.01)
        XCTAssertLessThanOrEqual(((pts.map(\.sy).max() ?? 0) - (pts.map(\.sy).min() ?? 0)) * scale, 300 - 24 + 0.01)
    }

    func testATimeIsWrittenInTheLargestUnits() {
        XCTAssertEqual(formatDuration(45.2), "45 s")
        XCTAssertEqual(formatDuration(750), "12 min 30 s")
        XCTAssertEqual(formatDuration(3 * 3600 + 5 * 60 + 9), "3 h 05 min")
        XCTAssertEqual(formatDuration(-4), "0 s")
    }
}
