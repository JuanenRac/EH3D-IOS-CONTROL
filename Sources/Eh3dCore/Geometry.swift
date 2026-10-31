// EH3D-IOS-CONTROL - the drawing of a job: where the head is, how a millimetre becomes a point of the screen, and the isometric view. Plain arithmetic, the same as the Android app.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

/// A place on the table, in mm.
public struct Spot: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// How many holes are finished when the machine has run `itemsDone` items: the holes whose end item has been reached.
public func holesDone(_ view: JobView, itemsDone: Int) -> Int { view.holeEnds.filter { $0 <= itemsDone }.count }

/// Where the head is, as far as the items done tell: the next hole of a drilling job, or along the paths of a routing job in proportion to the items done. An estimate between two reports of the server.
public func headSpot(_ view: JobView, itemsDone: Int, itemsTotal: Int) -> Spot? {
    if view.kind == "drill" || (!view.holes.isEmpty && view.paths.isEmpty) {
        if view.holes.isEmpty { return nil }
        let h = view.holes[min(holesDone(view, itemsDone: itemsDone), view.holes.count - 1)]
        return Spot(x: h.x, y: h.y)
    }
    let points = view.paths.flatMap { $0.points }
    guard let first = points.first else { return nil }
    let total = itemsTotal > 0 ? itemsTotal : view.items
    if total <= 0 { return first }
    let at = Double(min(max(itemsDone, 0), total)) / Double(total) * Double(points.count - 1)
    let i = min(Int(at), points.count - 1)
    let j = min(i + 1, points.count - 1)
    let f = at - Double(i)
    return Spot(x: points[i].x + (points[j].x - points[i].x) * f, y: points[i].y + (points[j].y - points[i].y) * f)
}

/// How many of the points of the paths (counted along all of them) the machine has reached.
public func pointsReached(_ view: JobView, itemsDone: Int, itemsTotal: Int) -> Int {
    let total = view.paths.reduce(0) { $0 + $1.points.count }
    let items = itemsTotal > 0 ? itemsTotal : view.items
    if total == 0 || items <= 0 { return 0 }
    return Int(Int64(min(max(itemsDone, 0), items)) * Int64(total) / Int64(items))
}

/// The box a drawing fits in, with a margin; a job with no work gets a 100 x 80 mm table so that there is something to draw.
public func drawingBox(_ view: JobView, marginMm: Double = 4) -> [Double] {
    let b = view.bounds ?? [0, 0, 100, 80]
    let w = max(b[2] - b[0], 1), h = max(b[3] - b[1], 1)
    return [b[0] - marginMm, b[1] - marginMm, b[0] + w + marginMm, b[1] + h + marginMm]
}

/// The scale and the corner that put a box of mm into a canvas of `width` x `height` points, centred, with Y going up as on the machine.
public struct Plan {
    private let box: [Double]
    public let scale: Double
    private let offsetX: Double, bottom: Double
    public init(box: [Double], width: Double, height: Double) {
        self.box = box
        scale = min(width / (box[2] - box[0]), height / (box[3] - box[1]))
        offsetX = (width - scale * (box[2] - box[0])) / 2
        bottom = height - (height - scale * (box[3] - box[1])) / 2
    }
    public func x(_ mm: Double) -> Double { offsetX + scale * (mm - box[0]) }
    public func y(_ mm: Double) -> Double { bottom - scale * (mm - box[1]) }
}

/// A point of the isometric view: the horizontal and vertical place on the screen, and the depth.
public struct IsoPoint: Equatable { public let sx: Double; public let sy: Double; public let depth: Double }

/// The isometric view: the table is turned by `yaw` (radians) around its centre and seen from `pitch` above the horizon; `z` is the height above the table in mm.
public struct Iso {
    private let cx: Double, cy: Double
    public let yaw: Double, pitch: Double
    public init(cx: Double, cy: Double, yaw: Double, pitch: Double) { self.cx = cx; self.cy = cy; self.yaw = yaw; self.pitch = pitch }

    public func project(_ x: Double, _ y: Double, _ z: Double = 0) -> IsoPoint {
        let dx = x - cx, dy = y - cy
        let rx = dx * cos(yaw) - dy * sin(yaw)
        let ry = dx * sin(yaw) + dy * cos(yaw)
        return IsoPoint(sx: rx, sy: -(ry * sin(pitch) + z * cos(pitch)), depth: ry)
    }

    /// The scale that makes the whole table of `tableW` x `tableD` mm (and a head of `zMax` mm over it) fit in a canvas.
    public func fit(tableW: Double, tableD: Double, zMax: Double, width: Double, height: Double, marginPx: Double = 12) -> Double {
        let corners = [(0.0, 0.0), (tableW, 0.0), (tableW, tableD), (0.0, tableD)].flatMap { [project($0.0, $0.1, 0), project($0.0, $0.1, zMax)] }
        let w = (corners.map(\.sx).max() ?? 0) - (corners.map(\.sx).min() ?? 0)
        let h = (corners.map(\.sy).max() ?? 0) - (corners.map(\.sy).min() ?? 0)
        return min((width - 2 * marginPx) / max(w, 1), (height - 2 * marginPx) / max(h, 1))
    }
}

/// A time as the machines show it: 3 h 05 min, 12 min 30 s or 45 s.
public func formatDuration(_ seconds: Double) -> String {
    let s = max(Int(seconds), 0)
    if s >= 3600 { return String(format: "%d h %02d min", s / 3600, (s % 3600) / 60) }
    if s >= 60 { return String(format: "%d min %02d s", s / 60, s % 60) }
    return "\(s) s"
}
