// EH3D-IOS-CONTROL - the spindle of a machine (the original one or the one with a variable-frequency drive), what the server does with a job that asks for more than it gives, and what a job says
// about it: the excesses it was let through with, and the tools that were switched off for it (the same as the Android app).
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI
import Eh3dCore

/// The spindle choices the server knows: none (empty), the original one and the one with a variable-frequency drive.
let spindleIds = ["", "original", "vfd"]

func spindleName(_ model: AppModel, _ id: String) -> String {
    switch id {
    case "original": return model.tr("Original")
    case "vfd": return model.tr("Con variador (VFD)")
    default: return model.tr("Ninguno")
    }
}

func guardName(_ model: AppModel, _ guardMode: String) -> String { guardMode == "warn" ? model.tr("Avisar y recortar") : model.tr("Rechazarlo") }

/// The limits of a spindle in a line.
func limitsText(_ model: AppModel, _ l: SpindleLimits) -> String {
    model.trf("De %d a %d rpm · corte hasta %d mm/min · penetración hasta %d mm/min · broca hasta %.1f mm", l.minRpm, l.maxRpm, l.maxXyMmMin, l.maxZMmMin, l.maxBitMm)
}

/// One excess of a tool over the spindle, in a sentence.
func warningText(_ model: AppModel, _ w: SpindleWarning) -> String {
    switch w.code {
    case "rpm_above_max": return model.trf("Herramienta %d: %d rpm, el husillo da hasta %d.", w.tool, w.value, w.limit)
    case "rpm_below_min": return model.trf("Herramienta %d: %d rpm, el husillo da desde %d.", w.tool, w.value, w.limit)
    case "feed_xy_above_max": return model.trf("Herramienta %d: corte a %d mm/min, el husillo aguanta %d.", w.tool, w.value, w.limit)
    case "feed_z_above_max": return model.trf("Herramienta %d: penetración a %d mm/min, el husillo aguanta %d.", w.tool, w.value, w.limit)
    default: return model.trf("Herramienta %d: %s", w.tool, w.code)
    }
}

/// The spindle of the machine: which one it carries and the switch; only an administrator changes them.
struct SpindleCard: View {
    @ObservedObject var model: AppModel
    let machineId: String
    var body: some View {
        if let info = model.spindle {
            Card(accent: Forge.blue) {
                Title(model.tr("Husillo"))
                HStack(spacing: 8) {
                    ForEach(spindleIds, id: \.self) { id in
                        Choice(selected: info.spindle == id, label: spindleName(model, id), enabled: model.canAdmin) { model.setSpindle(machineId, spindle: id, guardMode: nil) }
                    }
                }
                if let active = info.active {
                    Text(limitsText(model, active)).font(.caption).foregroundColor(Forge.text)
                    if let top = info.nodeMaxRpm { Text(model.trf("El nodo debe tener como máximo %d rpm.", top)).font(.caption).foregroundColor(Forge.dim) }
                } else {
                    Text(model.tr("Sin husillo elegido: el servidor no compara los trabajos con ningún límite.")).font(.caption).foregroundColor(Forge.dim)
                }
                Text(model.tr("Si el trabajo pide más de lo que da el husillo")).font(.caption).foregroundColor(Forge.dim)
                HStack(spacing: 8) {
                    ForEach(["reject", "warn"], id: \.self) { g in
                        Choice(selected: info.guardMode == g, label: guardName(model, g), enabled: model.canAdmin) { model.setSpindle(machineId, spindle: nil, guardMode: g) }
                    }
                }
                if !model.canAdmin { Text(model.tr("Solo un administrador puede cambiar el husillo.")).font(.caption).foregroundColor(Forge.dim) }
            }
        }
    }
}

/// What a job says about the spindle and the tools it leaves out; the caller draws it only when there is something to say.
struct JobNotes: View {
    @ObservedObject var model: AppModel
    let view: JobView
    var body: some View {
        Card(accent: Forge.orange) {
            if !view.spindleWarnings.isEmpty {
                Title(model.tr("Avisos del husillo"))
                ForEach(Array(view.spindleWarnings.enumerated()), id: \.offset) { _, w in Text(warningText(model, w)).foregroundColor(Forge.orange).font(.subheadline) }
            }
            if !view.skippedTools.isEmpty || view.skipped > 0 {
                Title(model.tr("Lo que se deja fuera"))
                if !view.skippedTools.isEmpty { Text(model.trf("Herramientas desactivadas: %s", view.skippedTools.map { "T\($0)" }.joined(separator: ", "))).foregroundColor(Forge.text) }
                if view.skipped > 0 { Text(model.trf("Ya hechos y omitidos: %d", view.skipped)).foregroundColor(Forge.text) }
            }
        }
    }
}
