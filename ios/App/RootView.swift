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
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    /// The size class the forms follow: the system's, or the rig's reading of its fixed width (a frame alone does not
    /// change the size class, and a 320-point window is compact).
    private var effectiveSizeClass: UserInterfaceSizeClass? {
        if let fixedWidth { return Double(fixedWidth) < IPadLayout.rigCompactMaximumWidth ? .compact : .regular }
        return sizeClass
    }

    /// Which form this window takes: the stack, or two columns.
    var plan: ColumnPlan {
        IPadLayout.columnPlan(width: effectiveSizeClass.map { $0 == .compact ? .compact : .regular })
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
            case .two: columns
            }
        }
        .onChange(of: plan, initial: true) { _, plan in
            model.isWideWindow = plan != .stack
            model.cardOpen = false
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

    /// The iPad's form: Playlists in the sidebar and the chosen playlist's songs beside it. The player floats over the songs
    /// as a glass bar and opens as a card, as on the iPhone. In portrait, and at large type sizes, the sidebar folds away
    /// behind its button.
    private var columns: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            PlaylistsView(selection: Binding(get: { model.selectedPlaylist }, set: { if let url = $0 { model.openFromList(url, in: plan) } else { model.select(nil, in: plan) } }))
        } detail: {
            HStack(spacing: 0) {
                Group {
                    if let url = model.selectedPlaylist, let session = model.openSession(for: url) {
                        PlaylistView(session: session)
                    } else if let url = model.selectedPlaylist, model.opening[url] != nil {
                        ProgressView().accessibilityLabel("Opening").accessibilityIdentifier("songs-opening")
                    } else {
                        ContentUnavailableView("No playlist chosen", systemImage: "music.note.list", description: Text("Choose a playlist"))
                            .accessibilityIdentifier("songs-empty")
                    }
                }
                .overlay { PlayerChrome() }
                // The lyrics have a panel of their own beside the songs, opened from the toolbar, not a place in the player.
                if model.lyricsPanelShown {
                    Divider()
                    LyricsPanel(embedded: true)
                        .frame(width: Self.lyricsPanelWidth)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeInOut(duration: Chrome.cardResizeDuration), value: model.lyricsPanelShown)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private static let lyricsPanelWidth: CGFloat = 380
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
                            PlaylistCloudIcon(entry: entry, opening: model.opening[entry.url]) { model.beginSync(entry) }.padding(.trailing, 28)
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
                    Button { model.openFromList(entry.url, in: .stack) } label: {
                        row(entry).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                        .overlay(alignment: .trailing) {
                            PlaylistCloudIcon(entry: entry, opening: model.opening[entry.url]) { model.beginSync(entry) }.padding(.trailing, 28)
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
            case .ok(let count):
                if let progress = model.opening[entry.url], progress.isShown {
                    Text(progress.label).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("opening-label")
                } else {
                    Text("\(count) \(count == 1 ? "song" : "songs")").font(.caption).foregroundStyle(.secondary)
                }
            case .loading: EmptyView()
            case .damaged: Text("Can't be read").font(.caption).foregroundStyle(.secondary)
            case .newerVersion: Text("Made by a newer version of Playaway").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The banner above a playlist's songs while some of them need this device to be allowed to read their folder (story 41).
struct RestoreBanner: View {
    let plan: RecoveryPlan
    let restore: () -> Void
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }

    var body: some View {
        let songs = plan.trackCount, folders = plan.folders.count
        HStack(spacing: 12) {
            Text("Playaway needs your OK to play \(songs) \(songs == 1 ? "song" : "songs") from \(folders) \(folders == 1 ? "folder" : "folders") on this \(device)")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Restore", action: restore)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("restore-button")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("restore-banner")
        .accessibilityLabel("\(songs) songs need access")
    }
}

/// What the person is about to do, before the system's chooser appears: which folders, how many songs, and what to tap.
struct RestoreExplainer: View {
    @EnvironmentObject var model: AppModel
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if let session = model.restoreSession, let plan = model.recoveryPlan(for: session) {
                    Text("Playaway needs access to \(plan.folders.count == 1 ? "1 folder" : "\(plan.folders.count) folders") to restore \(plan.trackCount) \(plan.trackCount == 1 ? "song" : "songs") on this \(device).")
                        .font(.headline)
                    ForEach(plan.folders, id: \.drivePath) { folder in
                        Label("\(folder.name): \(folder.trackCount) \(folder.trackCount == 1 ? "song" : "songs")", systemImage: "folder")
                    }
                    if let first = plan.folders.first {
                        Text("On the next screen, tap Open to let Playaway use “\(first.name)” on this \(device). You only do this once for each folder.")
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Continue") { model.continueRestore() }
                    .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
                    .accessibilityIdentifier("restore-continue")
                Button("Not Now") { model.cancelRestore() }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("restore-not-now")
            }
            .padding()
            .navigationTitle("Restore songs")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("restore-explainer")
        .presentationDetents([.medium])
    }
}

/// The system's folder chooser, opened at a hinted folder. SwiftUI's own file importer cannot set where it opens.
struct FolderPicker: UIViewControllerRepresentable {
    let hint: URL?
    let picked: (URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(picked: picked) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        if let hint { picker.directoryURL = hint }     // a hint: a wrong one only makes the chooser open where it last was
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let picked: (URL?) -> Void
        init(picked: @escaping (URL?) -> Void) { self.picked = picked }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { picked(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { picked(nil) }
    }
}

/// Shown while Playaway searches a folder for the songs: a big iCloud folder can take a while, and nothing here should
/// look frozen. The count of items looked at moves, and Cancel stops the search.
struct RestoreProgressCard: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let progress = model.restoreProgress {
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text("Restoring your songs").font(.headline)
                    Text(progress.looked == 0 ? "Looking in “\(progress.folder)”…" : "Looked at \(progress.looked) items in “\(progress.folder)”")
                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    Button("Cancel") { model.cancelRestoreSearch() }
                        .buttonStyle(.bordered).accessibilityIdentifier("restore-cancel")
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("restore-progress")
            }
            .transition(.opacity)
        }
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
                    if model.isWideWindow {
                        Button { model.lyricsPanelShown.toggle() } label: { Image(systemName: "quote.bubble") }
                            .accessibilityLabel("Lyrics").accessibilityIdentifier("lyrics-panel-button")
                    }
                    Button { importing = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add Songs")
                        .keyboardShortcut("o", modifiers: .command)
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
                let before = Set(session.playlist.tracks.map(\.id))
                session.add(urls)
                model.considerNudge(after: session.playlist.tracks.filter { !before.contains($0.id) })
                scoped.forEach { $0.stopAccessingSecurityScopedResource() }
            }
            // Story 41: songs this device may not read yet. One banner with the count; the explanation, then the system's chooser.
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if let plan = model.recoveryPlan(for: session) {
                        RestoreBanner(plan: plan) { model.beginRestore(for: session) }
                    }
                    #if DEBUG
                    // Test aid: adds a song from a drive folder the way the file chooser would (the chooser cannot be driven by a test).
                    if ProcessInfo.processInfo.arguments.contains("-PlayawayFakeDrive") {
                        Button("Add from Drive") { model.addFakeDriveSong(to: session) }
                            .font(.caption2).accessibilityIdentifier("add-fake-drive-song")
                    }
                    #endif
                }
            }
            .sheet(isPresented: Binding(get: { model.restoreSession === session }, set: { if !$0 { model.restoreSheetDismissed() } })) {
                switch model.restorePhase {
                case .explain: RestoreExplainer().environmentObject(model)
                case .pick:
                    #if DEBUG
                    if AppModel.fakesTheChooserSheet { FakeSheetChooser() } else { FolderPicker(hint: model.restoreHint) { model.folderPicked($0) }.ignoresSafeArea() }
                    #else
                    FolderPicker(hint: model.restoreHint) { model.folderPicked($0) }.ignoresSafeArea()
                    #endif
                }
            }
            .overlay { RestoreProgressCard() }
            .fileImporter(isPresented: $model.locateShown, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
                model.locate(try? result.get().first)
            }
            .sheet(isPresented: $model.nudgePickerShown) {
                FolderPicker(hint: nil) { model.nudgeFolderPicked($0) }.ignoresSafeArea()
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
    /// While the playlist is being read and the wait is long enough to notice: the cloud becomes a pie of how far it is.
    var opening: OpeningProgress? = nil
    let tapped: () -> Void

    private var state: CloudIconState { entry.location == .iCloud ? .outline : .crossedOut }

    var body: some View {
        if let opening, opening.isShown {
            OpeningPie(fraction: opening.fraction)
                .frame(width: cloudIconDrawnSize.width, height: cloudIconDrawnSize.height)
                .frame(minWidth: minimumCloudIconTapSize.width, minHeight: minimumCloudIconTapSize.height)
                .accessibilityLabel(opening.label)
                .accessibilityIdentifier("playlist-opening-pie")
        } else {
            cloudButton
        }
    }

    private var cloudButton: some View {
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

#if DEBUG
/// Test aid: stands in for the system's folder chooser inside the real sheet. The system closes the sheet when Open is
/// tapped and then reports the folder; this does the same, in that order.
struct FakeSheetChooser: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button("Open") {
            let answer = model.fakeChooserAnswer()
            dismiss()
            DispatchQueue.main.async { model.folderPicked(answer) }
        }
        .accessibilityIdentifier("fake-chooser-open")
    }
}
#endif

/// A small pie that fills clockwise from the top.
struct OpeningPie: View {
    let fraction: Double
    var body: some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.4), lineWidth: 1.5)
            Circle().trim(from: 0, to: max(0.02, fraction)).stroke(.tint, style: StrokeStyle(lineWidth: 5, lineCap: .butt))
                .scaleEffect(0.5)
                .rotationEffect(.degrees(-90))
        }
    }
}
