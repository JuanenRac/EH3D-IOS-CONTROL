// EH3D-IOS-CONTROL - the app: one window with the model of the app and the Forge theme.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import SwiftUI

@main
struct Eh3dApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .onAppear { model.requestNotices() }
                .onChange(of: scenePhase) { phase in model.setVisible(phase == .active) }
        }
    }
}
