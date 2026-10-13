import SwiftUI
import PlayawayCore

@main
struct PlayawayApp: App {
    var body: some Scene { WindowGroup { PlaylistsView() } }
}

/// Empty shell: the real screens belong to stories 23 to 27.
struct PlaylistsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("No Playlists", systemImage: "music.note.list",
                                   description: Text("Playlists you create appear here."))
                .navigationTitle("Playlists")
        }
        .accessibilityIdentifier("playlists-root")
    }
}
