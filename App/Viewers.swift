// EH3D-IOS-CONTROL - the 2D and the 3D view of a job: the board, the holes and the paths as the machine does them, with what is done lit and the head where the server's report puts it.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI
import Eh3dCore

private func dashed(_ color: Color, _ width: CGFloat) -> (GraphicsContext.Shading, StrokeStyle) { (.color(color), StrokeStyle(lineWidth: width, dash: [8, 6])) }

/// The view from above: the board with its holes (a ring until it is drilled, filled after) and its paths (dim until the head has cut them), and the head.
struct JobView2D: View {
    let job: Job
    let itemsDone: Int
    let itemsTotal: Int
    let live: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: live ? 1.0 / 30 : 1.0, paused: !live)) { timeline in
            let ripple = live ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.5) / 1.5 : 0
            Canvas { ctx, size in draw(&ctx, size, ripple) }
        }
        .background(Forge.table)
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ ripple: Double) {
        let view = job.view
        let box = drawingBox(view)
        let plan = Plan(box: box, width: Double(size.width), height: Double(size.height))
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: plan.x(x), y: plan.y(y)) }
        // the table grid every 10 mm
        var gx = (box[0] / 10).rounded(.up) * 10
        while gx <= box[2] { var p = Path(); p.move(to: CGPoint(x: plan.x(gx), y: 0)); p.addLine(to: CGPoint(x: plan.x(gx), y: size.height)); ctx.stroke(p, with: .color(Forge.grid), lineWidth: 1); gx += 10 }
        var gy = (box[1] / 10).rounded(.up) * 10
        while gy <= box[3] { var p = Path(); p.move(to: CGPoint(x: 0, y: plan.y(gy))); p.addLine(to: CGPoint(x: size.width, y: plan.y(gy))); ctx.stroke(p, with: .color(Forge.grid), lineWidth: 1); gy += 10 }
        // the board, where the work is
        if let b = view.bounds {
            let r = CGRect(x: plan.x(b[0] - 2), y: plan.y(b[3] + 2), width: plan.x(b[2] + 2) - plan.x(b[0] - 2), height: plan.y(b[1] - 2) - plan.y(b[3] + 2))
            ctx.fill(Path(r), with: .color(Forge.board))
            ctx.stroke(Path(r), with: .color(Forge.amber.opacity(0.35)), lineWidth: 1.5)
        }
        // the paths: the part that is done is bright, the rest dim and dashed
        let reached = pointsReached(view, itemsDone: itemsDone, itemsTotal: itemsTotal)
        var counted = 0
        for path in view.paths {
            let color = Forge.tool(path.pen)
            for i in 1..<max(path.points.count, 1) {
                let a = path.points[i - 1], b = path.points[i]
                var p = Path(); p.move(to: pt(a.x, a.y)); p.addLine(to: pt(b.x, b.y))
                if counted + i <= reached { ctx.stroke(p, with: .color(color), lineWidth: 3) }
                else { ctx.stroke(p, with: .color(color.opacity(0.45)), style: StrokeStyle(lineWidth: 2, dash: [8, 6])) }
            }
            counted += path.points.count
        }
        // the holes
        let radius = max(2.6, plan.scale * 0.45)
        let done = holesDone(view, itemsDone: itemsDone)
        for (i, h) in view.holes.enumerated() {
            let c = Forge.tool(h.tool)
            let r = CGRect(x: plan.x(h.x) - radius, y: plan.y(h.y) - radius, width: radius * 2, height: radius * 2)
            if i < done { ctx.fill(Path(ellipseIn: r), with: .color(c)) } else { ctx.stroke(Path(ellipseIn: r), with: .color(c.opacity(0.85)), lineWidth: 1.6) }
        }
        // the head: a ring that breathes and a ripple that spreads while the machine works, and the cross
        if let spot = headSpot(view, itemsDone: itemsDone, itemsTotal: itemsTotal) {
            let at = pt(spot.x, spot.y)
            func circle(_ r: Double) -> Path { Path(ellipseIn: CGRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 2)) }
            ctx.stroke(circle(12 + 2 * ripple), with: .color(Forge.green), lineWidth: 2.5)
            if live { ctx.stroke(circle(12 + 30 * ripple), with: .color(Forge.green.opacity(0.55 * (1 - ripple))), lineWidth: 1.5) }
            var cross = Path(); cross.move(to: CGPoint(x: at.x - 22, y: at.y)); cross.addLine(to: CGPoint(x: at.x + 22, y: at.y)); cross.move(to: CGPoint(x: at.x, y: at.y - 22)); cross.addLine(to: CGPoint(x: at.x, y: at.y + 22))
            ctx.stroke(cross, with: .color(Forge.green), lineWidth: 1.5)
        }
    }
}

/// The isometric view: the board as a slab on the table, turned with a finger (a double tap puts it back), the spindle over the place where the head is.
struct JobView3D: View {
    let job: Job
    let itemsDone: Int
    let itemsTotal: Int
    let live: Bool
    @State private var yaw = 0.6
    @State private var pitch = 0.85
    @State private var dragStart: (Double, Double)?

    var body: some View {
        TimelineView(.animation(minimumInterval: live ? 1.0 / 30 : 1.0, paused: !live)) { timeline in
            let ripple = live ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.5) / 1.5 : 0
            Canvas { ctx, size in draw(&ctx, size, ripple) }
        }
        .background(Forge.table)
        .gesture(DragGesture().onChanged { g in
            if dragStart == nil { dragStart = (yaw, pitch) }
            let s = dragStart!
            yaw = s.0 + Double(g.translation.width) / 140
            pitch = min(max(s.1 - Double(g.translation.height) / 200, 0.25), 1.45)
        }.onEnded { _ in dragStart = nil })
        .onTapGesture(count: 2) { yaw = 0.6; pitch = 0.85 }
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ ripple: Double) {
        let view = job.view
        let box = drawingBox(view, marginMm: 6)
        let iso = Iso(cx: (box[0] + box[2]) / 2, cy: (box[1] + box[3]) / 2, yaw: yaw, pitch: pitch)
        let w = box[2] - box[0], d = box[3] - box[1]
        let zMax = 45.0
        let k = iso.fit(tableW: w, tableD: d, zMax: zMax, width: Double(size.width), height: Double(size.height)) * 0.98
        let mid = CGPoint(x: size.width / 2, y: size.height / 2 + CGFloat(zMax * k * 0.25))
        func p(_ x: Double, _ y: Double, _ z: Double = 0) -> CGPoint { let q = iso.project(x, y, z); return CGPoint(x: mid.x + CGFloat(q.sx * k), y: mid.y + CGFloat(q.sy * k)) }
        let thick = 1.6
        let corners = [(box[0], box[1]), (box[2], box[1]), (box[2], box[3]), (box[0], box[3])]
        for i in 0..<4 {
            let a = corners[i], b = corners[(i + 1) % 4]
            var side = Path(); side.move(to: p(a.0, a.1)); side.addLine(to: p(b.0, b.1)); side.addLine(to: p(b.0, b.1, thick)); side.addLine(to: p(a.0, a.1, thick)); side.closeSubpath()
            ctx.fill(side, with: .color(Color(red: 0.055, green: 0.09, blue: 0.063)))
            ctx.stroke(side, with: .color(Forge.amber.opacity(0.25)), lineWidth: 1)
        }
        var top = Path()
        for (i, c) in corners.enumerated() { if i == 0 { top.move(to: p(c.0, c.1, thick)) } else { top.addLine(to: p(c.0, c.1, thick)) } }
        top.closeSubpath()
        ctx.fill(top, with: .color(Forge.board))
        ctx.stroke(top, with: .color(Forge.amber.opacity(0.6)), lineWidth: 1.6)
        var gx = (box[0] / 10).rounded(.up) * 10
        while gx <= box[2] { var l = Path(); l.move(to: p(gx, box[1], thick)); l.addLine(to: p(gx, box[3], thick)); ctx.stroke(l, with: .color(Forge.grid), lineWidth: 1); gx += 10 }
        var gy = (box[1] / 10).rounded(.up) * 10
        while gy <= box[3] { var l = Path(); l.move(to: p(box[0], gy, thick)); l.addLine(to: p(box[2], gy, thick)); ctx.stroke(l, with: .color(Forge.grid), lineWidth: 1); gy += 10 }
        let reached = pointsReached(view, itemsDone: itemsDone, itemsTotal: itemsTotal)
        var counted = 0
        for path in view.paths {
            let color = Forge.tool(path.pen)
            for i in 1..<max(path.points.count, 1) {
                let a = path.points[i - 1], b = path.points[i]
                var l = Path(); l.move(to: p(a.x, a.y, thick)); l.addLine(to: p(b.x, b.y, thick))
                ctx.stroke(l, with: .color(counted + i <= reached ? color : color.opacity(0.5)), lineWidth: counted + i <= reached ? 3 : 2)
            }
            counted += path.points.count
        }
        let done = holesDone(view, itemsDone: itemsDone)
        for (i, h) in view.holes.enumerated() {
            let c = Forge.tool(h.tool), at = p(h.x, h.y, thick)
            let r = CGRect(x: at.x - 3.3, y: at.y - 3.3, width: 6.6, height: 6.6)
            if i < done { ctx.fill(Path(ellipseIn: r), with: .color(c)) } else { ctx.stroke(Path(ellipseIn: r), with: .color(c.opacity(0.85)), lineWidth: 1.4) }
        }
        if let spot = headSpot(view, itemsDone: itemsDone, itemsTotal: itemsTotal) {
            let foot = p(spot.x, spot.y, thick), tip = p(spot.x, spot.y, zMax), top2 = p(spot.x, spot.y, zMax + 18)
            var l = Path(); l.move(to: foot); l.addLine(to: tip); ctx.stroke(l, with: .color(Forge.green.opacity(0.9)), lineWidth: 4)
            var s = Path(); s.move(to: tip); s.addLine(to: top2); ctx.stroke(s, with: .color(Color(red: 0.56, green: 0.51, blue: 0.45)), lineWidth: 9)
            ctx.fill(Path(ellipseIn: CGRect(x: foot.x - 6, y: foot.y - 6, width: 12, height: 12)), with: .color(Forge.green))
            if live { let r = 8 + 26 * ripple; ctx.stroke(Path(ellipseIn: CGRect(x: foot.x - r, y: foot.y - r, width: r * 2, height: r * 2)), with: .color(Forge.green.opacity(0.6 * (1 - ripple))), lineWidth: 1.6) }
        }
    }
}
