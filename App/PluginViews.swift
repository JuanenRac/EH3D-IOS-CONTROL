// EH3D-IOS-CONTROL - the machines of the plugins of the server (laser, pick-and-place, board station, CNC, Gerber, CAM, 3D printer, vision, CAD) and the switches of the server: what each machine says of itself,
// a badge when it has only run against a simulator, the interlocks in red, the emergency stop with one touch and no question, the release of a latch (administrators, asked twice), the queue of its jobs
// (a job is started by a person, asked twice, and never by itself) and the limits of temperature of a printer. The rules are in Sources/Eh3dCore/WorkSafety.swift; the Android app and EH3D-STUDIO show the same.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI
import Eh3dCore

/// The word of an interlock that holds a machine.
func interlockWord(_ interlock: Interlock, _ tr: (String) -> String) -> String {
    switch interlock {
    case .latched: return tr("Enclavada")
    case .estopLatched: return tr("Parada de emergencia enclavada")
    case .alarm: return tr("Alarma")
    }
}

/// The word of the state of a job of the queue, with how far it is when it runs.
func workJobWord(_ job: WorkJob, _ tr: (String) -> String) -> String {
    switch job.state {
    case "running": return tr("En marcha") + " · \(job.percent) %"
    case "paused": return tr("En pausa")
    default: return tr("En cola")
    }
}

/// What a switch of the server does when it is on; all four are off by default.
func switchNote(_ key: String, _ tr: (String) -> String) -> String {
    switch key {
    case "mdns_announce": return tr("Apagado por defecto. Encendido: el servidor se anuncia en la red local.")
    case "compat_api": return tr("Apagado por defecto. Encendido: las rutas de Moonraker y OctoPrint responden lecturas en la raíz de la dirección.")
    case "compat_write": return tr("Apagado por defecto. Encendido: esas rutas también pueden escribir (pausar, cancelar, subir un archivo a la cola). Nada arranca solo.")
    case "slice_enabled": return tr("Apagado por defecto. Encendido: el servidor puede laminar mallas a G-code.")
    default: return ""
    }
}

/// The word of the kind of a node of a pick-and-place machine.
func pnpKindWord(_ kind: String, _ tr: (String) -> String) -> String { kind == "head" ? tr("Cabezal") : tr("Alimentador") }

/// A node of a pick-and-place machine, read only: its kind, address and machine, whether the server counts it ready (green) or not (red; a node that is switched off is grey), its health as the server says it,
/// the last error of its poll and the numbers it said last. The token is never shown (the phone never reads it). The nodes are registered and changed in EH3D-STUDIO.
struct PnpNodeCard: View {
    @ObservedObject var model: AppModel
    let n: PnpNode

    var body: some View {
        let color = !n.enabled ? Forge.dim : n.ready ? Forge.green : Forge.danger
        let place = n.machine.isEmpty ? n.address : n.address + " · " + n.machine
        let kind = pnpKindWord(n.kind, model.tr)
        let health = n.lastError.isEmpty ? "health: " + n.health : "health: " + n.health + " · " + n.lastError
        Card(accent: color) {
            HStack(spacing: 10) {
                Light(color: color, live: n.ready)
                VStack(alignment: .leading) {
                    Text(n.name).font(.headline).foregroundColor(Forge.text)
                    Text(kind + " · " + place).font(.caption).foregroundColor(Forge.dim)
                }
                Spacer()
                Pill(text: n.ready ? model.tr("Listo") : model.tr("No listo"), color: color)
            }
            if n.simulatorOnly { Pill(text: model.tr("SOLO SIMULADOR"), color: Forge.orange) }
            Text(health).font(.caption).foregroundColor(Forge.text)
            ForEach(Array(n.facts.enumerated()), id: \.offset) { _, line in
                Text("\(line.key): \(line.value)").font(.caption).foregroundColor(Forge.dim)
            }
        }
    }
}

/// What a button of the card asks a second time before it does anything.
private enum Pending: Equatable {
    case release
    case start(WorkJob)
    case cancel(WorkJob)
}

/// A machine of a plugin of the server: its state, the badge of the simulator, its interlocks in red, what the plugin says of it, the emergency stop (an operator: one touch, no question), the release of a
/// latch (an administrator: asked twice) and the jobs of its queue (an operator starts one, asked twice).
struct WorkMachineCard: View {
    @ObservedObject var model: AppModel
    let w: WorkMachine
    @State private var pending: Pending?

    var body: some View {
        let busy = w.state == "busy"
        let color = w.latched ? Forge.danger : busy ? Forge.amber : Forge.green
        let word = w.latched ? model.tr("Bloqueada") : busy ? model.tr("Trabajando") : model.tr("Libre")
        let queue = MachineSafety.activeJobs(model.workJobs, machineId: w.id)
        Card(accent: color) {
            HStack(spacing: 10) {
                Light(color: color, live: busy && !w.latched)
                VStack(alignment: .leading) {
                    Text(w.name).font(.headline).foregroundColor(Forge.text)
                    Text(w.plugin).font(.caption).foregroundColor(Forge.dim)
                }
                Spacer()
                Pill(text: word, color: color)
            }
            if w.simulatorOnly {
                Pill(text: model.tr("SOLO SIMULADOR"), color: Forge.orange)
                Text(model.tr("Esta máquina solo ha funcionado contra un simulador: aún no hay prueba en una máquina real.")).font(.caption).foregroundColor(Forge.dim)
            }
            ForEach(Array(w.interlocks.enumerated()), id: \.offset) { _, interlock in Pill(text: interlockWord(interlock, model.tr), color: Forge.danger) }
            if w.autoStart { Pill(text: model.tr("Arranca los trabajos sola"), color: Forge.danger) }
            if let limits = w.limits {
                Text(model.trf("Límites de temperatura (°C): boquilla %s · cama %s · cámara %s", MachineSafety.limitText(limits.hotendC), MachineSafety.limitText(limits.bedC), MachineSafety.limitText(limits.chamberC)))
                    .font(.caption).foregroundColor(Forge.text)
            }
            if !w.heaters.isEmpty {
                Text(model.trf("Temperaturas (°C): %s", w.heaters.map { MachineSafety.heaterText($0) }.joined(separator: " · "))).font(.caption).foregroundColor(Forge.dim)
            }
            ForEach(Array(MachineSafety.facts(w).enumerated()), id: \.offset) { _, line in
                Text("\(line.key): \(line.value)").font(.caption).foregroundColor(Forge.dim)
            }
            if MachineSafety.canStop(isOperator: model.canOperate, w) {
                Button { model.emergencyStopWork(w) } label: { Text(model.tr("PARADA DE EMERGENCIA")).font(.headline).frame(maxWidth: .infinity).frame(height: 44) }
                    .buttonStyle(.borderedProminent).tint(Forge.danger)
            }
            if MachineSafety.canRelease(isAdmin: model.canAdmin, w) {
                Button { pending = .release } label: { Text(model.tr("Soltar el enclavamiento")).frame(maxWidth: .infinity) }.buttonStyle(.bordered)
            } else if !w.interlocks.isEmpty && !model.canAdmin {
                Text(model.tr("Solo un administrador puede soltar el enclavamiento de una máquina.")).font(.caption).foregroundColor(Forge.dim)
            }
            if !queue.isEmpty {
                Title(model.tr("Trabajos en la cola"))
                if MachineSafety.needsManualStart(w.plugin) {
                    Text(model.tr("Una persona debe iniciar esta impresión: nada arranca solo.")).font(.caption).foregroundColor(Forge.dim)
                }
                ForEach(Array(queue.prefix(5)), id: \.id) { job in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(job.name.isEmpty ? job.id : job.name).foregroundColor(Forge.text)
                            Text(workJobWord(job, model.tr)).font(.caption).foregroundColor(Forge.dim)
                        }
                        Spacer()
                        if !w.latched && MachineSafety.canStartJob(isOperator: model.canOperate, job) { Button(model.tr("Empezar")) { pending = .start(job) } }
                        if MachineSafety.canCancelJob(isOperator: model.canOperate, job) { Button(model.tr("Cancelar")) { pending = .cancel(job) } }
                    }
                }
            }
        }
        .confirmationDialog(askTitle(pending), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible, presenting: pending) { ask in
            switch ask {
            case .release:
                Button(model.tr("SOLTAR"), role: .destructive) { model.releaseWork(w) }
                Button(model.tr("No soltar"), role: .cancel) {}
            case .start(let job):
                Button(model.tr("INICIAR")) { model.startWorkJob(job.id) }
                Button(model.tr("No iniciar"), role: .cancel) {}
            case .cancel(let job):
                Button(model.tr("Cancelar"), role: .destructive) { model.cancelWorkJob(job.id) }
                Button(model.tr("No cancelar"), role: .cancel) {}
            }
        } message: { ask in
            Text(askText(ask))
        }
    }

    private func askTitle(_ ask: Pending?) -> String {
        switch ask {
        case .release: return model.tr("Soltar el enclavamiento")
        case .start: return model.tr("Empezar el trabajo")
        case .cancel: return model.tr("Cancelar")
        case nil: return ""
        }
    }

    private func askText(_ ask: Pending) -> String {
        switch ask {
        case .release: return model.tr("¿Soltar el enclavamiento de esta máquina? Compruebe antes que es seguro volver a trabajar.")
        case .start: return model.tr("¿Iniciar este trabajo? Compruebe que la máquina está lista y que nadie está en la zona de trabajo.")
        case .cancel(let job): return model.tr("¿Cancelar este trabajo?") + "\n\n" + (job.name.isEmpty ? job.id : job.name)
        }
    }
}

/// The switches of security of the server that the app explains, for an administrator: whether each is on and what it does. They are changed in EH3D-STUDIO.
struct ServerSwitchesCard: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Card {
            Title(model.tr("Interruptores del servidor"))
            ForEach(model.switches, id: \.key) { item in
                HStack {
                    Text(item.key).foregroundColor(Forge.text)
                    Spacer()
                    Pill(text: item.on ? model.tr("Encendido") : model.tr("Apagado"), color: item.safe ? Forge.green : Forge.orange)
                }
                Text(switchNote(item.key, model.tr)).font(.caption).foregroundColor(Forge.dim)
            }
            Text(model.tr("Se cambian en EH3D-STUDIO. Los cuatro vienen apagados por defecto.")).font(.caption).foregroundColor(Forge.dim)
        }
    }
}
