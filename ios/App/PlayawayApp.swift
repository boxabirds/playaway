import SwiftUI
import PlayawayCore

@main
struct PlayawayApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.saveMemory(force: true) }
        }
    }
}
