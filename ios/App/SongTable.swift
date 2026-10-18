import SwiftUI
import UIKit
import PlayawayCore

/// The song list as a system table view: swipe-left trash, press-and-hold drag to reorder (with the system's gap and
/// automatic scrolling), no Edit mode.
struct SongTable: UIViewRepresentable {
    @ObservedObject var session: PlaylistSession
    @EnvironmentObject var model: AppModel

    func makeCoordinator() -> Coordinator { let coordinator = Coordinator(session: session); coordinator.model = model; return coordinator }

    func makeUIView(context: Context) -> UITableView {
        let table = UITableView(frame: .zero, style: .plain)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.dragDelegate = context.coordinator
        table.dragInteractionEnabled = true
        table.register(UITableViewCell.self, forCellReuseIdentifier: Coordinator.cellID)
        table.separatorStyle = .none
        table.accessibilityIdentifier = "song-table"
        return table
    }

    func updateUIView(_ table: UITableView, context: Context) {
        let c = context.coordinator
        c.session = session
        c.model = model
        c.currentID = session.player.current?.id
        // Room for the floating controller, so the last song can be scrolled up clear of it.
        let bottom = model.playerBarInset
        table.contentInset.bottom = bottom
        table.verticalScrollIndicatorInsets.bottom = bottom
        // Rebuild only what changed. The song list used to be rebuilt on every model update, including the playback
        // position ticking four times a second, which made scrolling jerky and could swap the item being dragged.
        let signature = Coordinator.Signature(ids: session.playlist.tracks.map(\.id), current: c.currentID, cloud: model.cloudRevision)
        guard !c.isDragging else { c.needsReloadAfterDrag = true; return }
        defer { c.lastSignature = signature }
        guard let last = c.lastSignature else { table.reloadData(); c.noteReload(table); return }
        if last == signature { return }
        if last.ids == signature.ids {
            table.reconfigureRows(at: table.indexPathsForVisibleRows ?? [])    // only what each row shows changed
        } else {
            table.reloadData()
        }
        c.noteReload(table)
    }

    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate, UITableViewDragDelegate {
        static let cellID = "song"
        var session: PlaylistSession
        var currentID: UUID?
        var isDragging = false
        var needsReloadAfterDrag = false
        var lastSignature: Signature?
        private(set) var reloads = 0

        struct Signature: Equatable { let ids: [UUID]; let current: UUID?; let cloud: Int }

        /// Counts rebuilds, and shows the count to UI tests, which check that nothing rebuilds the list needlessly.
        func noteReload(_ table: UITableView) {
            reloads += 1
            #if DEBUG
            table.accessibilityValue = "reloads=\(reloads)"
            #endif
        }
        weak var model: AppModel?
        init(session: PlaylistSession) { self.session = session }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { session.playlist.tracks.count }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellID, for: indexPath)
            let track = session.playlist.tracks[indexPath.row]
            let playing = track.id == currentID
            let display = model?.cloudDisplay(for: track, in: session)
            let name = track.reference.fileName.fileNameWithoutExtension
            cell.contentConfiguration = UIHostingConfiguration {
                HStack {
                    Text(name).foregroundStyle(.primary).opacity(display?.dimmed == true ? 0.45 : 1)
                    Spacer()
                    if playing { Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint) }
                    if let display {
                        CloudIconButton(display: display) { [weak self] in
                            guard let self, let model = self.model else { return }
                            model.cloudIconTapped(track, session: self.session)
                        }
                    }
                }
            }
            cell.accessibilityTraits = .button
            cell.accessibilityLabel = track.reference.fileName.fileNameWithoutExtension
            let count = session.playlist.tracks.count
            cell.accessibilityCustomActions = songRowActions(index: indexPath.row, count: count).map { action in
                let name: String
                switch action {
                case .moveUp: name = "Move Up"
                case .moveDown: name = "Move Down"
                case .remove: name = "Remove from Playlist"
                }
                return UIAccessibilityCustomAction(name: name) { [weak self] _ in
                    Task { @MainActor in self?.perform(action, at: indexPath.row) }
                    return true
                }
            }
            return cell
        }

        /// The VoiceOver alternative to swiping and dragging, announcing where the song ended up.
        @MainActor private func perform(_ action: SongRowAction, at row: Int) {
            let count = session.playlist.tracks.count
            switch action {
            case .moveUp:
                session.move(from: row, to: row - 1)
                UIAccessibility.post(notification: .announcement, argument: "Moved to position \(row) of \(count)")
            case .moveDown:
                session.move(from: row, to: row + 1)
                UIAccessibility.post(notification: .announcement, argument: "Moved to position \(row + 2) of \(count)")
            case .remove:
                session.remove(at: IndexSet(integer: row))
                UIAccessibility.post(notification: .announcement, argument: "Removed from playlist")
            }
        }

        func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            tableView.deselectRow(at: indexPath, animated: true)
            Task { @MainActor in self.session.play(self.session.playlist.tracks[indexPath.row]) }
        }

        func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { true }

        func tableView(_ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
            Task { @MainActor in self.session.move(from: source.row, to: destination.row) }
        }

        func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            let remove = UIContextualAction(style: .destructive, title: nil) { [weak self] _, _, done in
                Task { @MainActor in self?.session.remove(at: IndexSet(integer: indexPath.row)) }
                done(true)
            }
            remove.image = UIImage(systemName: "trash")
            remove.accessibilityLabel = "Remove from Playlist"
            return UISwipeActionsConfiguration(actions: [remove])
        }

        /// A row's drag carries the track id (for reordering within this list) and, when the file is found, its URL, so
        /// a playlist in the iPad's sidebar can take the song (story 38).
        func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
            let track = self.session.playlist.tracks[indexPath.row]
            let provider = NSItemProvider(object: track.id.uuidString as NSString)
            if let model, case .resolved(let url) = model.resolver.resolve(track.reference, besidePlaylistAt: self.session.folder).0 {
                provider.registerObject(url as NSURL, visibility: .all)
            }
            return [UIDragItem(itemProvider: provider)]
        }

        func tableView(_ tableView: UITableView, dragSessionWillBegin session: UIDragSession) { isDragging = true }
        func tableView(_ tableView: UITableView, dragSessionDidEnd session: UIDragSession) {
            isDragging = false
            guard needsReloadAfterDrag else { return }
            needsReloadAfterDrag = false
            lastSignature = nil
            DispatchQueue.main.async { tableView.reloadData(); self.noteReload(tableView) }
        }
    }
}


/// The cloud icon at the end of a song row. It is drawn small but its tappable area is at least 44 by 44 points.
struct CloudIconButton: View {
    let display: SongRowCloudDisplay
    let tapped: () -> Void

    var body: some View {
        Button(action: tapped) {
            // Drawn small, tappable at 44 by 44: the extra area is hit-test only, so it does not make the row taller.
            icon
                .frame(width: cloudIconDrawnSize.width, height: cloudIconDrawnSize.height)
                .padding(.horizontal, (minimumCloudIconTapSize.width - cloudIconDrawnSize.width) / 2)
                .padding(.vertical, (minimumCloudIconTapSize.height - cloudIconDrawnSize.height) / 2)
                .contentShape(Rectangle())
                .padding(.horizontal, -(minimumCloudIconTapSize.width - cloudIconDrawnSize.width) / 2)
                .padding(.vertical, -(minimumCloudIconTapSize.height - cloudIconDrawnSize.height) / 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("cloud-icon")
        .accessibilityValue(valueText)
    }

    @ViewBuilder private var icon: some View {
        switch display.icon {
        case .crossedOut: Image(systemName: "icloud.slash").foregroundStyle(.secondary)
        case .outline: Image(systemName: "icloud").foregroundStyle(.secondary)
        case .exclamation: Image(systemName: "exclamationmark.icloud").foregroundStyle(.red)
        case .pieDownload, .pieSync:
            if let fraction = display.fraction, fraction > 0 {
                ZStack {
                    Circle().stroke(.secondary.opacity(0.3), lineWidth: 3)
                    Circle().trim(from: 0, to: fraction).stroke(.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            } else {
                ProgressView().scaleEffect(0.7)    // the system's percentage is not known, so no pie fill
            }
        }
    }

    private var label: String {
        switch display.icon {
        case .crossedOut: return "Not in iCloud"
        case .outline: return display.dimmed ? "In iCloud, not on this iPhone" : "In iCloud"
        case .pieDownload, .pieSync: return "Downloading, tap to cancel"
        case .exclamation: return DownloadState.failedAccessibilityLabel
        }
    }

    private var valueText: String {
        guard let fraction = display.fraction, fraction > 0 else { return "" }
        return "\(Int(fraction * 100)) percent"
    }
}


