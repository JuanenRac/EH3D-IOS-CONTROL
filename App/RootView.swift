// EH3D-IOS-CONTROL - the frame of the app: the address and sign-in before, and after them the page that is open with the tabs at the foot.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI
import Eh3dCore

struct RootView: View {
    @ObservedObject var model: AppModel
    /// The mark first, as in the apps of the other programs, and then what the phase of the app asks for.
    @State private var splash = true

    var body: some View {
        ZStack {
            Forge.background.ignoresSafeArea()
            if splash {
                SplashView(model: model) { splash = false }
            } else {
                switch model.phase {
                case .booting: RestoringView(model: model)
                case .signedOut, .firstSetup: EntryView(model: model)
                case .signedIn: Frame(model: model)
                }
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
            LinkBanner(model: model)
            StopNotes(model: model)
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
                case .prepare(let id): PrepareView(model: model, machineId: id)
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
        switch p { case .home, .machine, .prepare: machines = true; case .jobs, .job: jobs = true; default: more = true }
        return HStack {
            item(model.tr("Máquinas"), "house", machines, .home)
            item(model.tr("Trabajos"), "briefcase", jobs, .jobs)
            item(model.tr("Más"), "ellipsis", more, .more)
        }.padding(.vertical, 8).background(Forge.panel)
    }
}

/// The first second and a half: the mark appears, then the app.
private struct SplashView: View {
    @ObservedObject var model: AppModel
    let done: () -> Void
    @State private var appear = false
    @State private var leave = false

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(red: 0.227, green: 0.165, blue: 0.031), Forge.background], center: .center, startRadius: 0, endRadius: 450).ignoresSafeArea()
            VStack(spacing: 6) {
                Eh3dLogo(size: 112)
                Text("EH3D").font(.system(size: 30, weight: .black)).tracking(6).foregroundColor(Forge.text).padding(.top, 14)
                Text(model.tr("Control de máquinas")).font(.footnote).foregroundColor(Forge.dim)
            }
            .opacity(appear ? 1 : 0).scaleEffect(appear ? 1 : 0.85)
        }
        .opacity(leave ? 0 : 1)
        .onAppear {
            withAnimation(.easeOut(duration: 0.65)) { appear = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                withAnimation(.easeIn(duration: 0.35)) { leave = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { done() }
            }
        }
    }
}

/// While the app tries the session kept from the last time: the sign-in is not shown for a moment and then taken away.
private struct RestoringView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 14) {
            Eh3dLogo(size: 72)
            ProgressView().tint(Forge.amber)
            Text(model.tr("Conectando con tu servidor…")).foregroundColor(Forge.dim)
        }
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
    @State private var visible = false

    private var setup: Bool { model.phase == .firstSetup }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.165, green: 0.118, blue: 0.031), Forge.background, Forge.background], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 6) {
                    Eh3dLogo(size: 84).padding(.top, 24)
                    Text("EH3D").font(.system(size: 28, weight: .black)).tracking(5).foregroundColor(Forge.text).padding(.top, 8)
                    Text(model.tr("Control de máquinas")).font(.footnote).foregroundColor(Forge.dim)
                    Panel {
                        HStack(spacing: 10) {
                            Image(systemName: "server.rack").foregroundColor(Forge.amber)
                            TextField(model.tr("Dirección (192.168.0.180 o https://…)"), text: $host).textFieldStyle(.roundedBorder).autocapitalization(.none).disableAutocorrection(true).keyboardType(.URL)
                        }
                        HStack(spacing: 10) {
                            TextField(model.tr("Puerto"), text: $port).textFieldStyle(.roundedBorder).keyboardType(.numberPad).frame(width: 110)
                            Spacer()
                            Button(model.busy ? model.tr("Conectando…") : model.tr("Conectar")) { model.connect(host: host, port: port) }.buttonStyle(.bordered).disabled(host.isEmpty || model.busy)
                        }
                        if ServerEndpoint.needsSecureConnection(host) { Text(model.tr("Fuera de la red local solo se admite https://: la contraseña no viajará sin cifrar.")).font(.caption).foregroundColor(Forge.orange) }
                        Title(setup ? model.tr("Primer administrador") : model.tr("Iniciar sesión"))
                        if setup {
                            Text(model.tr("El servidor aún no tiene usuarios. El código aparece en su consola al arrancar.")).font(.caption).foregroundColor(Forge.dim)
                            HStack(spacing: 10) { Image(systemName: "lock").foregroundColor(Forge.amber); TextField(model.tr("Código de alta"), text: $code).textFieldStyle(.roundedBorder).autocapitalization(.none) }
                        }
                        HStack(spacing: 10) { Image(systemName: "person").foregroundColor(Forge.amber); TextField(model.tr("Usuario"), text: $name).textFieldStyle(.roundedBorder).autocapitalization(.none).disableAutocorrection(true) }
                        HStack(spacing: 10) {
                            Image(systemName: "lock").foregroundColor(Forge.amber)
                            Group { if visible { TextField(model.tr("Contraseña"), text: $password) } else { SecureField(model.tr("Contraseña"), text: $password) } }.textFieldStyle(.roundedBorder).autocapitalization(.none).disableAutocorrection(true)
                            Button { visible.toggle() } label: { Image(systemName: visible ? "eye.slash" : "eye").foregroundColor(Forge.dim) }.accessibilityLabel(visible ? model.tr("Ocultar") : model.tr("Mostrar"))
                        }
                        if !setup { Toggle(model.tr("Recordarme en este teléfono"), isOn: $remember).foregroundColor(Forge.text) }
                        Button {
                            if setup { model.firstSetup(code: code, name: name, password: password) }
                            else { model.signIn(origin: ServerEndpoint.fromHostAndPort(host, port)?.origin ?? model.origin, name: name, password: password, remember: remember) }
                        } label: {
                            HStack { if model.busy { ProgressView().tint(.black) } else { Image(systemName: "arrow.right.circle") }; Text(setup ? model.tr("Crear administrador") : model.tr("Entrar")).fontWeight(.bold) }.frame(maxWidth: .infinity).frame(height: 40)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(name.isEmpty || password.count < (setup ? 8 : 1) || (setup && code.isEmpty) || model.busy)
                        if setup { Text(model.tr("La contraseña tiene de 8 a 128 caracteres.")).font(.caption).foregroundColor(Forge.dim) }
                        if let m = model.message {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle").foregroundColor(Forge.danger)
                                Text(m).font(.caption).foregroundColor(Forge.danger)
                                Spacer()
                                Button(model.tr("Cerrar")) { model.dismissMessage() }.font(.caption)
                            }
                        }
                    }.padding(.top, 20)
                    if !setup {
                        Text(remember ? model.tr("Con «Recordarme» solo se guarda, cifrado en este teléfono, el pase de sesión de este servidor (nunca el usuario ni la contraseña); caduca a los 30 días y se revoca al cerrar sesión.")
                                      : model.tr("No se guarda nada en el teléfono: al cerrar la app tendrás que entrar de nuevo. Marca «Recordarme» para conservar el pase de sesión, cifrado, durante 30 días."))
                            .font(.caption).foregroundColor(Forge.dim).multilineTextAlignment(.center).padding(.top, 14)
                    }
                }.padding(24)
            }
        }
        .onAppear {
            let o = model.origin
            host = o.replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "https://", with: "").split(separator: ":").first.map(String.init) ?? ""
            if let p = o.split(separator: ":").last, p.allSatisfy({ $0.isNumber }), !p.isEmpty { port = String(p) }
            name = ""; password = ""; remember = model.rememberMe
        }
    }
}
