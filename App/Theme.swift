// EH3D-IOS-CONTROL - the Forge look of the EH3D programs: warm black, amber for what matters, orange for attention, green for what is well (the same as the Android app and the programs on the computer).
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI

enum Forge {
    static let background = Color(red: 0.059, green: 0.051, blue: 0.043)
    static let panel = Color(red: 0.090, green: 0.075, blue: 0.063)
    static let raised = Color(red: 0.133, green: 0.110, blue: 0.090)
    static let amber = Color(red: 1.0, green: 0.690, blue: 0.0)
    static let orange = Color(red: 1.0, green: 0.353, blue: 0.122)
    static let green = Color(red: 0.608, green: 0.890, blue: 0.290)
    static let blue = Color(red: 0.298, green: 0.788, blue: 0.941)
    static let danger = Color(red: 1.0, green: 0.329, blue: 0.439)
    static let text = Color(red: 0.957, green: 0.925, blue: 0.878)
    static let dim = Color(red: 0.612, green: 0.553, blue: 0.478)
    static let grid = Color(red: 0.169, green: 0.141, blue: 0.114)
    static let board = Color(red: 0.114, green: 0.169, blue: 0.122)
    static let table = Color(red: 0.078, green: 0.067, blue: 0.055)
    /// The colours of the tools, as the programs on the computer paint them.
    static let tools = [amber, green, blue, orange]
    static func tool(_ number: Int) -> Color { tools[((number - 1) % 4 + 4) % 4] }
}

struct Card<Content: View>: View {
    var accent: Color = Forge.amber
    let content: Content
    init(accent: Color = Forge.amber, @ViewBuilder _ content: () -> Content) { self.accent = accent; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Forge.panel, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.35), lineWidth: 1))
    }
}

struct Title: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text.uppercased()).font(.caption2.weight(.semibold)).tracking(1.2).foregroundColor(Forge.amber) }
}

struct Pill: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption2.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule()).overlay(Capsule().stroke(color.opacity(0.6), lineWidth: 1)).foregroundColor(color)
    }
}

/// A light that breathes slowly while `live` is true: the machine works and the screen is alive.
struct Light: View {
    let color: Color
    let live: Bool
    @State private var dim = false
    var body: some View {
        Circle().fill(color).frame(width: 10, height: 10).opacity(live && dim ? 0.45 : 1)
            .onAppear { if live { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { dim = true } } }
    }
}

struct ProgressBar: View {
    let percent: Int
    var color: Color = Forge.amber
    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Forge.grid)
                    Capsule().fill(color).frame(width: g.size.width * CGFloat(min(max(percent, 0), 100)) / 100).animation(.easeOut(duration: 0.4), value: percent)
                }
            }.frame(height: 8)
            Text("\(percent) %").font(.subheadline.weight(.semibold)).foregroundColor(Forge.text)
        }
    }
}

struct Tile: View {
    let value: String
    let name: String
    var color: Color = Forge.text
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.bold)).foregroundColor(color)
            Text(name).font(.caption).foregroundColor(Forge.dim)
        }
        .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
        .background(Forge.raised, in: RoundedRectangle(cornerRadius: 6))
    }
}
