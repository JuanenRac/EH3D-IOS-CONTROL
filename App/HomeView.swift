// EH3D-IOS-CONTROL - the home page: the machines of the workshop with what each one is doing, the emergency stop of all of them, and the page of one machine with its job, its views, its stop and the camera of its drill head.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI
import Eh3dCore

func machineState(_ m: FleetMachine, _ tr: (String) -> String) -> (String, Color) {
    switch m.state {
    case "busy": return (tr("Trabajando"), Forge.amber)
    case "waiting": return (tr("Espera al operario"), Forge.orange)
    default: return (tr("Libre"), Forge.green)
    }
}

func roleName(_ role: String, _ tr: (String) -> String) -> String { role == "admin" ? tr("administrador") : role == "operator" ? tr("operario") : tr("solo ver") }

struct HomeView: View {
    @ObservedObject var model: AppModel
    @State private var askAll = false

    var body: some View {
        let fleet = model.fleet
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("EH3D").font(.largeTitle.weight(.bold)).foregroundColor(Forge.amber)
                        Text(model.login.map { "\($0.name) · \(roleName($0.role, model.tr))" } ?? "").font(.caption).foregroundColor(Forge.dim)
                    }
                    Spacer()
                    Light(color: model.offline ? Forge.danger : Forge.green, live: !model.offline)
                }
                HStack(spacing: 8) {
                    Tile(value: "\(fleet.idle)", name: model.tr("Libres"), color: Forge.green)
                    Tile(value: "\(fleet.busy)", name: model.tr("Trabajando"), color: Forge.amber)
                    Tile(value: "\(fleet.waiting)", name: model.tr("Esperan"), color: Forge.orange)
                }
                if fleet.busy + fleet.waiting > 0 {
                    Button { askAll = true } label: { Text(model.tr("PARADA DE EMERGENCIA DE TODAS")).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10) }
                        .buttonStyle(.borderedProminent).tint(Forge.danger).disabled(!model.canOperate)
                    if !model.canOperate { Text(model.tr("Su usuario solo puede ver: no puede hacer esto.")).font(.caption).foregroundColor(Forge.dim) }
                }
                if fleet.machines.isEmpty { Card { Text(model.offline ? model.tr("Sin conexión con el servidor.") : model.tr("El servidor no tiene máquinas todavía. Se añaden desde EH3D-STUDIO.")).foregroundColor(Forge.dim) } }
                ForEach(fleet.machines, id: \.id) { m in MachineCard(model: model, m: m).onTapGesture { model.open(.machine(m.id)) } }
            }.padding(.horizontal, 16).padding(.top, 12)
        }
        .confirmationDialog(model.tr("PARADA DE EMERGENCIA"), isPresented: $askAll, titleVisibility: .visible) {
            Button(model.tr("PARAR AHORA"), role: .destructive) { model.emergencyStopAll() }
            Button(model.tr("No parar"), role: .cancel) {}
        } message: { Text(model.tr("¿Parar todas las máquinas que trabajan?") + "\n" + model.tr("La máquina se detiene, el husillo y los motores se apagan y el trabajo se cancela.")) }
    }
}

struct MachineCard: View {
    @ObservedObject var model: AppModel
    let m: FleetMachine
    var body: some View {
        let (word, color) = machineState(m, model.tr)
        Card(accent: color) {
            HStack(spacing: 10) {
                Light(color: color, live: m.state == "busy")
                VStack(alignment: .leading) {
                    Text(m.name).font(.headline).foregroundColor(Forge.text)
                    Text([m.model, m.station].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundColor(Forge.dim)
                }
                Spacer()
                Pill(text: word, color: color)
            }
            if let job = m.job {
                Text(job.name.isEmpty ? job.kind : job.name).foregroundColor(Forge.text)
                ProgressBar(percent: job.percent, color: color)
                Text(model.trf("%d de %d hechos · quedan %s", job.itemsDone, job.itemsTotal, formatDuration(job.remainingS))).font(.caption).foregroundColor(Forge.dim)
            } else if m.ready > 0 {
                Text(model.trf("%d trabajo(s) listo(s) para empezar", m.ready)).font(.caption).foregroundColor(Forge.dim)
            }
        }
    }
}

func jobStateText(_ state: String, _ tr: (String) -> String) -> String {
    switch state {
    case "ready": return tr("Listo")
    case "connecting": return tr("Conectando")
    case "running": return tr("En marcha")
    case "waiting_operator": return tr("Espera al operario")
    case "done": return tr("Terminado")
    case "cancelled": return tr("Cancelado")
    case "failed": return tr("Fallido")
    default: return state
    }
}

func jobStateColor(_ state: String) -> Color {
    switch state {
    case "running", "connecting": return Forge.amber
    case "waiting_operator": return Forge.orange
    case "done": return Forge.green
    case "failed": return Forge.danger
    default: return Forge.dim
    }
}

/// The words of a kind of job.
func jobKindText(_ kind: String, _ tr: (String) -> String) -> String {
    switch kind {
    case "drill": return tr("Taladrado")
    case "gcode": return tr("G-code")
    default: return tr("Fresado")
    }
}

@MainActor
func pauseText(_ p: Pause, _ model: AppModel) -> String {
    switch p.kind {
    case "hold": return model.tr("Trabajo en pausa: pulse Reanudar para que siga.")
    case "resume": return model.tr("El trabajo sigue tras una parada: compruebe la máquina y pulse Reanudar antes del primer movimiento.")
    case "tool_change": return model.trf("Ponga la herramienta %d y confirme.", p.tool ?? 0)
    case "spindle_start": return model.tr("Compruebe que el husillo gira y confirme.")
    default: return model.tr("La máquina espera una confirmación.")
    }
}

/// The 2D and 3D views of a job with the choice between them.
struct JobViewer: View {
    @ObservedObject var model: AppModel
    let job: Job
    let itemsDone: Int
    let itemsTotal: Int
    let live: Bool
    @State private var mode = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: $mode) { Text("2D").tag(0); Text("3D").tag(1) }.pickerStyle(.segmented).frame(maxWidth: 160)
            Text(mode == 1 ? model.tr("Arrastre para girar; doble toque para volver.") : model.tr("Anillo verde: dónde está el cabezal (estimado).")).font(.caption).foregroundColor(Forge.dim)
            Group {
                if mode == 0 { JobView2D(job: job, itemsDone: itemsDone, itemsTotal: itemsTotal, live: live) } else { JobView3D(job: job, itemsDone: itemsDone, itemsTotal: itemsTotal, live: live) }
            }.aspectRatio(1.35, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

struct MachineView: View {
    @ObservedObject var model: AppModel
    let id: String
    @State private var askStop = false

    var body: some View {
        if let machine = model.fleet.machine(id) { content(machine) }
        else { VStack(alignment: .leading) { Button("‹ " + model.tr("Volver")) { model.back() }; Text(model.tr("Esta máquina ya no está en el servidor.")).foregroundColor(Forge.dim); Spacer() }.padding(16) }
    }

    private func content(_ machine: FleetMachine) -> some View {
        let (word, color) = machineState(machine, model.tr)
        let active = machine.job
        let job = model.job.flatMap { $0.summary.machine == id ? $0 : nil }
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Button("‹ " + model.tr("Volver")) { model.back() }; Spacer(); Pill(text: word, color: color) }
                Text(machine.name).font(.title2.weight(.bold)).foregroundColor(Forge.text)
                Text([machine.model, machine.station, machine.connection].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundColor(Forge.dim)
                if let a = active, JobStates.active(a.state) {
                    Button { askStop = true } label: { Text(model.tr("PARADA DE EMERGENCIA")).font(.headline).frame(maxWidth: .infinity).frame(height: 44) }
                        .buttonStyle(.borderedProminent).tint(Forge.danger).disabled(!model.canOperate)
                    if !model.canOperate { Text(model.tr("Su usuario solo puede ver: no puede hacer esto.")).font(.caption).foregroundColor(Forge.dim) }
                }
                if let a = active {
                    if let p = a.pause {
                        Card(accent: Forge.orange) {
                            Title(model.tr("La máquina espera"))
                            Text(pauseText(p, model)).foregroundColor(Forge.text)
                            if a.kind == "gcode" { Button(model.tr("Reanudar")) { model.resume(a.id) }.buttonStyle(.borderedProminent).disabled(!model.canOperate) }
                            else { Button(model.tr("Confirmar")) { model.confirm(a.id) }.buttonStyle(.borderedProminent).disabled(!model.canOperate) }
                        }
                    }
                    if a.kind == "gcode" && a.state == "running" { Button(model.tr("Pausar")) { model.pause(a.id) }.buttonStyle(.bordered).frame(maxWidth: .infinity).disabled(!model.canOperate) }
                    Card(accent: color) {
                        Title(model.tr("Trabajo en curso"))
                        Text(a.name.isEmpty ? a.kind : a.name).font(.headline).foregroundColor(Forge.text)
                        ProgressBar(percent: a.percent, color: color)
                        HStack(spacing: 8) {
                            Tile(value: "\(a.itemsDone)/\(a.itemsTotal)", name: model.tr("pasos"))
                            if a.holesTotal > 0 { Tile(value: "\(a.holesDone)/\(a.holesTotal)", name: model.tr("agujeros")) }
                            Tile(value: formatDuration(a.remainingS), name: model.tr("quedan"))
                        }
                        Text(model.trf("Lanzado por %s", a.by)).font(.caption).foregroundColor(Forge.dim)
                    }
                    if let job, a.kind != "gcode" { Card { Title(model.tr("Visor en directo")); JobViewer(model: model, job: job, itemsDone: a.itemsDone, itemsTotal: a.itemsTotal, live: a.state == "running") } }
                } else {
                    Card {
                        Text(model.tr("La máquina está libre.")).foregroundColor(Forge.text)
                        Text(model.tr("Los trabajos que están listos se arrancan desde la pestaña Trabajos.")).font(.caption).foregroundColor(Forge.dim)
                        Button(model.tr("Preparar trabajo")) { model.openPrepare(id) }.buttonStyle(.borderedProminent).disabled(!model.canOperate)
                    }
                }
                if model.spindle != nil { SpindleCard(model: model, machineId: id) }
                if let allowed = model.dollarAllowed, model.fleet.machine(id)?.connection != "node" {
                    Text(allowed ? model.tr("Líneas $ de GRBL en los trabajos de G-code: permitidas en esta máquina.") : model.tr("Líneas $ de GRBL en los trabajos de G-code: no permitidas en esta máquina (las permite un administrador desde Studio)."))
                        .font(.caption).foregroundColor(allowed ? Forge.orange : Forge.dim)
                }
                if !model.noHead { HeadCard(model: model, machineId: id) }
                if !model.noHead, model.head?.camera == true { QualityCard(model: model, machineId: id) }
                Title(model.tr("Trabajos de esta máquina"))
                ForEach(model.jobs.prefix(6), id: \.id) { j in JobRow(model: model, j: j).onTapGesture { model.open(.job(j.id)) } }
            }.padding(.horizontal, 16)
        }
        .confirmationDialog(model.tr("PARADA DE EMERGENCIA"), isPresented: $askStop, titleVisibility: .visible) {
            Button(model.tr("PARAR AHORA"), role: .destructive) { model.emergencyStop(id) }
            Button(model.tr("No parar"), role: .cancel) {}
        } message: { Text(model.trf("Se parará %s.", machine.name) + "\n" + model.tr("La máquina se detiene, el husillo y los motores se apagan y el trabajo se cancela.")) }
    }
}

struct HeadCard: View {
    @ObservedObject var model: AppModel
    let machineId: String
    var body: some View {
        Card(accent: Forge.blue) {
            Title(model.tr("Cabezal de taladrado"))
            if let head = model.head {
                if head.camera, let url = model.streamURL(machineId) { MjpegView(url: url, resolve: { await model.ticketURL($0) }).aspectRatio(4.0 / 3.0, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 6)) }
                else { Text(model.tr("La cámara del cabezal está apagada.")).foregroundColor(Forge.dim) }
                LightRow(model: model, machineId: machineId, head: head)
                HStack(spacing: 8) {
                    Tile(value: head.rpmSensor ? String(format: "%.0f", head.rpm) : "-", name: model.tr("rpm"))
                    Tile(value: head.tempC.map { String(format: "%.1f °C", $0) } ?? "-", name: model.tr("temperatura"), color: head.heat == "critical" ? Forge.danger : head.heat != "ok" ? Forge.orange : Forge.text)
                    Tile(value: head.protectOpen ? model.tr("abierta") : model.tr("cerrada"), name: model.tr("protección"), color: head.protectOpen ? Forge.orange : Forge.green)
                }
                if head.laser {
                    HStack {
                        Button(model.tr("Medir la mesa")) { model.measureTable(machineId) }.buttonStyle(.bordered).disabled(!model.canOperate)
                        if let m = model.measure { Text(m.ok ? model.trf("%.3f mm (±%.3f)", m.distanceMm, m.sigmaMm) : model.trf("Sin medida: %s", m.why)).foregroundColor(m.ok ? Forge.green : Forge.orange) }
                    }
                }
                HeadSensors(model: model, head: head)
            } else { Text(model.tr("Sin datos del nodo del cabezal.")).foregroundColor(Forge.dim) }
        }
    }
}

/// What the sensors of the head say besides the tiles: the laser (how its last reading went and the offset it was calibrated with), the temperature sensors on the wire, how clean the pulses of the speed sensor are and the version of the node. Nothing for a node that does not say.
struct HeadSensors: View {
    @ObservedObject var model: AppModel
    let head: HeadStatus
    var body: some View {
        let laser = head.laser ? laserStatusPhrase(head.laserStatus) : ""
        let rpm = head.rpmSensor ? rpmQualityPhrase(head.rpmQuality) : ""
        if !(laser.isEmpty && rpm.isEmpty && head.tempSensors == 0 && head.version.isEmpty) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.tr("Sensores del cabezal")).font(.subheadline).foregroundColor(Forge.text)
                if !laser.isEmpty {
                    Text(model.tr(laser)).font(.caption).foregroundColor(head.laserStatus == "valid" ? Forge.green : head.laserStatus == "none" ? Forge.dim : Forge.orange)
                    if head.laserAgeMs >= 0 { Text(model.trf("Última lectura: %.1f mm (hace %d s)", head.laserLastMm, head.laserAgeMs / 1000)).font(.caption).foregroundColor(Forge.dim) }
                    if head.laserOffsetMm != 0 { Text(model.trf("Desfase calibrado del láser: %.2f mm", head.laserOffsetMm)).font(.caption).foregroundColor(Forge.dim) }
                }
                if !rpm.isEmpty {
                    Text(model.tr(rpm)).font(.caption).foregroundColor(head.rpmQuality == "good" ? Forge.green : head.rpmQuality == "none" ? Forge.dim : Forge.orange)
                    if head.rpmRejected > 0 { Text(model.trf("Pulsos descartados por ruido: %d", head.rpmRejected)).font(.caption).foregroundColor(Forge.dim) }
                }
                if head.tempSensors > 0 { Text(model.trf("Sensores de temperatura en el hilo: %d", head.tempSensors)).font(.caption).foregroundColor(Forge.dim) }
                if head.tempGuess { Text(model.tr("Hay varios sensores de temperatura y el nodo lee el primero que encontró: elija uno en el panel del nodo.")).font(.caption).foregroundColor(Forge.orange) }
                if !head.version.isEmpty { Text(model.trf("Versión del nodo: %s", head.version)).font(.caption).foregroundColor(Forge.dim) }
            }
        }
    }
}

struct JobRow: View {
    @ObservedObject var model: AppModel
    let j: JobSummary
    var body: some View {
        let color = jobStateColor(j.state)
        Card(accent: color) {
            HStack {
                VStack(alignment: .leading) {
                    Text(j.name.isEmpty ? j.kind : j.name).font(.headline).foregroundColor(Forge.text)
                    Text([jobKindText(j.kind, model.tr), j.by].joined(separator: " · ")).font(.caption).foregroundColor(Forge.dim)
                }
                Spacer()
                Pill(text: jobStateText(j.state, model.tr), color: color)
            }
            if JobStates.active(j.state) { ProgressBar(percent: j.percent, color: color) }
            if !j.message.isEmpty { Text(j.message).font(.caption).foregroundColor(Forge.orange) }
        }
    }
}

struct JobsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.tr("Trabajos")).font(.title2.weight(.bold)).foregroundColor(Forge.text).padding(.top, 14)
                if model.jobs.isEmpty { Card { Text(model.tr("No hay trabajos todavía. Se preparan desde EH3D-STUDIO o desde BUNGARD-GUI.")).foregroundColor(Forge.dim) } }
                ForEach(model.jobs, id: \.id) { j in JobRow(model: model, j: j).onTapGesture { model.open(.job(j.id)) } }
            }.padding(.horizontal, 16)
        }
    }
}

struct JobDetailView: View {
    @ObservedObject var model: AppModel
    let id: String
    @State private var askStop = false
    @State private var askStart = false
    @State private var askDelete = false

    var body: some View {
        let job = model.job.flatMap { $0.summary.id == id ? $0 : nil }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button("‹ " + model.tr("Volver")) { model.back() }
                if let job {
                    let s = job.summary, color = jobStateColor(s.state)
                    HStack {
                        VStack(alignment: .leading) {
                            Text(s.name.isEmpty ? s.kind : s.name).font(.title2.weight(.bold)).foregroundColor(Forge.text)
                            Text(jobKindText(s.kind, model.tr)).font(.caption).foregroundColor(Forge.dim)
                        }
                        Spacer(); Pill(text: jobStateText(s.state, model.tr), color: color)
                    }
                    Card(accent: color) {
                        ProgressBar(percent: s.percent, color: color)
                        Text(model.trf("%d de %d pasos · estimado %s", s.itemsDone, s.itemsTotal, formatDuration(s.estimateS))).font(.caption).foregroundColor(Forge.dim)
                        if s.kind == "gcode" { Text(model.trf("Línea del programa: %d", s.line)).font(.caption).foregroundColor(Forge.dim) }
                        if !s.message.isEmpty { Text(s.message).foregroundColor(Forge.orange) }
                    }
                    if !job.view.skippedTools.isEmpty || job.view.skipped > 0 || !job.view.spindleWarnings.isEmpty { JobNotes(model: model, view: job.view) }
                    if s.kind != "gcode" { Card { Title(model.tr("Visor")); JobViewer(model: model, job: job, itemsDone: s.itemsDone, itemsTotal: s.itemsTotal, live: s.state == "running") } }
                    if !job.view.tools.isEmpty {
                        Card {
                            Title(model.tr("Herramientas"))
                            ForEach(job.view.tools, id: \.number) { t in
                                HStack { Circle().fill(Forge.tool(t.number)).frame(width: 10, height: 10); Text("T\(t.number)  \(t.spindleRpm) rpm  \(t.feedMmMin) mm/min" + (t.depthMm.map { String(format: "  %.2f mm", $0) } ?? "") + "  ×\(t.count)").foregroundColor(Forge.text).font(.subheadline) }
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        if s.state == "ready" { Button(model.tr("Empezar")) { askStart = true }.buttonStyle(.borderedProminent).disabled(!model.canOperate) }
                        if JobStates.active(s.state) { Button(model.tr("PARAR")) { askStop = true }.buttonStyle(.borderedProminent).tint(Forge.danger).disabled(!model.canOperate) }
                        if s.kind == "gcode" && s.state == "running" { Button(model.tr("Pausar")) { model.pause(s.id) }.buttonStyle(.bordered).disabled(!model.canOperate) }
                        if s.state == "waiting_operator" && s.kind == "gcode" { Button(model.tr("Reanudar")) { model.resume(s.id) }.buttonStyle(.borderedProminent).disabled(!model.canOperate) }
                        else if s.state == "waiting_operator" { Button(model.tr("Confirmar")) { model.confirm(s.id) }.buttonStyle(.borderedProminent).disabled(!model.canOperate) }
                        if JobStates.canGoOn(s.state) { Button(model.tr("Seguir desde donde se detuvo")) { model.goOn(s) }.buttonStyle(.bordered).disabled(!model.canOperate) }
                        if !JobStates.active(s.state) { Button(model.tr("Borrar")) { askDelete = true }.buttonStyle(.bordered).disabled(!model.canOperate) }
                    }
                    if let p = s.pause { Text(pauseText(p, model)).foregroundColor(Forge.orange) }
                    if JobStates.canGoOn(s.state) { Text(model.tr("El servidor guardó lo que se pidió: se crea un trabajo nuevo que deja fuera lo ya hecho, sin elegir el archivo otra vez. Espera a que lo empiece y nada se mueve solo.")).font(.caption).foregroundColor(Forge.dim) }
                    if !s.resumedFrom.isEmpty { Text(model.trf("Continúa el trabajo %s", s.resumedFrom)).font(.caption).foregroundColor(Forge.dim) }
                    if s.state == "ready" { Text(model.tr("Un trabajo nunca arranca solo: pulse Empezar con la máquina preparada.")).font(.caption).foregroundColor(Forge.dim) }
                } else { Text(model.tr("Cargando…")).foregroundColor(Forge.dim) }
            }.padding(.horizontal, 16)
        }
        .confirmationDialog(model.tr("PARADA DE EMERGENCIA"), isPresented: $askStop, titleVisibility: .visible) {
            Button(model.tr("PARAR AHORA"), role: .destructive) { model.cancel(id) }
            Button(model.tr("No parar"), role: .cancel) {}
        } message: { Text(model.trf("Se cancelará %s.", job?.summary.name ?? "")) }
        .confirmationDialog(model.tr("Empezar el trabajo"), isPresented: $askStart, titleVisibility: .visible) {
            Button(model.tr("Empezar")) { model.start(id) }
            Button(model.tr("Cancelar"), role: .cancel) {}
        } message: { Text(model.tr("Compruebe que la máquina está preparada y despejada. El trabajo empieza ahora.")) }
        .confirmationDialog(model.tr("Borrar el trabajo"), isPresented: $askDelete, titleVisibility: .visible) {
            Button(model.tr("Borrar"), role: .destructive) { model.delete(id) }
            Button(model.tr("Cancelar"), role: .cancel) {}
        } message: { Text(model.tr("No se puede deshacer.")) }
    }
}
