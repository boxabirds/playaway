import SwiftUI
import PlayawayCore

@main
struct PlayawayApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model)
        }
    }
}
