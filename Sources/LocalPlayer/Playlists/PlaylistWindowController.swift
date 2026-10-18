import PlayawayCore
import AppKit
import Combine
import UniformTypeIdentifiers

/// The window of one playlist, with three areas top to bottom and nothing else: what is playing with its controls
/// (including shuffle and repeat), the tracks, and a slim footer with add, the track count and remove. Standard
/// AppKit controls only.
@MainActor
final class PlaylistWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    private static let rowDragType = NSPasteboard.PasteboardType("com.localplayer.playlist.row")
    private static let initialSize = NSSize(width: 480, height: 620)
    private static let minimumSize = NSSize(width: 420, height: 420)
    private static let contentInset: CGFloat = 20
    private static let groupSpacing: CGFloat = 14
    private static let rowSpacing: CGFloat = 8
    private static let tableMinimumHeight: CGFloat = 160
    private static let footerHeight: CGFloat = 28
    private static let footerSymbolSize: CGFloat = 12
    private static let rowHeight: CGFloat = 30
    private static let cellIdentifier = NSUserInterfaceItemIdentifier("TrackCell")
    private static let hazardIconSize: CGFloat = 16
    /// Window open and close animations. Tests turn them off: closing animated windows in a headless test process
    /// has crashed Core Animation's transform-animation teardown.
    static var animatesWindows = true
    static let emptyHintText = "This playlist is empty. Drag audio files here, or choose Add Files."

    private let playlistDocument: PlaylistDocument
    private let services: AppServices
    private var cancellables = Set<AnyCancellable>()

    let tableView = NSTableView()
    let scrollView = NSScrollView()
    let addButton = NSButton()
    let removeButton = NSButton()
    let countLabel = NSTextField(labelWithString: "")
    let emptyHint = NSTextField(wrappingLabelWithString: PlaylistWindowController.emptyHintText)
    /// The playlist's iCloud sync switch, to the right of the name in the title bar, and the reason it is disabled.
    let syncButton = NSButton()
    let syncReason = NSTextField(labelWithString: "")
    private let syncRow = NSStackView()
    /// Test seams: the Playlist and Files dialogs are sheets, so tests answer them here instead and read the messages.
    var askPlaylistChoice: (() async -> PlaylistChoice)?
    var askFilesChoice: (() async -> FilesChoice)?
    private(set) var filesAsked = 0
    private(set) var filesMessages: [String] = []
    /// True once a press of the switch has run to the end (the intake flow included), for tests to wait on.
    private(set) var intakeFinished = false
    /// The symbol the switch shows (symbol images carry no name of their own).
    private(set) var syncSymbolName = ""
    let transport: TransportControlsView
    let modes: PlayModeControls

    /// Test seams: the panels are modal, so tests replace them with stubs that return a chosen URL.
    var chooseFilesToAdd: @MainActor () -> [URL]? = PlaylistWindowController.runAddPanel
    var chooseFileToLocate: @MainActor () -> URL? = PlaylistWindowController.runLocatePanel

    init(document: PlaylistDocument) {
        playlistDocument = document
        services = document.services
        let modes = PlayModeControls(settings: document.services.settings)
        self.modes = modes
        transport = TransportControlsView(viewModel: document.services.transport, modes: modes)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.initialSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: true)
        window.minSize = Self.minimumSize
        window.isReleasedWhenClosed = false
        if !Self.animatesWindows { window.animationBehavior = .none }
        super.init(window: window)
        shouldCascadeWindows = true
        buildContent(in: window)
        installSyncSwitch(in: window)
        bind()
        reload()
    }

    // MARK: iCloud sync switch (story 18)

    private func installSyncSwitch(in window: NSWindow) {
        syncButton.title = ""
        syncButton.imagePosition = .imageOnly
        syncButton.isBordered = false
        syncButton.target = self
        syncButton.action = #selector(syncPressed(_:))
        syncButton.setAccessibilityIdentifier(ElementID.sync)
        syncReason.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        syncReason.textColor = .secondaryLabelColor
        syncReason.setAccessibilityIdentifier(ElementID.syncReason)
        let row = syncRow
        row.addArrangedSubview(syncReason)
        row.addArrangedSubview(syncButton)
        row.orientation = .horizontal
        row.spacing = Self.rowSpacing
        row.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: Self.rowSpacing)
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = row
        accessory.layoutAttribute = .trailing
        window.addTitlebarAccessoryViewController(accessory)
        services.cloud.changes.receive(on: DispatchQueue.main).sink { [weak self] in
            self?.refreshSync()
            self?.refreshRows()
        }.store(in: &cancellables)
        services.downloadChanges.sink { [weak self] in self?.refreshRows() }.store(in: &cancellables)
        refreshSync()
    }

    /// The switch follows where the file is and whether iCloud can be reached; the mapping is the shared one.
    func refreshSync() {
        let presentation = playlistDocument.sync.presentation
        syncSymbolName = presentation.symbolName
        syncButton.image = NSImage(systemSymbolName: presentation.symbolName, accessibilityDescription: presentation.accessibilityLabel)
        syncButton.contentTintColor = playlistDocument.sync.state == .on ? .controlAccentColor : .secondaryLabelColor
        syncButton.isEnabled = presentation.isEnabled
        syncButton.toolTip = presentation.reason ?? presentation.accessibilityLabel
        syncButton.setAccessibilityLabel(presentation.accessibilityLabel)
        syncButton.setAccessibilityValue(presentation.accessibilityValue)
        syncReason.stringValue = presentation.reason ?? ""
        syncReason.isHidden = presentation.reason == nil
        syncRow.frame.size = syncRow.fittingSize          // an accessory view has no size until shown; the element walk needs one
    }

    /// Pressing the crossed-out cloud turns sync on; pressing the activated cloud, or a disabled switch, does nothing.
    @objc func syncPressed(_ sender: Any?) {
        guard playlistDocument.sync.state == .off, playlistDocument.sync.presentation.isEnabled else { return }
        let presenter: PlaylistPromptPresenting = askPlaylistChoice.map { ClosurePlaylistPresenter($0) } ?? MacPlaylistPresenter(window: window)
        let filesPresenter = makeFilesPresenter()
        intakeFinished = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            await playlistDocument.sync.turnOn(presenter: presenter, filesPresenter: filesPresenter)
            refreshSync()
            refreshRows()                      // the rows' clouds appear now, also when no file moved (Add Without Syncing)
            intakeFinished = true
        }
    }

    /// The 'Sync with iCloud: Files' sheet, or the test seam standing in for it.
    private func makeFilesPresenter() -> FilesPromptPresenting {
        askFilesChoice.map { ask in
            ClosureFilesPresenter(ask: { [weak self] in self?.filesAsked += 1; return await ask() },
                                  shown: { [weak self] in self?.filesMessages.append($0) })
        } ?? MacFilesPresenter(window: window)
    }

    // MARK: Song rows in iCloud (story 20)

    private func songURL(for track: Track) -> URL? { playlistDocument.songURL(for: track) }

    /// What a row's cloud icon shows: the shared row rule over this Mac's answer about the file and the download
    /// coordinator's. Only a synced playlist shows cloud state (an unsynced one shows nothing, as on the iPhone).
    func cloudDisplay(for track: Track) -> SongRowCloudDisplay? {
        guard playlistDocument.sync.state == .on else { return nil }
        guard let url = songURL(for: track) else {
            return playlistDocument.unfoundKind(of: track).flatMap(SongRowCloudDisplay.unfound)   // story 42: the question-mark cloud
        }
        let tracked = services.downloads.state(of: MacSongs.id(for: url))
        return SongRowCloudDisplay(presence: services.cloudSongs.presence(of: url), tracked: tracked == .onThisDevice ? nil : tracked)
    }

    /// A click on a row's cloud icon follows the shared rule (story 31): crossed-out asks the Files question for that
    /// song only, the pie cancels, the exclamation mark retries, the outline does nothing. No click plays the row.
    func cloudIconClicked(_ track: Track) {
        if cloudDisplay(for: track)?.icon == .elsewhere { services.notices.show(.addedElsewhere); return }
        guard let display = cloudDisplay(for: track), let url = songURL(for: track) else { return }
        switch cloudIconTapAction(state: display.icon, kind: .song) {
        case .openSyncDialog:
            let presenter = makeFilesPresenter()
            Task { @MainActor [weak self] in
                guard let self else { return }
                await playlistDocument.sync.bringSong(track, presenter: presenter)
                refreshRows()
            }
        case .cancelDownload, .cancelSync:
            services.cancelDownload(of: MacSongs.id(for: url))
        case .retryDownload:
            services.retryDownload(of: track, at: url, in: playlistDocument)
        case .none, .restoreAccess, .explainElsewhere:     // restoreAccess belongs to the iPhone and iPad: the Mac reads iCloud Drive directly
            break
        }
    }

    /// Updates the cloud icons and dimming of the rows on screen without reloading the table.
    private func refreshRows() {
        let tracks = playlistDocument.playlist.tracks
        let visible = tableView.rows(in: tableView.visibleRect)
        for row in visible.location..<(visible.location + visible.length) where tracks.indices.contains(row) {
            (tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? TrackCellView)?.cloud = cloudDisplay(for: tracks[row])
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Layout

    private func buildContent(in window: NSWindow) {
        configureTable()
        configureTrackButtons()

        let tracksGroup = NSStackView(views: [scrollView, emptyHint, footer()])
        tracksGroup.orientation = .vertical
        tracksGroup.alignment = .leading
        tracksGroup.spacing = Self.rowSpacing

        let root = NSStackView(views: [transport, tracksGroup])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = Self.groupSpacing
        root.edgeInsets = NSEdgeInsets(top: Self.contentInset, left: Self.contentInset,
                                       bottom: Self.contentInset, right: Self.contentInset)
        window.contentView = root

        for view in [transport, scrollView, tracksGroup] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -2 * Self.contentInset).isActive = true
        }
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.tableMinimumHeight).isActive = true
        emptyHint.widthAnchor.constraint(equalTo: tracksGroup.widthAnchor).isActive = true
    }

    /// Add Files on the left, the track count in the middle, Remove on the right. The count stays centred
    /// whatever the width of the buttons.
    private func footer() -> NSView {
        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        for view in [addButton, countLabel, removeButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            footer.addSubview(view)
            view.centerYAnchor.constraint(equalTo: footer.centerYAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            footer.heightAnchor.constraint(equalToConstant: Self.footerHeight),
            addButton.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            countLabel.centerXAnchor.constraint(equalTo: footer.centerXAnchor),
            removeButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            addButton.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -Self.rowSpacing),
            countLabel.trailingAnchor.constraint(lessThanOrEqualTo: removeButton.leadingAnchor, constant: -Self.rowSpacing),
        ])
        return footer
    }

    private func configureTable() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(ElementID.tracks))   // part of the tracks element
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .inset
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.rowHeight = Self.rowHeight
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)
        tableView.registerForDraggedTypes([.fileURL, Self.rowDragType])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        let menu = NSMenu()
        menu.delegate = self
        tableView.menu = menu
        tableView.setAccessibilityIdentifier(ElementID.tracks)
        tableView.setAccessibilityLabel("Tracks")

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.setAccessibilityIdentifier(ElementID.tracks)
        scrollView.setAccessibilityElement(true)
        scrollView.setAccessibilityLabel("Tracks")
        emptyHint.setAccessibilityIdentifier(ElementID.emptyHint)
        emptyHint.textColor = .secondaryLabelColor
    }

    private func configureTrackButtons() {
        let small = NSImage.SymbolConfiguration(pointSize: Self.footerSymbolSize, weight: .semibold)
        addButton.title = "Add Files"
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Files")?.withSymbolConfiguration(small)
        addButton.imagePosition = .imageLeading
        addButton.isBordered = false
        addButton.contentTintColor = .controlAccentColor
        addButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        addButton.target = self
        addButton.action = #selector(addFiles(_:))
        addButton.setAccessibilityIdentifier(ElementID.add)
        addButton.setAccessibilityLabel("Add Files")
        removeButton.title = ""
        removeButton.image = NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove")?.withSymbolConfiguration(small)
        removeButton.imagePosition = .imageOnly
        removeButton.isBordered = false
        removeButton.contentTintColor = .secondaryLabelColor
        removeButton.toolTip = "Remove"
        removeButton.target = self
        removeButton.action = #selector(removeSelectedTracks(_:))
        removeButton.setAccessibilityIdentifier(ElementID.remove)
        removeButton.setAccessibilityLabel("Remove")
        countLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        countLabel.textColor = .secondaryLabelColor
        countLabel.setAccessibilityIdentifier(ElementID.count)
        countLabel.setAccessibilityLabel("Number of tracks")
    }

    // MARK: Binding

    private func bind() {
        playlistDocument.changes.sink { [weak self] in self?.reload() }.store(in: &cancellables)
        playlistDocument.statuses.changes.sink { [weak self] in self?.reload() }.store(in: &cancellables)
        if let marks = services.marks as? ReadabilityMarkStore {
            marks.changes.sink { [weak self] in self?.reload() }.store(in: &cancellables)
        }
        // The playing marker follows the engine (play, pause, stop) and the playlist's own current track.
        services.engine.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshMarkers() }.store(in: &cancellables)
        playlistDocument.player.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.services.transport.refresh()
                self?.refreshMarkers()
            }.store(in: &cancellables)
    }

    /// Which marker a row shows: playing or paused for this playlist's current track, otherwise none.
    private func marker(for track: Track) -> TrackCellView.Marker {
        guard playlistDocument.player.isSessionActive, playlistDocument.player.current?.id == track.id else { return .none }
        switch services.engine.state {
        case .playing: return .playing
        case .paused: return .paused
        case .idle: return .none
        }
    }

    /// Updates the markers of the rows on screen without reloading the table, so selection and scrolling stay.
    private func refreshMarkers() {
        let tracks = playlistDocument.playlist.tracks
        let visible = tableView.rows(in: tableView.visibleRect)
        for row in visible.location..<(visible.location + visible.length) where tracks.indices.contains(row) {
            (tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? TrackCellView)?.marker = marker(for: tracks[row])
        }
    }

    func reload() {
        let selected = tableView.selectedRowIndexes
        tableView.reloadData()
        let valid = selected.filteredIndexSet { $0 < tableView.numberOfRows }
        tableView.selectRowIndexes(valid, byExtendingSelection: false)
        let count = playlistDocument.playlist.tracks.count
        emptyHint.isHidden = count != 0
        countLabel.stringValue = count == 1 ? "1 track" : "\(count) tracks"
        countLabel.isHidden = count == 0
        removeButton.isEnabled = !tableView.selectedRowIndexes.isEmpty
        services.transport.refresh()      // "Track 2 of 5" follows edits
        refreshSync()
    }

    // MARK: Table data

    func numberOfRows(in tableView: NSTableView) -> Int { playlistDocument.playlist.tracks.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard playlistDocument.playlist.tracks.indices.contains(row) else { return nil }
        let track = playlistDocument.playlist.tracks[row]
        let cell = (tableView.makeView(withIdentifier: Self.cellIdentifier, owner: self) as? TrackCellView) ?? TrackCellView()
        cell.identifier = Self.cellIdentifier
        let missing = playlistDocument.statuses.isMissing(track.id)
        cell.configure(name: TransportControlsView.displayTitle(forFileName: track.reference.fileName), missing: missing,
                       hazard: services.marks.mark(of: track) == .unreadable, marker: marker(for: track),
                       cloud: cloudDisplay(for: track))
        cell.cloudClicked = { [weak self] in self?.cloudIconClicked(track) }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        removeButton.isEnabled = !tableView.selectedRowIndexes.isEmpty
    }

    // MARK: Row actions

    @objc private func rowDoubleClicked() {
        playRow(tableView.clickedRow)
    }

    /// What a double-click on a row does: play that track.
    func playRow(_ row: Int) {
        guard playlistDocument.playlist.tracks.indices.contains(row) else { return }
        playlistDocument.player.play(track: playlistDocument.playlist.tracks[row])
    }

    @objc func addFiles(_ sender: Any?) {
        guard let urls = chooseFilesToAdd(), !urls.isEmpty else { return }
        dropFiles(urls)
    }

    /// Songs arriving by a drop or by Add Files (story 21): the rows are added as they always were (unsupported files
    /// rejected, new rows at the end), then the sync controller takes the added songs through the one shared Files
    /// flow when the playlist is synced, and does nothing more when it is not. The window holds no flow logic.
    func dropFiles(_ urls: [URL]) {
        intakeFinished = false
        let added = playlistDocument.addFiles(urls).added
        let presenter = makeFilesPresenter()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await playlistDocument.sync.bringAdded(added, presenter: presenter)
            refreshRows()
            intakeFinished = true
        }
    }

    /// Delete and Forward Delete reach here from the table through the responder chain.
    override func deleteBackward(_ sender: Any?) { removeSelectedTracks(sender) }
    override func deleteForward(_ sender: Any?) { removeSelectedTracks(sender) }

    /// Return plays the selected track, as a double-click does.
    override func insertNewline(_ sender: Any?) {
        playRow(tableView.selectedRow)
    }

    @objc func removeSelectedTracks(_ sender: Any?) {
        let rows = Array(tableView.selectedRowIndexes)
        guard !rows.isEmpty else { return }
        try? playlistDocument.removeTracks(at: rows)
    }

    @objc func locateTrack(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let url = chooseFileToLocate() else { return }
        _ = playlistDocument.relinker.relink(trackID: id, to: url, in: playlistDocument)
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(removeSelectedTracks(_:)) { return !tableView.selectedRowIndexes.isEmpty }
        return true
    }

    // MARK: Context menu: Locate is offered on a missing track's row only

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        locateMenuItems(forRow: tableView.clickedRow).forEach(menu.addItem)
    }

    /// Locate is offered on a missing track's row only; present tracks and empty space get no menu.
    func locateMenuItems(forRow row: Int) -> [NSMenuItem] {
        guard playlistDocument.playlist.tracks.indices.contains(row) else { return [] }
        let track = playlistDocument.playlist.tracks[row]
        guard playlistDocument.statuses.isMissing(track.id) else { return [] }
        let item = NSMenuItem(title: "Locate…", action: #selector(locateTrack(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = track.id
        return [item]
    }

    // MARK: Drag and drop

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.rowDragType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        if info.draggingSource as? NSTableView === tableView {
            tableView.setDropRow(row, dropOperation: .above)
            return .move
        }
        if info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            tableView.setDropRow(tableView.numberOfRows, dropOperation: .above)
            return .copy
        }
        return []
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        let pasteboard = info.draggingPasteboard
        if info.draggingSource as? NSTableView === tableView {
            let sources = (pasteboard.pasteboardItems ?? []).compactMap { $0.string(forType: Self.rowDragType).flatMap(Int.init) }
            return reorder(rows: sources, toBefore: row)
        }
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { return false }
        dropFiles(urls)
        return true
    }

    /// Moves the dragged rows so they sit before `row`, keeping their relative order.
    @discardableResult
    func reorder(rows sources: [Int], toBefore row: Int) -> Bool {
        let tracks = playlistDocument.playlist.tracks
        let sorted = Array(Set(sources)).sorted()
        guard !sorted.isEmpty, sorted.allSatisfy({ tracks.indices.contains($0) }) else { return false }
        let moving = sorted.map { tracks[$0] }
        var remaining = tracks
        for index in sorted.reversed() { remaining.remove(at: index) }
        let insertAt = row - sorted.filter { $0 < row }.count
        remaining.insert(contentsOf: moving, at: min(max(insertAt, 0), remaining.count))
        for (target, track) in remaining.enumerated() {
            guard let current = playlistDocument.playlist.index(ofTrackWithID: track.id), current != target else { continue }
            try? playlistDocument.moveTrack(from: current, to: target)
        }
        return true
    }

    // MARK: Panels

    private static func runAddPanel() -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mp3, .wav, .mpeg4Audio]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add"
        return panel.runModal() == .OK ? panel.urls : nil
    }

    private static func runLocatePanel() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Locate"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// A row: a leading glyph slot, the name, and at the right-hand end the cloud icon of a synced playlist's song
/// (story 20). The slot shows the hazard icon for a track that could not be played, or the playing or paused marker
/// for the current track. The name is greyed when the file is missing or not on this Mac, and accent-coloured and
/// semibold while it is the current track.
@MainActor
final class TrackCellView: NSTableCellView {
    enum Marker { case none, playing, paused }

    private static let glyphSize: CGFloat = 16
    private static let spacing: CGFloat = 6
    private static let nameSize: CGFloat = 14
    /// The cloud icons are quiet: half opacity, like the phone's secondary colour. A download in progress and a
    /// failure are full strength so they are seen.
    private static let quietCloudOpacity: CGFloat = 0.5
    private let glyphView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    /// The cloud icon, a control with story 31's click rules; hidden for an unsynced playlist.
    let cloudButton = NSButton()
    private let pie = PieIndicator()
    private var name = ""
    private var missing = false
    private var hazard = false
    private(set) var titleWeight: NSFont.Weight = .regular
    var cloudClicked: (() -> Void)?

    var marker: Marker = .none {
        didSet { if marker != oldValue { refresh() } }
    }

    /// What the cloud icon shows, nil for a song of an unsynced playlist.
    var cloud: SongRowCloudDisplay? {
        didSet { if cloud != oldValue { refresh() } }
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { refresh() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        nameField.lineBreakMode = .byTruncatingMiddle
        let stack = NSStackView(views: [glyphView, nameField])
        stack.spacing = Self.spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        cloudButton.title = ""
        cloudButton.imagePosition = .imageOnly
        cloudButton.isBordered = false
        cloudButton.target = self
        cloudButton.action = #selector(cloudPressed(_:))
        cloudButton.setAccessibilityIdentifier(ElementID.songCloud)
        cloudButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cloudButton)
        pie.translatesAutoresizingMaskIntoConstraints = false
        cloudButton.addSubview(pie)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.spacing),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: cloudButton.leadingAnchor, constant: -Self.spacing),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            glyphView.widthAnchor.constraint(equalToConstant: Self.glyphSize),
            cloudButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.spacing),
            cloudButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            cloudButton.widthAnchor.constraint(equalToConstant: cloudIconDrawnSize.width),
            cloudButton.heightAnchor.constraint(equalToConstant: cloudIconDrawnSize.height),
            pie.leadingAnchor.constraint(equalTo: cloudButton.leadingAnchor),
            pie.trailingAnchor.constraint(equalTo: cloudButton.trailingAnchor),
            pie.topAnchor.constraint(equalTo: cloudButton.topAnchor),
            pie.bottomAnchor.constraint(equalTo: cloudButton.bottomAnchor),
        ])
        textField = nameField
        imageView = glyphView
    }

    @objc private func cloudPressed(_ sender: Any?) { cloudClicked?() }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    func configure(name: String, missing: Bool, hazard: Bool, marker: Marker = .none, cloud: SongRowCloudDisplay? = nil) {
        self.name = name
        self.missing = missing
        self.hazard = hazard
        self.marker = marker
        self.cloud = cloud
        refresh()
    }

    /// A track that could not be played shows the hazard, never the playing marker.
    private var shownMarker: Marker { hazard ? .none : marker }

    private func refresh() {
        let emphasized = backgroundStyle == .emphasized
        nameField.stringValue = name
        titleWeight = shownMarker == .none ? .regular : .semibold
        nameField.font = .systemFont(ofSize: Self.nameSize, weight: titleWeight)
        if emphasized {
            nameField.textColor = .alternateSelectedControlTextColor
        } else {
            let dimmed = missing || cloud?.dimmed == true
            nameField.textColor = dimmed ? .disabledControlTextColor : (shownMarker == .none ? .labelColor : .controlAccentColor)
        }
        refreshCloud(emphasized: emphasized)
        let tint: NSColor = emphasized ? .alternateSelectedControlTextColor : .controlAccentColor
        switch (hazard, shownMarker) {
        case (true, _):
            glyphView.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Could not be played")
            glyphView.contentTintColor = emphasized ? tint : .systemYellow
            glyphView.setAccessibilityLabel("Could not be played")
            glyphView.isHidden = false
        case (_, .playing):
            glyphView.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Playing")
            glyphView.contentTintColor = tint
            glyphView.setAccessibilityLabel("Playing")
            glyphView.isHidden = false
        case (_, .paused):
            glyphView.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Paused")
            glyphView.contentTintColor = tint
            glyphView.setAccessibilityLabel("Paused")
            glyphView.isHidden = false
        default:
            glyphView.isHidden = true
        }
        // Colour alone must not carry the state: say it.
        let state: String
        switch (hazard, shownMarker, missing) {
        case (true, _, _): state = ", could not be played"
        case (_, .playing, _): state = ", playing"
        case (_, .paused, _): state = ", paused"
        case (_, _, true): state = ", file not found"
        default: state = ""
        }
        setAccessibilityLabel(name + state + cloudSpoken)
    }

    /// The cloud icon: outline, crossed-out, exclamation mark, or the pie of a download (a spinner while the system
    /// has not said how far it is). Hidden for an unsynced playlist.
    private func refreshCloud(emphasized: Bool) {
        guard let cloud else { cloudButton.isHidden = true; return }
        cloudButton.isHidden = false
        let quiet: NSColor = emphasized ? .alternateSelectedControlTextColor : .secondaryLabelColor
        var symbol: String?, tint = quiet, opacity = Self.quietCloudOpacity, elsewhereImage = false
        switch cloud.icon {
        case .crossedOut, .locked: symbol = "icloud.slash"     // locked never occurs on the Mac
        case .elsewhere: symbol = nil; elsewhereImage = true
        case .outline: symbol = "icloud"
        case .exclamation: symbol = "exclamationmark.icloud"; tint = emphasized ? quiet : .systemRed; opacity = 1
        case .pieDownload, .pieSync: opacity = 1
        }
        cloudButton.image = elsewhereImage ? Self.questionCloud(description: cloudLabel)
            : symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: cloudLabel) }
        cloudButton.contentTintColor = tint
        cloudButton.alphaValue = opacity
        pie.isHidden = symbol != nil || elsewhereImage
        pie.fraction = cloud.fraction
        cloudButton.toolTip = cloudLabel
        cloudButton.setAccessibilityLabel(cloudLabel)
        cloudButton.setAccessibilityValue(cloud.fraction.map { $0 > 0 ? "\(Int($0 * 100)) percent" : "" } ?? "")
    }

    private var cloudLabel: String {
        guard let cloud else { return "" }
        switch cloud.icon {
        case .crossedOut: return "Not in iCloud"
        case .outline: return cloud.dimmed ? "In iCloud, not on this Mac" : "In iCloud"
        case .pieDownload, .pieSync: return "Downloading, click to cancel"
        case .exclamation: return DownloadState.failedAccessibilityLabel
        case .locked: return "Needs access to this folder"
        case .elsewhere: return "Not available on this Mac. Added from another device."
        }
    }

    /// Said after the name so colour and a small icon never carry the state alone.
    private var cloudSpoken: String {
        guard let cloud else { return "" }
        switch cloud.icon {
        case .crossedOut: return ", not in iCloud"
        case .outline: return cloud.dimmed ? ", not on this Mac" : ", in iCloud"
        case .pieDownload, .pieSync: return ", downloading from iCloud"
        case .exclamation: return ", " + DownloadState.failedAccessibilityLabel
        case .locked: return ", needs access to this folder"
        case .elsewhere: return ", on another device"
        }
    }

    /// A cloud with a question mark: the system has no such symbol, so the cloud is drawn with the mark in it.
    private static func questionCloud(description: String) -> NSImage? {
        guard let cloud = NSImage(systemSymbolName: "icloud", accessibilityDescription: description) else { return nil }
        let image = NSImage(size: cloud.size, flipped: false) { rect in
            cloud.draw(in: rect)
            let mark = NSAttributedString(string: "?", attributes: [.font: NSFont.systemFont(ofSize: rect.height * 0.5, weight: .bold)])
            let size = mark.size()
            mark.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2 - rect.height * 0.04))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description
        return image
    }

    var cloudKind: CloudIconState? { cloudButton.isHidden ? nil : cloud?.icon }
    var cloudOpacity: CGFloat { cloudButton.alphaValue }
    var pieFraction: Double? { pie.isHidden ? nil : pie.fraction }

    var showsHazard: Bool { hazard && !glyphView.isHidden }
    var glyphDescription: String? { glyphView.isHidden ? nil : glyphView.accessibilityLabel() }
    var isGreyedOut: Bool { nameField.textColor == .disabledControlTextColor }
    var title: String { nameField.stringValue }
}

/// The pie of a download in progress is the system's determinate circular progress indicator; with no fraction
/// known it spins, as the phone does. Clicks pass through to the button underneath.
@MainActor
final class PieIndicator: NSProgressIndicator {
    private static let unknown: Double = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        style = .spinning
        controlSize = .small
        minValue = 0
        maxValue = 1
        isDisplayedWhenStopped = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    /// The done part, nil while the system has not said how far the download is.
    var fraction: Double? {
        get { isIndeterminate ? nil : doubleValue }
        set {
            if let newValue, newValue > Self.unknown {
                stopAnimation(nil)
                isIndeterminate = false
                doubleValue = min(newValue, maxValue)
            } else {
                isIndeterminate = true
                if !isHidden { startAnimation(nil) }
            }
        }
    }

    override var isHidden: Bool {
        didSet {
            guard isIndeterminate else { return }
            if isHidden { stopAnimation(nil) } else { startAnimation(nil) }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
