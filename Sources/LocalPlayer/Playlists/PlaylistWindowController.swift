import AppKit
import Combine
import UniformTypeIdentifiers

/// The window of one playlist, with three groups top to bottom and nothing else: what is playing and its controls,
/// shuffle and repeat, and the tracks with add and remove. Standard AppKit controls only.
final class PlaylistWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    private static let rowDragType = NSPasteboard.PasteboardType("com.localplayer.playlist.row")
    private static let initialSize = NSSize(width: 520, height: 640)
    private static let minimumSize = NSSize(width: 420, height: 460)
    private static let contentInset: CGFloat = 20
    private static let groupSpacing: CGFloat = 18
    private static let rowSpacing: CGFloat = 8
    private static let tableMinimumHeight: CGFloat = 160
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
    let emptyHint = NSTextField(wrappingLabelWithString: PlaylistWindowController.emptyHintText)
    let transport: TransportControlsView
    let modes: PlayModeControls

    /// Test seams: the panels are modal, so tests replace them with stubs that return a chosen URL.
    var chooseFilesToAdd: () -> [URL]? = PlaylistWindowController.runAddPanel
    var chooseFileToLocate: () -> URL? = PlaylistWindowController.runLocatePanel

    init(document: PlaylistDocument) {
        playlistDocument = document
        services = document.services
        transport = TransportControlsView(viewModel: document.services.transport)
        modes = PlayModeControls(settings: document.services.settings)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.initialSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: true)
        window.minSize = Self.minimumSize
        window.isReleasedWhenClosed = false
        if !Self.animatesWindows { window.animationBehavior = .none }
        super.init(window: window)
        shouldCascadeWindows = true
        buildContent(in: window)
        bind()
        reload()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Layout

    private func buildContent(in window: NSWindow) {
        configureTable()
        configureTrackButtons()

        let trackButtons = NSStackView(views: [addButton, removeButton])
        trackButtons.spacing = Self.rowSpacing
        let tracksGroup = NSStackView(views: [scrollView, emptyHint, trackButtons])
        tracksGroup.orientation = .vertical
        tracksGroup.alignment = .leading
        tracksGroup.spacing = Self.rowSpacing

        let root = NSStackView(views: [transport, modes, tracksGroup])
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

    private func configureTable() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(ElementID.tracks))   // part of the tracks element
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .inset
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = NSFont.systemFontSize * 2
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
        scrollView.borderType = .bezelBorder
        scrollView.setAccessibilityIdentifier(ElementID.tracks)
        scrollView.setAccessibilityElement(true)
        scrollView.setAccessibilityLabel("Tracks")
        emptyHint.setAccessibilityIdentifier(ElementID.emptyHint)
        emptyHint.textColor = .secondaryLabelColor
    }

    private func configureTrackButtons() {
        addButton.title = "Add Files"
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Files")
        addButton.imagePosition = .imageLeading
        addButton.bezelStyle = .texturedRounded
        addButton.target = self
        addButton.action = #selector(addFiles(_:))
        addButton.setAccessibilityIdentifier(ElementID.add)
        addButton.setAccessibilityLabel("Add Files")
        removeButton.title = "Remove"
        removeButton.image = NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove")
        removeButton.imagePosition = .imageLeading
        removeButton.bezelStyle = .texturedRounded
        removeButton.target = self
        removeButton.action = #selector(removeSelectedTracks(_:))
        removeButton.setAccessibilityIdentifier(ElementID.remove)
        removeButton.setAccessibilityLabel("Remove")
    }

    // MARK: Binding

    private func bind() {
        playlistDocument.changes.sink { [weak self] in self?.reload() }.store(in: &cancellables)
        playlistDocument.statuses.changes.sink { [weak self] in self?.reload() }.store(in: &cancellables)
        if let marks = services.marks as? ReadabilityMarkStore {
            marks.changes.sink { [weak self] in self?.reload() }.store(in: &cancellables)
        }
    }

    func reload() {
        let selected = tableView.selectedRowIndexes
        tableView.reloadData()
        let valid = selected.filteredIndexSet { $0 < tableView.numberOfRows }
        tableView.selectRowIndexes(valid, byExtendingSelection: false)
        emptyHint.isHidden = !playlistDocument.playlist.tracks.isEmpty
        removeButton.isEnabled = !tableView.selectedRowIndexes.isEmpty
    }

    // MARK: Table data

    func numberOfRows(in tableView: NSTableView) -> Int { playlistDocument.playlist.tracks.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard playlistDocument.playlist.tracks.indices.contains(row) else { return nil }
        let track = playlistDocument.playlist.tracks[row]
        let cell = (tableView.makeView(withIdentifier: Self.cellIdentifier, owner: self) as? TrackCellView) ?? TrackCellView()
        cell.identifier = Self.cellIdentifier
        let missing = playlistDocument.statuses.isMissing(track.id)
        cell.configure(name: track.reference.fileName, missing: missing,
                       hazard: services.marks.mark(of: track) == .unreadable)
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

/// A row: an optional hazard icon and the file name, greyed when the file is missing.
final class TrackCellView: NSTableCellView {
    private static let hazardSize: CGFloat = 16
    private static let spacing: CGFloat = 6
    private let hazardView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hazardView.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Could not be played")
        hazardView.contentTintColor = .systemYellow
        hazardView.setAccessibilityLabel("Could not be played")
        nameField.lineBreakMode = .byTruncatingMiddle
        let stack = NSStackView(views: [hazardView, nameField])
        stack.spacing = Self.spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.spacing),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Self.spacing),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            hazardView.widthAnchor.constraint(equalToConstant: Self.hazardSize),
        ])
        textField = nameField
        imageView = hazardView
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    func configure(name: String, missing: Bool, hazard: Bool) {
        nameField.stringValue = name
        nameField.textColor = missing ? .disabledControlTextColor : .labelColor
        hazardView.isHidden = !hazard
        // Colour alone must not carry the state: say it.
        let state = hazard ? ", could not be played" : (missing ? ", file not found" : "")
        setAccessibilityLabel(name + state)
    }

    var showsHazard: Bool { !hazardView.isHidden }
    var isGreyedOut: Bool { nameField.textColor == .disabledControlTextColor }
    var title: String { nameField.stringValue }
}
