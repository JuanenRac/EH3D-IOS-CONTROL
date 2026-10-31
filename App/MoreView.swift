// EH3D-IOS-CONTROL - the pages of "More": the language, the help, the about page, the version of the app against the newest release on GitHub, and the sign-out. Also the live picture of the camera.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI
import UIKit
import Eh3dCore

/// The camera of the drill head: the stream is read as it comes and cut into pictures; a dropped stream is asked for again after 1, 2, 4... seconds (30 at most).
struct MjpegView: View {
    let url: URL
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Forge.raised
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if failed { Text("…").foregroundColor(Forge.dim) }
            else { ProgressView().tint(Forge.amber) }
        }
        .task(id: url) { await run() }
    }

    private func run() async {
        var backoff = Backoff()
        while !Task.isCancelled {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                var parser = MjpegFrameParser()
                var chunk = Data()
                for try await byte in bytes {
                    chunk.append(byte)
                    if chunk.count >= 4096 {
                        for frame in parser.feed(chunk) { if let picture = UIImage(data: frame) { image = picture; failed = false; backoff.succeeded() } }
                        chunk.removeAll(keepingCapacity: true)
                    }
                }
            } catch { if Task.isCancelled { return }; if image == nil { failed = true } }
            backoff.failed()
            try? await Task.sleep(nanoseconds: UInt64(backoff.delaySeconds * 1_000_000_000))
        }
    }
}

struct MoreView: View {
    @ObservedObject var model: AppModel
    @State private var latest: String?
    @State private var checking = false

    private var installed: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.1" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.tr("Más")).font(.title2.weight(.bold)).foregroundColor(Forge.text).padding(.top, 14)
                Card {
                    Title(model.tr("Sesión"))
                    Text(model.login.map { "\($0.name) · \(roleName($0.role, model.tr))" } ?? "").foregroundColor(Forge.text)
                    Text(model.origin).font(.caption).foregroundColor(Forge.dim)
                    Button(model.tr("Cerrar sesión")) { model.signOut() }.buttonStyle(.bordered)
                }
                Card {
                    Title(model.tr("Actualización desde GitHub"))
                    Text(model.trf("Versión instalada: %s", installed)).foregroundColor(Forge.text)
                    if checking { Text(model.tr("Buscando…")).foregroundColor(Forge.dim) }
                    else if let latest, SemanticVersion.isNewer(latest, than: installed) {
                        Text(model.trf("Hay una versión nueva: %s", latest)).foregroundColor(Forge.amber)
                        Link(model.tr("Descargar e instalar"), destination: URL(string: "https://github.com/JuanenRac/EH3D-IOS-CONTROL/releases/latest")!)
                    } else if latest != nil { Text(model.tr("Está al día.")).foregroundColor(Forge.green) }
                    Button(latest == nil ? model.tr("Buscar actualizaciones") : model.tr("Buscar de nuevo")) { Task { await check() } }.buttonStyle(.bordered).disabled(checking)
                }
                Card {
                    Title(model.tr("Ajustes"))
                    Button { model.open(.languages) } label: { HStack { Text(model.tr("Idioma")).foregroundColor(Forge.text); Spacer(); Text(Translator.languages.first { $0.code == model.language }?.name ?? "").foregroundColor(Forge.amber) } }
                    HStack { Text(model.tr("Tema")).foregroundColor(Forge.text); Spacer(); Text("Forge").foregroundColor(Forge.amber) }
                    Button(model.tr("Avisos")) { model.requestNotices() }.buttonStyle(.bordered)
                }
                Card {
                    Button { model.open(.help) } label: { Text(model.tr("Ayuda")).foregroundColor(Forge.text) }
                    Button { model.open(.about) } label: { Text(model.tr("Acerca de")).foregroundColor(Forge.text) }
                }
            }.padding(.horizontal, 16)
        }
    }

    /// Looks at the newest release of this project on GitHub (public, no sign-in); iPhones cannot be updated from outside the store, so the app only tells and links to it.
    private func check() async {
        checking = true; defer { checking = false }
        guard let url = URL(string: "https://api.github.com/repos/JuanenRac/EH3D-IOS-CONTROL/releases/latest") else { return }
        var r = URLRequest(url: url); r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept"); r.setValue("EH3D-IOS-CONTROL/\(installed)", forHTTPHeaderField: "User-Agent")
        if let (data, _) = try? await URLSession.shared.data(for: r), let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let tag = j["tag_name"] as? String { latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag }
        else { latest = installed }
    }
}

struct LanguageView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("‹ " + model.tr("Volver")) { model.back() }
            Text(model.tr("Idioma")).font(.title2.weight(.bold)).foregroundColor(Forge.text)
            ForEach(Translator.languages, id: \.code) { l in
                Button { model.choose(language: l.code) } label: { HStack { Image(systemName: model.language == l.code ? "largecircle.fill.circle" : "circle").foregroundColor(Forge.amber); Text(l.name).foregroundColor(Forge.text); Spacer() } }.padding(.vertical, 4)
            }
            Spacer()
        }.padding(16)
    }
}

struct HelpView: View {
    @ObservedObject var model: AppModel
    @State private var topic = 0
    var body: some View {
        let topics: [(String, String)] = [
            (model.tr("Empezar"), model.tr("Escriba la dirección del servidor EH3D-SERVER (la de su red, por ejemplo la de la CM5) y el puerto 18200, y pulse Conectar. Si el servidor aún no tiene usuarios, la app pide el código de alta que aparece en su consola y crea el primer administrador. Después inicie sesión.")),
            (model.tr("Máquinas"), model.tr("La pantalla Máquinas muestra cada máquina del taller: libre, trabajando o esperando al operario, con el progreso del trabajo y lo que queda. Pulse una máquina para seguirla en tiempo real.")),
            (model.tr("Parada de emergencia"), model.tr("El botón rojo para la máquina: se cancela su trabajo, el husillo y los motores se apagan. Pide una segunda pulsación para evitar paradas accidentales. Solo los operarios y administradores pueden pararla; los demás usuarios solo ven. No sustituye a la seta de emergencia física de la máquina.")),
            (model.tr("Visor 2D y 3D"), model.tr("Muestra la placa, los agujeros (un anillo hasta que se taladran, rellenos después) y las trayectorias (tenues hasta que se cortan). El anillo verde marca dónde está el cabezal; es una estimación a partir de los pasos hechos que informa el servidor. En 3D, arrastre para girar y toque dos veces para volver.")),
            (model.tr("Cabezal y cámara"), model.tr("Si la máquina tiene un nodo de cabezal (EH3D-NODE-BUNGARD-AUX) verá su cámara, las vueltas y la temperatura del husillo y la salida de protección, y podrá medir la altura de la mesa con el láser.")),
            (model.tr("Trabajos"), model.tr("La pestaña Trabajos lista los trabajos del servidor. Un trabajo nunca arranca solo: ábralo y pulse Empezar con la máquina preparada. Cuando la máquina pide cambiar de herramienta, confirme desde aquí.")),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            Button("‹ " + model.tr("Volver")) { model.back() }
            Text(model.tr("Ayuda")).font(.title2.weight(.bold)).foregroundColor(Forge.text)
            ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(topics.indices, id: \.self) { i in Button(topics[i].0) { topic = i }.buttonStyle(.bordered).tint(topic == i ? Forge.amber : Forge.dim) } } }
            Card { Title(topics[topic].0); Text(topics[topic].1).foregroundColor(Forge.text) }
            Spacer()
        }.padding(16)
    }
}

struct AboutView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("‹ " + model.tr("Volver")) { model.back() }
            Card {
                Text("EH3D").font(.largeTitle.weight(.bold)).foregroundColor(Forge.amber)
                Text(model.tr("Control de máquinas")).foregroundColor(Forge.text)
                Text(model.trf("Versión %s", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.1")).foregroundColor(Forge.dim)
                Text(model.tr("Vigila y para las máquinas Bungard del taller a través de EH3D-SERVER. Es independiente: no está hecha, avalada ni respaldada por Bungard Elektronik.")).font(.caption).foregroundColor(Forge.dim)
                Text("JuanenRac · Electro Hobby 3D · GPL-3.0-or-later").font(.caption).foregroundColor(Forge.dim)
                Text("github.com/JuanenRac/EH3D-IOS-CONTROL").font(.caption).foregroundColor(Forge.amber)
            }
            Spacer()
        }.padding(16)
    }
}
