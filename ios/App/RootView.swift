import SwiftUI
import UniformTypeIdentifiers
import PlayawayCore

struct RootView: View {
    @EnvironmentObject var model: AppModel

    /// Test rig (story 38): `-PlayawayWindowWidth <points>` (or that key in the app's defaults) fixes the root's width,
    /// so the compact and two-column forms can be tried on any simulator without multitasking gestures.
    static let windowWidthKey = "PlayawayWindowWidth"
    private var fixedWidth: CGFloat? {
        #if DEBUG
        let width = UserDefaults.standard.integer(forKey: Self.windowWidthKey)
        return width > 0 ? CGFloat(width) : nil
        #else
        return nil
        #endif
    }

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var windowWidth: CGFloat = 0

    /// The size class the forms follow: the system's, or the rig's reading of its fixed width (a frame alone does not
    /// change the size class, and a 320-point window is compact).
    private var effectiveSizeClass: UserInterfaceSizeClass? {
        if let fixedWidth { return Double(fixedWidth) < IPadLayout.rigCompactMaximumWidth ? .compact : .regular }
        return sizeClass
    }

    /// Which columns this window shows (story 38): the size class and type size, and the measured width.
    var plan: ColumnPlan {
        let width: WidthClass? = effectiveSizeClass.map { $0 == .compact ? .compact : .regular }
        return IPadLayout.columnPlan(width: width, isAccessibilityTypeSize: typeSize.isAccessibilitySize, windowWidth: Double(windowWidth))
    }

    var body: some View {
        if let fixedWidth {
            content
                .environment(\.horizontalSizeClass, effectiveSizeClass)
                .frame(width: fixedWidth).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            content
        }
    }

    private var content: some View {
        Group {
            switch plan {
            case .stack: stack
            case .two, .three: columns
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
        .onChange(of: plan, initial: true) { _, plan in
            columnVisibility = plan == .three ? .all : .doubleColumn
            if plan != .stack { model.cardOpen = false }
        }
        .modifier(ModelAlerts())
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

    /// The iPhone's form, unchanged: Playlists pushes Playlist, the floating controller and the card over it.
    private var stack: some View {
        NavigationStack(path: $model.path) {
            PlaylistsView()
                .navigationDestination(for: URL.self) { url in
                    if let session = model.session(for: url) { PlaylistView(session: session) }
                    else { ContentUnavailableView("Playlist unavailable", systemImage: "exclamationmark.triangle") }
                }
        }
        .overlay { PlayerChrome() }
    }

    /// The iPad's form: Playlists in the sidebar, the chosen playlist's songs in the middle, Now Playing at the right.
    private var columns: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            PlaylistsView(selection: Binding(get: { model.selectedPlaylist }, set: { model.select($0, in: plan) }))
        } content: {
            if let url = model.selectedPlaylist, let session = model.session(for: url) {
                PlaylistView(session: session)
            } else {
                ContentUnavailableView("No playlist chosen", systemImage: "music.note.list", description: Text("Choose a playlist"))
                    .accessibilityIdentifier("songs-empty")
            }
        } detail: {
            NowPlayingColumn()
        }
        .navigationSplitViewStyle(.balanced)
    }
}

struct PlaylistsView: View {
    @EnvironmentObject var model: AppModel
    /// In columns the list is a selection; in the stack (nil) its rows navigate.
    var selection: Binding<URL?>? = nil
    @State private var creating = false
    @State private var newName = ""
    @State private var errorText: String?

    var body: some View {
        Group {
            if model.entries.isEmpty {
                ContentUnavailableView("No Playlists", systemImage: "music.note.list",
                                       description: Text("Tap + to make your first playlist."))
            } else if let selection {
                List(model.entries, selection: selection) { entry in
                    row(entry)
                        .frame(maxWidth: .infinity, alignment: .leading)      // the whole row, so the icon sits at its end
                        .contentShape(Rectangle())
                        .tag(entry.url)
                        .dropDestination(for: URL.self) { urls, _ in model.add(urls, toPlaylistAt: entry.url) }
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
            ToolbarItem(placement: .topBarLeading) {
                Button { model.experimentsShown = true } label: { Image(systemName: "flask") }
                    .accessibilityLabel("Experiments")
                    .accessibilityIdentifier("experiments-button")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { newName = ""; creating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New Playlist")
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: $model.experimentsShown) { ExperimentsView() }
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

/// The notice above a playlist's songs while this device needs permission for their iCloud Drive folder (story 40).
struct AccessNotice: View {
    let folder: String
    let allow: () -> Void
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("These songs are in your iCloud Drive folder “\(folder)”, which Playaway is not yet allowed to read on this \(device). Tap Allow, then choose “\(folder)” in the chooser and tap Open.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Button("Allow", action: allow)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("access-allow")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("access-notice")
        .accessibilityLabel("Needs access to \(folder)")
    }
}

struct PlaylistView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: PlaylistSession
    @State private var importing = false

    var body: some View {
        SongTable(session: session)
            // Files dropped on the songs (from Files, or another playlist's row) go the way Add Songs does.
            .dropDestination(for: URL.self) { urls, _ in
                let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
                session.add(urls)
                scoped.forEach { $0.stopAccessingSecurityScopedResource() }
                return true
            }
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
                        .keyboardShortcut("o", modifiers: .command)
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
                session.add(urls)
                scoped.forEach { $0.stopAccessingSecurityScopedResource() }
            }
            // Story 40: songs in an iCloud Drive folder this device has not been allowed to read. One tap opens the
            // system's folder chooser; the grant covers the folder and everything in it from then on.
            .safeAreaInset(edge: .top, spacing: 0) {
                if let folder = model.accessNeeded(for: session) {
                    AccessNotice(folder: folder) { model.allowAccess(for: session) }
                }
            }
            .fileImporter(isPresented: $model.folderPickerShown, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                model.folderPicked(try? result.get().first)
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
