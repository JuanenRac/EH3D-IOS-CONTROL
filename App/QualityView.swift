// EH3D-IOS-CONTROL - the ring of LEDs around the camera of the drill head and the quality check of the work (the same as the Android app): the camera looks at the board after the job, the
// analyser of the shop (in the server, the same one the desktop program uses) judges the holes and the milled channels, and the verdict is shown big: correct, not correct, or cannot judge when the
// picture was too poor. The ring of LEDs says the same in colour on the head.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI
import Eh3dCore

/// The levels of the ring that the screen offers; 0 turns it off (or, for the picture, leaves it as it is).
let lightLevels = [0, 30, 60, 80]

/// The widths of the hole of the job in the centre of the picture that the screen offers (0 is none), from the tools of a Bungard machine.
let holeWidths: [Double] = [0, 0.6, 0.8, 1.0, 1.2]

/// A choice among a few: filled when it is the one in use.
private struct Choice: View {
    let selected: Bool
    let label: String
    var enabled = true
    let action: () -> Void
    var body: some View {
        Group {
            if selected { Button(action: action) { Text(label).lineLimit(1).frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent) }
            else { Button(action: action) { Text(label).lineLimit(1).frame(maxWidth: .infinity) }.buttonStyle(.bordered) }
        }.disabled(!enabled)
    }
}

/// The ring of LEDs: off and three levels. It is lit in the white of the camera.
struct LightRow: View {
    @ObservedObject var model: AppModel
    let machineId: String
    let head: HeadStatus
    var body: some View {
        if !head.light {
            Text(model.tr("Este nodo no tiene aro de luz.")).font(.caption).foregroundColor(Forge.dim)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.tr("Aro de luz") + ": " + (head.lightOn ? "\(head.lightLevel) %" : model.tr("apagado"))).foregroundColor(Forge.text)
                HStack(spacing: 8) {
                    ForEach(lightLevels, id: \.self) { level in
                        Choice(selected: level == 0 ? !head.lightOn : (head.lightOn && head.lightLevel == level), label: level == 0 ? model.tr("Apagar") : "\(level) %", enabled: model.canOperate) { model.setLight(machineId, level: level) }
                    }
                }
            }
        }
    }
}

/// What a finding of the analyser says, in the language of the app.
func findingText(_ model: AppModel, _ f: Finding) -> String {
    let words: String
    switch f.code {
    case "hole_missing": words = model.tr("no hay agujero")
    case "hole_wrong_size": words = model.tr("tamaño incorrecto")
    case "hole_off_centre": words = model.tr("descentrado")
    case "hole_not_round": words = model.tr("no es redondo")
    case "hole_debris": words = model.tr("rebabas o polvo alrededor")
    case "hole_out_of_view": words = model.tr("fuera de la imagen")
    case "mill_no_channels": words = model.tr("no se ven canales")
    case "mill_too_narrow": words = model.tr("canales demasiado estrechos")
    case "mill_too_wide": words = model.tr("canales demasiado anchos")
    case "mill_pinched": words = model.tr("un canal se estrecha: riesgo de cortocircuito")
    case "mill_uneven": words = model.tr("canales irregulares")
    case "image_too_dark": words = model.tr("foto demasiado oscura: más luz")
    case "image_too_bright": words = model.tr("foto demasiado clara: menos luz")
    case "image_low_contrast": words = model.tr("foto sin contraste")
    case "image_blurry": words = model.tr("foto desenfocada")
    case "not_calibrated": words = model.tr("fija antes la escala")
    case "nothing_to_check": words = model.tr("no hay ninguna comprobación activa")
    case "no_expected_holes": words = model.tr("ningún agujero del trabajo a la vista")
    default: words = f.code
    }
    if let hole = f.hole { return "#\(hole + 1): \(words)" }
    return words
}

/// The verdict, as large as a sign: it is read from across the workshop.
private struct VerdictBadge: View {
    @ObservedObject var model: AppModel
    let quality: Quality?
    let busy: Bool
    var body: some View {
        let (color, word): (Color, String) = {
            if busy { return (Forge.raised, model.tr("Verificando…")) }
            guard let q = quality else { return (Forge.raised, model.tr("Aún sin verificar")) }
            switch q.verdict {
            case "ok": return (Forge.green, model.tr("CORRECTO"))
            case "not_ok": return (Forge.danger, model.tr("NO CORRECTO"))
            default: return (Forge.orange, model.tr("NO SE PUEDE JUZGAR"))
            }
        }()
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(color)
            if busy { ProgressView().tint(Forge.amber) }
            else { Text(word).font(.system(size: word.count > 12 ? 22 : 32, weight: .black)).multilineTextAlignment(.center).foregroundColor(quality == nil ? Forge.dim : .white) }
        }.frame(maxWidth: .infinity).frame(height: 96)
    }
}

struct QualityCard: View {
    @ObservedObject var model: AppModel
    let machineId: String
    @State private var light = 2
    @State private var hole = 2

    var body: some View {
        let q = model.quality
        let busy = model.qualityBusy
        Card(accent: Forge.amber) {
            Title(model.tr("Verificación de calidad"))
            VerdictBadge(model: model, quality: q, busy: busy)
            if let q = q, !busy {
                if q.holesTotal > 0 { Text("\(q.holesOk)/\(q.holesTotal) " + model.tr("agujeros bien")).font(.headline).foregroundColor(q.holesOk == q.holesTotal ? Forge.green : Forge.danger) }
                if let width = q.channelMm { Text(model.tr("ancho de canal") + " " + String(format: "%.2f mm", width)).foregroundColor(Forge.text) }
                ForEach(Array(q.findings.prefix(6).enumerated()), id: \.offset) { _, f in
                    Text(findingText(model, f)).font(.subheadline).foregroundColor(f.fails ? Forge.danger : Forge.orange)
                }
            }
            Text(model.tr("Luz para la foto")).font(.caption).foregroundColor(Forge.dim)
            HStack(spacing: 8) {
                ForEach(Array(lightLevels.enumerated()), id: \.offset) { i, level in
                    Choice(selected: light == i, label: level == 0 ? model.tr("Como está") : "\(level) %") { light = i }
                }
            }
            Text(model.tr("Agujero en el centro (mm)")).font(.caption).foregroundColor(Forge.dim)
            HStack(spacing: 6) {
                ForEach(Array(holeWidths.enumerated()), id: \.offset) { i, width in
                    Choice(selected: hole == i, label: width == 0 ? model.tr("ninguno") : String(format: "%.1f", width)) { hole = i }
                }
            }
            Text(model.tr("Perfil del analizador")).font(.caption).foregroundColor(Forge.dim)
            HStack(spacing: 8) {
                ForEach(Array([model.tr("Estándar"), model.tr("Paso fino"), model.tr("Prototipo")].enumerated()), id: \.offset) { i, name in
                    Button { model.inspectPreset(machineId, index: i) } label: { Text(name).lineLimit(1).frame(maxWidth: .infinity) }.buttonStyle(.bordered).disabled(!model.canOperate || busy)
                }
            }
            Button { model.inspect(machineId, light: lightLevels[light], holeMm: holeWidths[hole]) } label: {
                Text(busy ? model.tr("Verificando…") : model.tr("Verificar ahora")).fontWeight(.bold).frame(maxWidth: .infinity).frame(height: 40)
            }.buttonStyle(.borderedProminent).disabled(!model.canOperate || busy)
            Button { model.inspectCalibrate(machineId) } label: { Text(model.tr("Calibrar con este agujero")).frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).disabled(!model.canOperate || busy || q == nil || (q?.holesTotal ?? 0) == 0)
        }
    }
}
