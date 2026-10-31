// EH3D-IOS-CONTROL - the frame of the app: the address and sign-in before, and after them the page that is open with the tabs at the foot.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI
import Eh3dCore

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Forge.background.ignoresSafeArea()
            switch model.phase {
            case .booting: ProgressView().tint(Forge.amber)
            case .signedOut, .firstSetup: EntryView(model: model)
            case .signedIn: Frame(model: model)
            }
        }
        .preferredColorScheme(.dark)
        .tint(Forge.amber)
        .alert(model.tr("Aviso"), isPresented: Binding(get: { model.message != nil && model.phase == .signedIn }, set: { if !$0 { model.dismissMessage() } })) {
            Button(model.tr("Cerrar")) { model.dismissMessage() }
        } message: { Text(model.message ?? "") }
    }
}

private struct Frame: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.offline {
                Text(model.tr("Sin conexión con el servidor: se muestra lo último que se supo.")).font(.caption).foregroundColor(Forge.danger).padding(8).frame(maxWidth: .infinity).background(Forge.danger.opacity(0.2))
            }
            Group {
                switch model.page {
                case .home: HomeView(model: model)
                case .jobs: JobsView(model: model)
                case .more: MoreView(model: model)
                case .help: HelpView(model: model)
                case .about: AboutView(model: model)
                case .languages: LanguageView(model: model)
                case .machine(let id): MachineView(model: model, id: id)
                case .job(let id): JobDetailView(model: model, id: id)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Tabs(model: model)
        }
    }
}

private struct Tabs: View {
    @ObservedObject var model: AppModel
    private func item(_ title: String, _ icon: String, _ on: Bool, _ page: Page) -> some View {
        Button { model.tab(page) } label: {
            VStack(spacing: 2) { Image(systemName: icon); Text(title).font(.caption2) }.frame(maxWidth: .infinity).foregroundColor(on ? Forge.amber : Forge.dim)
        }
    }
    var body: some View {
        let p = model.page
        var machines = false, jobs = false, more = false
        switch p { case .home, .machine: machines = true; case .jobs, .job: jobs = true; default: more = true }
        return HStack {
            item(model.tr("Máquinas"), "house", machines, .home)
            item(model.tr("Trabajos"), "briefcase", jobs, .jobs)
            item(model.tr("Más"), "ellipsis", more, .more)
        }.padding(.vertical, 8).background(Forge.panel)
    }
}

/// The address of the server and, when it has no user yet, the first administrator; then the sign-in.
private struct EntryView: View {
    @ObservedObject var model: AppModel
    @State private var host = ""
    @State private var port = "18200"
    @State private var name = ""
    @State private var password = ""
    @State private var code = ""
    @State private var remember = false

    private var setup: Bool { model.phase == .firstSetup }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("EH3D").font(.largeTitle.weight(.bold)).foregroundColor(Forge.amber)
                Text(model.tr("Control de máquinas")).font(.headline).foregroundColor(Forge.text)
                Card {
                    Title(model.tr("Servidor"))
                    TextField(model.tr("Dirección (192.168.0.180 o https://…)"), text: $host).textFieldStyle(.roundedBorder).autocapitalization(.none).disableAutocorrection(true).keyboardType(.URL)
                    HStack {
                        TextField(model.tr("Puerto"), text: $port).textFieldStyle(.roundedBorder).keyboardType(.numberPad).frame(width: 110)
                        Button(model.busy ? model.tr("Conectando…") : model.tr("Conectar")) { model.connect(host: host, port: port) }.buttonStyle(.borderedProminent).disabled(host.isEmpty || model.busy)
                    }
                    if ServerEndpoint.needsSecureConnection(host) { Text(model.tr("Fuera de la red local solo se admite https://: la contraseña no viajará sin cifrar.")).font(.caption).foregroundColor(Forge.orange) }
                }
                Card {
                    Title(setup ? model.tr("Primer administrador") : model.tr("Iniciar sesión"))
                    if setup {
                        Text(model.tr("El servidor aún no tiene usuarios. El código aparece en su consola al arrancar.")).font(.caption).foregroundColor(Forge.dim)
                        TextField(model.tr("Código de alta"), text: $code).textFieldStyle(.roundedBorder).autocapitalization(.none)
                    }
                    TextField(model.tr("Usuario"), text: $name).textFieldStyle(.roundedBorder).autocapitalization(.none).disableAutocorrection(true)
                    SecureField(model.tr("Contraseña"), text: $password).textFieldStyle(.roundedBorder)
                    if !setup { Toggle(model.tr("Recordarme en este teléfono"), isOn: $remember).foregroundColor(Forge.text) }
                    Button(setup ? model.tr("Crear administrador") : model.tr("Entrar")) {
                        if setup { model.firstSetup(code: code, name: name, password: password) }
                        else { model.signIn(origin: ServerEndpoint.fromHostAndPort(host, port)?.origin ?? model.origin, name: name, password: password, remember: remember) }
                    }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                    .disabled(name.isEmpty || password.count < (setup ? 8 : 1) || (setup && code.isEmpty) || model.busy)
                    if setup { Text(model.tr("La contraseña tiene de 8 a 128 caracteres.")).font(.caption).foregroundColor(Forge.dim) }
                }
                if let m = model.message { Card(accent: Forge.danger) { Text(m).foregroundColor(Forge.danger); Button(model.tr("Cerrar")) { model.dismissMessage() } } }
            }.padding(24)
        }
        .onAppear {
            let o = model.origin
            host = o.replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "https://", with: "").split(separator: ":").first.map(String.init) ?? ""
            if let p = o.split(separator: ":").last, p.allSatisfy({ $0.isNumber }), !p.isEmpty { port = String(p) }
            name = model.savedUser(); password = model.savedPassword(); remember = model.rememberMe
        }
    }
}
