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
        .safeAreaInset(edge: .top, spacing: 0) {
            // Temporary, for build 17: what the launch-time restore did, so a restore that fails on a phone says why.
            Text("Restore: " + model.restoreReport)
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
                .accessibilityIdentifier("restore-report")
        }
        .overlay { PlayerChrome() }
        .sheet(isPresented: $model.renameShown) { RenameSheet() }
        .alert("Sync with iCloud", isPresented: Binding(get: { model.syncTarget != nil }, set: { if !$0 { model.syncTarget = nil } })) {
            Button("Move to iCloud") { model.confirmSync() }
            Button("Cancel", role: .cancel) { model.syncTarget = nil }
        } message: {
            Text("“\(model.syncTarget?.name ?? "")” will be moved to the Playaway folder in iCloud Drive so your other devices can see it. Your songs are not moved.")
        }
        .alert("Delete “\(model.deleteTarget?.name ?? "")”?", isPresented: Binding(get: { model.deleteTarget != nil },
                                                                                   set: { if !$0 { model.deleteTarget = nil } })) {
            Button("Delete", role: .destructive) { model.confirmDelete() }
            Button("Cancel", role: .cancel) { model.deleteTarget = nil }
        } message: { Text("Only the playlist is deleted. Your songs are not.") }
        .onAppear {
            #if DEBUG
            // Test aid: run every animation ten times slower, so a test can see whether a change is animated or snaps.
            if ProcessInfo.processInfo.arguments.contains("-PlayawaySlowAnimations") {
                DispatchQueue.main.async {
                    for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                        for window in scene.windows { window.layer.speed = 0.1 }
                    }
                }
            }
            #endif
        }
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
                        .overlay(alignment: .trailing) {
                            PlaylistCloudIcon(entry: entry) { model.beginSync(entry) }.padding(.trailing, 28)
                        }
                        .contextMenu {
                            if case .ok = entry.status {
                                Button { model.beginRename(entry.url) } label: { Label("Rename", systemImage: "pencil") }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { model.deleteTarget = entry } label: { Label("Delete", systemImage: "trash") }
                        }
                        .accessibilityAction(named: "Delete") { model.deleteTarget = entry }
                        .accessibilityAction(named: "Rename") { if case .ok = entry.status { model.beginRename(entry.url) } }
                }
                .contentMargins(.bottom, model.playerBarInset, for: .scrollContent)
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
        SongTable(session: session)
            // The title, the song count and the controls live in the navigation bar: back at the left, the name over the
            // song count in the middle, play or pause and Add Songs at the right.
            .navigationTitle(session.name)
            .navigationSubtitle(songCountText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleMenu {
                Button { model.beginRename(session.url) } label: { Label("Rename Playlist", systemImage: "pencil") }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    StartPlaylistButton(session: session)
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

    private var songCountText: String {
        let count = session.playlist.tracks.count
        return "\(count) \(count == 1 ? "song" : "songs")"
    }
}

/// Starts the playlist, or plays and pauses the song under way, by the shared rule. It is its own view so that the
/// playback position ticking does not redraw the navigation bar around it.
struct StartPlaylistButton: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: PlaylistSession

    var body: some View {
        let sessionIsPlaying = session.player.isSessionActive && model.transport.state == .playing
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
            Image(systemName: startButtonIcon(session: sessionIsPlaying ? .songUnderWay(isPlaying: true) : .noSongUnderWay) == .pause
                  ? "pause.fill" : "play.fill")
        }
        .accessibilityLabel("Start playlist")
    }
}

extension String {
    var fileNameWithoutExtension: String { (self as NSString).deletingPathExtension }
}


/// Renaming a playlist: a small form that keeps what was typed and says why a name was refused, in place.
struct RenameSheet: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $model.renameText)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit { model.confirmRename() }
                        .accessibilityIdentifier("rename-field")
                } footer: {
                    if let message = model.renameMessage { Text(message).foregroundStyle(.red).accessibilityIdentifier("rename-message") }
                }
            }
            .navigationTitle("Rename Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.cancelRename() } }
                ToolbarItem(placement: .confirmationAction) { Button("Rename") { model.confirmRename() } }
            }
        }
        .presentationDetents([.height(220)])
        .onAppear { focused = true }
        .onDisappear { model.cancelRename() }
    }
}


/// The cloud icon at the right edge of a playlist row. A crossed-out cloud means the playlist is only on this phone and
/// tapping it offers to move it to iCloud; an outline cloud means it is already in iCloud and does nothing.
struct PlaylistCloudIcon: View {
    let entry: PlaylistEntry
    let tapped: () -> Void

    private var state: CloudIconState { entry.location == .iCloud ? .outline : .crossedOut }

    var body: some View {
        Button {
            if cloudIconTapAction(state: state, kind: .playlist) == .openSyncDialog(.playlist) { tapped() }
        } label: {
            Image(systemName: state == .outline ? "icloud" : "icloud.slash")
                .foregroundStyle(.secondary)
                .frame(width: cloudIconDrawnSize.width, height: cloudIconDrawnSize.height)
                .frame(minWidth: minimumCloudIconTapSize.width, minHeight: minimumCloudIconTapSize.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state == .outline ? "In iCloud" : "Only on this iPhone. Moves it to iCloud.")
        .accessibilityIdentifier("playlist-cloud-icon")
    }
}
