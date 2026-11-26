// EH3D-IOS-CONTROL - the 3D printers the server watches, on the home page and read only: health, state, temperatures, progress, time left, layer and alerts. There is not one control here: nothing
// can be sent to a printer. What the printer did not say is written as unknown, never as zero; a server with the list switched off shows nothing.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI
import Eh3dCore

private func healthColor(_ health: String) -> Color {
    switch health {
    case "online": return Forge.green
    case "stale": return Forge.orange
    case "disabled", "off", "unknown": return Forge.dim
    default: return Forge.danger
    }
}

/// The part of the home page for the printers; nothing at all while the server has the list switched off.
struct PrintersSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let listing = model.printers
        if listing.view != .hidden {
            Title(model.tr("Impresoras 3D (solo lectura)"))
            Text(model.tr("Lo que el servidor lee de cada impresora. Desde aquí no se puede enviar nada a una impresora: ni pausa, ni temperatura, ni fichero.")).font(.caption).foregroundColor(Forge.dim)
            if listing.view == .unreadable {
                Text(model.tr("No se puede leer la lista de impresoras que responde el servidor.")).font(.caption).foregroundColor(Forge.danger)
            } else if listing.old {
                Text(model.tr("La lista de abajo es la última que se pudo leer.")).font(.caption).foregroundColor(Forge.orange)
            }
            if listing.view == .listed && listing.printers.isEmpty { Text(model.tr("No hay ninguna impresora registrada en el servidor.")).foregroundColor(Forge.dim) }
            ForEach(listing.printers, id: \.id) { p in PrinterCard(model: model, p: p) }
        }
    }
}

struct PrinterCard: View {
    @ObservedObject var model: AppModel
    let p: Printer

    private var unknown: String { model.tr("desconocido") }

    private var healthWord: String {
        switch p.health {
        case "disabled": return model.tr("Desactivada")
        case "off": return model.tr("Enlace apagado")
        case "online": return model.tr("En línea")
        case "stale": return model.tr("Datos antiguos")
        case "offline": return model.tr("Sin respuesta")
        case "refused": return model.tr("Acceso rechazado")
        case "untrusted": return model.tr("Certificado no fiable")
        case "bad_report": return model.tr("Respuesta ilegible")
        default: return model.tr("Sin leer")
        }
    }

    private var stateWord: String {
        switch p.state {
        case "idle": return model.tr("En reposo")
        case "preparing": return model.tr("Preparando")
        case "printing": return model.tr("Imprimiendo")
        case "paused": return model.tr("En pausa")
        case "finished": return model.tr("Terminada")
        case "failed": return model.tr("Fallida")
        case "cancelled": return model.tr("Cancelada")
        case "error": return model.tr("Error")
        case "emergency": return model.tr("Firmware parado")
        default: return unknown
        }
    }

    private func temperatureName(_ name: String) -> String {
        name == "nozzle" ? model.tr("Boquilla") : name == "bed" ? model.tr("Cama") : model.tr("Cámara cerrada")
    }

    private func severityWord(_ severity: String) -> String {
        severity == "error" ? model.tr("Error") : severity == "info" ? model.tr("Información") : model.tr("Aviso")
    }

    /// The lines of the temperatures; one line that says unknown when the printer gave none.
    private var temperatureLines: [String] {
        if p.temperatures.isEmpty { return [model.trf("Temperaturas: %s", unknown)] }
        return p.temperatures.map { model.trf("%s: %s (objetivo %s)", temperatureName($0.name), printerDegrees($0.currentC, unknown: unknown), printerDegrees($0.targetC, unknown: unknown)) }
    }

    private var timeLeftLine: String {
        var left = unknown
        if let seconds = p.remainingS {
            let time = printerTimeLeft(seconds)
            let text = time.hours > 0 ? model.trf("%d h %d min", time.hours, time.minutes) : model.trf("%d min", time.minutes)
            left = p.remainingEstimated ? model.trf("%s (estimación)", text) : text
        }
        return model.trf("Tiempo restante: %s", left)
    }

    private var layerLine: String { model.trf("Capa: %s de %s", printerNumber(p.layer, unknown: unknown), printerNumber(p.layers, unknown: unknown)) }

    /// The alerts as lines: unknown when the server shows nothing of the printer, "none" when the printer says it has none.
    private var alertLines: [String] {
        guard let alerts = p.alerts else { return [model.trf("Alertas: %s", unknown)] }
        if alerts.isEmpty { return [model.tr("Sin alertas")] }
        return alerts.map { a in [severityWord(a.severity) + ":", a.code, a.message].filter { !$0.isEmpty }.joined(separator: " ") }
    }

    var body: some View {
        let color = healthColor(p.health)
        let serious = p.alerts?.contains { $0.severity != "info" } ?? false
        Card(accent: color) {
            HStack(spacing: 10) {
                Light(color: color, live: p.current)
                VStack(alignment: .leading) {
                    Text(p.name).font(.headline).foregroundColor(Forge.text)
                    Text(printerFamilyName(p.family)).font(.caption).foregroundColor(Forge.dim)
                }
                Spacer()
                Pill(text: healthWord, color: color)
            }
            if p.simulated { Pill(text: model.tr("SOLO SIMULADOR"), color: Forge.orange) }
            else { Pill(text: model.tr("Sin validar en hardware"), color: Forge.dim) }
            if p.health == "stale", let age = p.ageS { Text(model.trf("dicho hace %d s", age)).font(.caption).foregroundColor(Forge.orange) }
            Text(model.trf("Estado: %s", stateWord)).foregroundColor(Forge.text)
            if !p.jobName.isEmpty { Text(p.jobName).foregroundColor(Forge.text) }
            ForEach(Array(temperatureLines.enumerated()), id: \.offset) { _, line in Text(line).font(.caption).foregroundColor(Forge.text) }
            // a bar is only drawn for a progress the printer said: an unknown one is not 0 %
            if let progress = p.progressPct { ProgressBar(percent: Int(progress), color: color) }
            else { Text(model.trf("Progreso: %s", printerPercent(nil, unknown: unknown))).font(.caption).foregroundColor(Forge.dim) }
            Text(timeLeftLine).font(.caption).foregroundColor(Forge.dim)
            Text(layerLine).font(.caption).foregroundColor(Forge.dim)
            ForEach(Array(alertLines.enumerated()), id: \.offset) { _, line in Text(line).font(.caption).foregroundColor(serious ? Forge.orange : Forge.dim) }
        }
    }
}
