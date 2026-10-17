import PlayawayCore
import AppKit
import Combine
import UniformTypeIdentifiers

/// The window of one playlist, with three areas top to bottom and nothing else: what is playing with its controls
/// (including shuffle and repeat), the tracks, and a slim footer with add, the track count and remove. Standard
/// AppKit controls only.
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
    /// Test seam: the Playlist dialog is a sheet, so tests answer it here instead.
    var askPlaylistChoice: (() async -> PlaylistChoice)?
    /// The symbol the switch shows (symbol images carry no name of their own).
    private(set) var syncSymbolName = ""
    let transport: TransportControlsView
    let modes: PlayModeControls

    /// Test seams: the panels are modal, so tests replace them with stubs that return a chosen URL.
    var chooseFilesToAdd: () -> [URL]? = PlaylistWindowController.runAddPanel
    var chooseFileToLocate: () -> URL? = PlaylistWindowController.runLocatePanel

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
        services.cloud.changes.receive(on: DispatchQueue.main).sink { [weak self] in self?.refreshSync() }.store(in: &cancellables)
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
        Task { @MainActor [weak self] in
            guard let self else { return }
            await playlistDocument.sync.turnOn(presenter: presenter)
            refreshSync()
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
                       hazard: services.marks.mark(of: track) == .unreadable, marker: marker(for: track))
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
        playlistDocument.addFiles(urls)
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
        playlistDocument.addFiles(urls)
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

/// A row: a leading glyph slot and the name. The slot shows the hazard icon for a track that could not be played,
/// or the playing or paused marker for the current track. The name is greyed when the file is missing, and
/// accent-coloured and semibold while it is the current track.
final class TrackCellView: NSTableCellView {
    enum Marker { case none, playing, paused }

    private static let glyphSize: CGFloat = 16
    private static let spacing: CGFloat = 6
    private static let nameSize: CGFloat = 14
    private let glyphView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    private var name = ""
    private var missing = false
    private var hazard = false
    private(set) var titleWeight: NSFont.Weight = .regular

    var marker: Marker = .none {
        didSet { if marker != oldValue { refresh() } }
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
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.spacing),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Self.spacing),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            glyphView.widthAnchor.constraint(equalToConstant: Self.glyphSize),
        ])
        textField = nameField
        imageView = glyphView
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    func configure(name: String, missing: Bool, hazard: Bool, marker: Marker = .none) {
        self.name = name
        self.missing = missing
        self.hazard = hazard
        self.marker = marker
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
            nameField.textColor = missing ? .disabledControlTextColor : (shownMarker == .none ? .labelColor : .controlAccentColor)
        }
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
        setAccessibilityLabel(name + state)
    }

    var showsHazard: Bool { hazard && !glyphView.isHidden }
    var glyphDescription: String? { glyphView.isHidden ? nil : glyphView.accessibilityLabel() }
    var isGreyedOut: Bool { nameField.textColor == .disabledControlTextColor }
    var title: String { nameField.stringValue }
}
