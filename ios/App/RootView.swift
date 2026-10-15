import SwiftUI
import UniformTypeIdentifiers
import PlayawayCore

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack(path: $model.path) {
            PlaylistsView()
                .navigationDestination(for: URL.self) { url in
                    if let session = model.session(for: url) { PlaylistView(session: session) }
                    else { ContentUnavailableView("Playlist unavailable", systemImage: "exclamationmark.triangle") }
                }
        }
        .overlay { PlayerChrome() }
        .onOpenURL { url in
            _ = url.startAccessingSecurityScopedResource()
            model.openCoordinator.open(url)
        }
    }
}

struct PlaylistsView: View {
    @EnvironmentObject var model: AppModel
    @State private var creating = false
    @State private var newName = ""
    @State private var errorText: String?

    var body: some View {
        Group {
            if model.entries.isEmpty {
                ContentUnavailableView("No Playlists", systemImage: "music.note.list",
                                       description: Text("Tap + to make your first playlist."))
            } else {
                List(model.entries) { entry in
                    NavigationLink(value: entry.url) { row(entry) }
                }
                .contentMargins(.bottom, model.playerBarVisible ? PlayerBar.inset : 0, for: .scrollContent)
            }
        }
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { newName = ""; creating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New Playlist")
            }
        }
        .alert("New Playlist", isPresented: $creating) {
            TextField("Name", text: $newName)
            Button("Create") {
                do { model.openPlaylist(try model.createPlaylist(named: newName)) }
                catch LibraryError.alreadyExists { errorText = "A playlist with that name already exists." }
                catch { errorText = "Enter a name for the playlist." }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Can't create playlist", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
        .onAppear { model.refresh(); model.firstScreenShown() }
    }

    @ViewBuilder private func row(_ entry: PlaylistEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.name).font(.body)
            switch entry.status {
            case .ok(let count): Text("\(count) \(count == 1 ? "song" : "songs")").font(.caption).foregroundStyle(.secondary)
            case .loading: EmptyView()
            case .damaged: Text("Can't be read").font(.caption).foregroundStyle(.secondary)
            case .newerVersion: Text("Made by a newer version of Playaway").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct PlaylistView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: PlaylistSession
    @State private var importing = false

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 20).padding(.vertical, 12)
            SongTable(session: session)
        }
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { importing = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add Songs")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
            session.add(urls)
            scoped.forEach { $0.stopAccessingSecurityScopedResource() }
        }
        .alert("Playlist", isPresented: Binding(get: { session.notice != nil }, set: { if !$0 { session.dismissNotice() } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(session.notice ?? "") }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(session.name).font(.headline)
                let count = session.playlist.tracks.count
                Text("\(count) \(count == 1 ? "song" : "songs")").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                let state: PlaylistSessionState = session.player.isSessionActive && model.transport.state != .idle
                    ? .songUnderWay(isPlaying: model.transport.state == .playing) : .noSongUnderWay
                var rng = SystemRandomNumberGenerator()
                switch startDecision(session: state, shuffleOn: model.settings.shuffleOn,
                                     songCount: session.playlist.tracks.count, random: &rng) {
                case .toggleCurrentSong: model.transport.playPause()
                case .startShuffled, .startInOrder: session.start()
                case .nothingToStart: break
                }
            } label: {
                Image(systemName: startButtonIcon(session: session.player.isSessionActive && model.transport.state == .playing
                                                  ? .songUnderWay(isPlaying: true) : .noSongUnderWay) == .pause ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Start playlist")
        }
    }
}

extension String {
    var fileNameWithoutExtension: String { (self as NSString).deletingPathExtension }
}
