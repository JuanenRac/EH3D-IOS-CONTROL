// EH3D-IOS-CONTROL - the texts and the sheet of the summary shown before a job starts, and the banner that says how the link to the server is and what became of a stop (the same as the Android app).
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI
import Eh3dCore

func linkColor(_ state: LinkState) -> Color {
    switch state {
    case .connected: return Forge.green
    case .stale: return Forge.orange
    case .offline, .wrongServer: return Forge.danger
    }
}

extension AppModel {
    /// One warning of the server about the work, in the language of the app.
    func warningText(_ w: WorkWarning) -> String {
        let a = warningArgs(w)
        switch w.code {
        case "tiny": return trf("Todo el trabajo mide solo %s x %s mm: revise la unidad del archivo", a[0], a[1])
        case "too_big": return trf("El trabajo (%s x %s mm) es mayor que la mesa (%s x %s mm)", a[0], a[1], a[2], a[3])
        case "far": return trf("El trabajo empieza a %s mm de la esquina de la mesa: revise el desplazamiento y la unidad", a[0])
        case "scale": return trf("El archivo de la máquina estira el trabajo (escala %s x %s, no 1)", a[0], a[1])
        case "out_of_course": return trf("El plan lleva el eje %s %s mm más allá de su recorrido", a[0], a[1])
        default: return trf("Aviso del servidor: %s", a[0])
        }
    }

    /// The one word that names the state of the link.
    func linkWord(_ state: LinkState) -> String {
        switch state {
        case .connected: return tr("Conectado")
        case .stale: return tr("Datos antiguos")
        case .offline: return tr("Sin conexión")
        case .wrongServer: return tr("Servidor distinto")
        }
    }

    /// What the banner says when the link is not good; nil when it is. The age of the last good answer is told whenever it is known.
    func linkBanner() -> String? {
        let age = link.ageS().map { formatDuration(Double($0)) }
        switch linkState {
        case .connected: return nil
        case .stale: return trf("Datos de hace %s: el servidor tarda en responder.", age ?? "?")
        case .offline: return tr("Sin conexión con el servidor.") + (age.map { " " + trf("Datos de hace %s.", $0) } ?? "")
        case .wrongServer: return tr("Esta dirección responde otro servicio, no EH3D-SERVER: compruebe la dirección.") + (age.map { " " + trf("Datos de hace %s.", $0) } ?? "")
        }
    }

    /// What is added to the question of a stop when there is no link: the order may not arrive, and where the sure way is. Empty with a link.
    func offlineStopWarning() -> String {
        offline ? "\n" + tr("Sin conexión con el servidor: la orden de parada puede no llegar. Use la parada física de la máquina.") : ""
    }

    /// What became of a stop that was sent.
    func stopNoteText(_ note: StopNote) -> String {
        switch note.outcome {
        case .sent: return trf("Parada enviada a %s. Esperando que la máquina lo confirme.", note.machineName)
        case .confirmed: return trf("Parada confirmada: %s ya no trabaja.", note.machineName)
        case .stillWorking: return trf("%s sigue trabajando. Use la parada física de la máquina.", note.machineName)
        }
    }
}

/// The banner under the top of the screen when the link to the server is not good: what is wrong, how old the data is and a button to try again now.
struct LinkBanner: View {
    @ObservedObject var model: AppModel
    var body: some View {
        if let text = model.linkBanner() {
            let color = linkColor(model.linkState)
            HStack {
                Text(text).font(.caption).foregroundColor(color)
                Spacer()
                Button(model.tr("Reintentar ahora")) { model.retryNow() }.font(.caption)
            }.padding(8).frame(maxWidth: .infinity).background(color.opacity(0.2))
        }
    }
}

/// What became of the stops that were sent, one line each.
struct StopNotes: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ForEach(model.stopNotes, id: \.machineId) { note in
            let color = note.outcome == .confirmed ? Forge.green : note.outcome == .stillWorking ? Forge.danger : Forge.orange
            HStack {
                Text(model.stopNoteText(note)).font(.caption).foregroundColor(color)
                Spacer()
                Button(model.tr("Cerrar")) { model.dismissStopNote(note.machineId) }.font(.caption)
            }.padding(8).frame(maxWidth: .infinity).background(color.opacity(0.2))
        }
    }
}

/// The facts of one view: what it does, how long it takes, how far the axes go and what looks wrong.
private struct SummaryFacts: View {
    @ObservedObject var model: AppModel
    let view: JobView
    var body: some View {
        let s = startSummary(view)
        VStack(alignment: .leading, spacing: 4) {
            if !view.name.isEmpty { Text(view.name).font(.subheadline.weight(.semibold)).foregroundColor(Forge.text) }
            Text(model.trf("%d agujeros o trazados con %d herramientas", s.count, s.tools)).foregroundColor(Forge.text)
            if let size = s.sizeMm, size.count >= 2 { Text(model.tr("Tamaño del trabajo") + ": " + plain(size[0]) + " x " + plain(size[1]) + " mm").foregroundColor(Forge.text) }
            if let seconds = s.seconds { Text(model.tr("Tiempo estimado") + ": " + formatDuration(seconds)).foregroundColor(Forge.text) }
            if let reach = s.reach {
                Text(s.outOfCourse ? model.tr("Simulación en seco: el plan exacto sale del recorrido de un eje") : model.tr("Simulación en seco: el plan exacto queda dentro del recorrido de cada eje"))
                    .foregroundColor(s.outOfCourse ? Forge.danger : Forge.green)
                Text(model.tr("Alcance de los ejes (mm desde los finales)") + ": " + reachLine(reach)).font(.caption).foregroundColor(Forge.dim)
            }
            ForEach(Array(s.warnings.enumerated()), id: \.offset) { _, w in Text(model.warningText(w)).foregroundColor(Forge.orange) }
        }
    }
}

/// The summary before a job starts, with the button that starts it and the one that cancels. `views` are one or two (a drilling and a routing pair).
struct StartSummarySheet: View {
    @ObservedObject var model: AppModel
    let views: [JobView]
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.tr("Revise antes de empezar")).font(.title3.weight(.bold)).foregroundColor(Forge.text)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(views.enumerated()), id: \.offset) { _, v in SummaryFacts(model: model, view: v) }
                    Text(model.tr("Compruebe que la máquina está preparada y despejada. El trabajo empieza ahora.")).font(.caption).foregroundColor(Forge.dim)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button(model.tr("Cancelar")) { onCancel() }.buttonStyle(.bordered)
                Spacer()
                Button(model.tr("Empezar")) { onStart() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(Forge.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
