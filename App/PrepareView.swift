// EH3D-IOS-CONTROL - the page that prepares a job: what to do (drilling, routing, both or a free G-code program), the file from the phone, its tools with their count, the ones switched off,
// the tool to start at, and the start. Nothing starts until the person confirms (the same as the Android app).
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI
import UniformTypeIdentifiers
import Eh3dCore

func workName(_ work: Work, _ tr: (String) -> String) -> String {
    switch work {
    case .drill: return tr("Taladrado")
    case .route: return tr("Fresado")
    case .both: return tr("Ambos")
    case .gcode: return tr("G-code")
    }
}

/// The tools of a side that the job will leave out, after the ones switched off and the start.
func sideSkipped(_ st: SideState) -> [Int] { st.view.map { Prepare.skipTools(order: Prepare.toolOrder($0), off: st.off, startAt: st.startAt) } ?? [] }

/// True when the work chosen can be started: every file it needs is planned and has something left to do.
func prepareReady(_ p: PrepareUi) -> Bool {
    if p.loading || p.busy { return false }
    func sideReady(_ st: SideState) -> Bool {
        guard let view = st.view else { return false }
        return st.error.isEmpty && !Prepare.nothingLeft(order: Prepare.toolOrder(view), skipped: sideSkipped(st))
    }
    switch p.work {
    case .drill: return sideReady(p.drill)
    case .route: return sideReady(p.route)
    case .both: return sideReady(p.drill) && sideReady(p.route)
    case .gcode: return p.gcodeError.isEmpty && (p.gcodeView?.items ?? 0) > 0
    }
}

private enum PickTarget { case file(Side), table(Side), program }

struct PrepareView: View {
    @ObservedObject var model: AppModel
    let machineId: String
    @State private var askStart = false
    @State private var target: PickTarget?
    @State private var picking = false
    @State private var skipText = ""

    var body: some View {
        let machine = model.fleet.machine(machineId)
        let connection = machine?.connection ?? ""
        let p = model.prepare
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button("‹ " + model.tr("Volver")) { model.back() }
                Text(model.tr("Preparar trabajo")).font(.title2.weight(.bold)).foregroundColor(Forge.text)
                Text(machine?.name ?? "").font(.caption).foregroundColor(Forge.dim)
                if !model.canOperate { Card(accent: Forge.orange) { Text(model.tr("Su usuario solo puede ver: no puede hacer esto.")).foregroundColor(Forge.orange) } }
                Card {
                    Title(model.tr("Qué se hace"))
                    Picker("", selection: Binding(get: { model.prepare.work }, set: { model.setWork($0) })) {
                        ForEach(Prepare.works(connection), id: \.self) { w in Text(workName(w, model.tr)).tag(w) }
                    }.pickerStyle(.segmented)
                    if p.work == .both { Text(model.tr("Son dos trabajos, uno detrás de otro: el taladrado se pone en marcha y el fresado queda listo para arrancarlo cuando termine.")).font(.caption).foregroundColor(Forge.dim) }
                    if connection == "node" { Text(model.tr("Esta máquina solo admite taladrado y fresado.")).font(.caption).foregroundColor(Forge.dim) }
                    if connection == "grbl" { Text(model.tr("Esta máquina es un controlador GRBL: solo admite G-code.")).font(.caption).foregroundColor(Forge.dim) }
                }
                if p.work == .drill || p.work == .both { sideCard(.drill, p.drill) }
                if p.work == .route || p.work == .both { sideCard(.route, p.route) }
                if p.work == .gcode { gcodeCard(p) }
                Button { askStart = true } label: { Text(p.busy ? model.tr("Preparando…") : model.tr("Empezar")).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8) }
                    .buttonStyle(.borderedProminent).disabled(!model.canOperate || !prepareReady(p))
                Text(model.tr("Un trabajo nunca arranca solo: se pone en marcha cuando usted lo confirma.")).font(.caption).foregroundColor(Forge.dim)
            }.padding(.horizontal, 16)
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first, let t = target else { return }
            switch t {
            case .file(let side): model.pickFile(machineId, side, url)
            case .table(let side): model.pickTable(machineId, side, url)
            case .program: model.pickProgram(machineId, url)
            }
        }
        .onAppear { skipText = String(model.prepare.skip) }
        .confirmationDialog(model.tr("Empezar el trabajo"), isPresented: $askStart, titleVisibility: .visible) {
            Button(model.tr("Empezar")) { model.startPrepared(machineId) }
            Button(model.tr("Cancelar"), role: .cancel) {}
        } message: { Text(model.tr("Compruebe que la máquina está preparada y despejada. El trabajo empieza ahora.")) }
    }

    private func pick(_ t: PickTarget) { target = t; picking = true }

    @ViewBuilder private func sideCard(_ side: Side, _ st: SideState) -> some View {
        Card {
            Title(side == .drill ? model.tr("Archivo de taladrado") : model.tr("Archivo de fresado"))
            Text(st.fileName.isEmpty ? model.tr("Ningún archivo") : st.fileName).font(.headline).foregroundColor(Forge.text)
            HStack(spacing: 8) {
                Button(model.tr("Elegir archivo")) { pick(.file(side)) }.buttonStyle(.borderedProminent).disabled(!model.canOperate)
                Button(model.tr("Tabla de herramientas")) { pick(.table(side)) }.buttonStyle(.bordered).disabled(!model.canOperate)
            }
            if !st.tableName.isEmpty { Text(model.trf("Tabla: %s", st.tableName)).font(.caption).foregroundColor(Forge.dim) }
            if !st.error.isEmpty { Text(st.error).foregroundColor(Forge.orange) }
            if let view = st.view { toolsList(side, st, view) }
        }
    }

    @ViewBuilder private func toolsList(_ side: Side, _ st: SideState, _ view: JobView) -> some View {
        let order = Prepare.toolOrder(view)
        let skipped = Prepare.skipTools(order: order, off: st.off, startAt: st.startAt)
        let diameters = side == .drill ? Prepare.declaredDiameters(st.text) : [:]
        Title(model.tr("Herramientas del archivo"))
        Text(model.tr("Apague las que no quiera hacer. Con «Empezar aquí» se omiten las anteriores en el orden del trabajo.")).font(.caption).foregroundColor(Forge.dim)
        ForEach(order, id: \.self) { number in
            let tool = view.tools.first { $0.number == number }
            let count = tool?.count ?? (side == .drill ? view.holes.filter { $0.tool == number }.count : view.paths.filter { $0.pen == number }.count)
            let left = skipped.contains(number)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading) {
                        Text(toolLine(side, number, count, tool, diameters[number])).font(.subheadline).foregroundColor(left ? Forge.dim : Forge.text)
                        if left && !st.off.contains(number) { Text(model.tr("Se omite: va antes de la herramienta de inicio.")).font(.caption).foregroundColor(Forge.dim) }
                    }
                    Spacer()
                    Button(model.tr("Empezar aquí")) { model.toggleStartAt(side, number) }
                        .buttonStyle(.bordered).tint(st.startAt == number ? Forge.amber : Forge.dim).disabled(st.off.contains(number))
                    Toggle("", isOn: Binding(get: { !st.off.contains(number) }, set: { _ in model.toggleToolOff(side, number) })).labelsHidden().disabled(!model.canOperate)
                }
            }
        }
        if order.allSatisfy({ skipped.contains($0) }) {
            Text(model.tr("No queda nada por hacer: todas las herramientas están desactivadas o el trabajo ya está hecho.")).foregroundColor(Forge.orange)
        } else {
            Text(model.trf("Se harán %d de %d herramientas · estimado %s", order.filter { !skipped.contains($0) }.count, order.count, formatDuration(view.estimateS))).font(.caption).foregroundColor(Forge.dim)
        }
        if !view.spindleWarnings.isEmpty { JobNotes(model: model, view: view) }
    }

    private func toolLine(_ side: Side, _ number: Int, _ count: Int, _ tool: ToolView?, _ diameter: Double?) -> String {
        var parts = ["T\(number)"]
        if let d = diameter { parts.append(String(format: "Ø %.2f mm", d)) }
        parts.append(side == .drill ? model.trf("%d agujeros", count) : model.trf("%d trazados", count))
        if let t = tool, t.spindleRpm > 0 { parts.append("\(t.spindleRpm) rpm") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func gcodeCard(_ p: PrepareUi) -> some View {
        Card {
            Title(model.tr("Programa G-code"))
            Text(p.gcodeName.isEmpty ? model.tr("Ningún archivo") : p.gcodeName).font(.headline).foregroundColor(Forge.text)
            Button(model.tr("Elegir archivo")) { pick(.program) }.buttonStyle(.borderedProminent).disabled(!model.canOperate)
            if !p.gcodeError.isEmpty { Text(p.gcodeError).foregroundColor(Forge.orange) }
            if !p.gcode.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.tr("Empezar desde la línea")).font(.caption).foregroundColor(Forge.dim)
                    TextField("0", text: $skipText).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                        .onChange(of: skipText) { v in
                            let digits = String(v.filter { $0.isNumber }.prefix(7))
                            if digits != v { skipText = digits }
                            model.setSkip(machineId, Int(digits) ?? 0)
                        }
                }
                Text(model.trf("El programa tiene %d líneas. Con una línea mayor que 0 la máquina espera su confirmación antes del primer movimiento.", Prepare.lineCount(p.gcode))).font(.caption).foregroundColor(Forge.dim)
                Toggle(isOn: Binding(get: { model.prepare.restoreOutputs }, set: { model.setRestoreOutputs($0) })) {
                    VStack(alignment: .leading) {
                        Text(model.tr("Volver a poner en marcha el husillo y el refrigerante")).foregroundColor(Forge.text)
                        Text(model.tr("Desactivado por seguridad: el husillo y el refrigerante no se encienden al continuar.")).font(.caption).foregroundColor(Forge.dim)
                    }
                }.disabled(!model.canOperate)
            }
            if let v = p.gcodeView {
                Text(model.trf("%d líneas se enviarán · estimado %s", v.items, formatDuration(v.estimateS))).foregroundColor(Forge.text)
                if let b = v.bounds, b.count >= 4 { Text(model.trf("Zona: X %.1f a %.1f · Y %.1f a %.1f mm", b[0], b[2], b[1], b[3])).font(.caption).foregroundColor(Forge.dim) }
                if !v.spindleWarnings.isEmpty { JobNotes(model: model, view: v) }
            }
        }
    }
}
