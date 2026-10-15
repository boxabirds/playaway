import SwiftUI
import UIKit
import PlayawayCore

/// The song list as a system table view: swipe-left trash, press-and-hold drag to reorder (with the system's gap and
/// automatic scrolling), no Edit mode.
struct SongTable: UIViewRepresentable {
    @ObservedObject var session: PlaylistSession
    @EnvironmentObject var model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    func makeUIView(context: Context) -> UITableView {
        let table = UITableView(frame: .zero, style: .plain)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.dragDelegate = context.coordinator
        table.dragInteractionEnabled = true
        table.register(UITableViewCell.self, forCellReuseIdentifier: Coordinator.cellID)
        table.accessibilityIdentifier = "song-table"
        return table
    }

    func updateUIView(_ table: UITableView, context: Context) {
        let c = context.coordinator
        c.session = session
        c.model = model
        c.currentID = session.player.current?.id
        // Room for the floating controller, so the last song can be scrolled up clear of it.
        let bottom = model.playerBarVisible ? PlayerBar.inset : 0
        table.contentInset.bottom = bottom
        table.verticalScrollIndicatorInsets.bottom = bottom
        guard !c.isDragging else { return }
        table.reloadData()
    }

    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate, UITableViewDragDelegate {
        static let cellID = "song"
        var session: PlaylistSession
        var currentID: UUID?
        var isDragging = false
        weak var model: AppModel?
        init(session: PlaylistSession) { self.session = session }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { session.playlist.tracks.count }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellID, for: indexPath)
            let track = session.playlist.tracks[indexPath.row]
            let playing = track.id == currentID
            let display = model?.cloudDisplay(for: track)
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

        func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
            let id = self.session.playlist.tracks[indexPath.row].id.uuidString
            return [UIDragItem(itemProvider: NSItemProvider(object: id as NSString))]
        }

        func tableView(_ tableView: UITableView, dragSessionWillBegin session: UIDragSession) { isDragging = true }
        func tableView(_ tableView: UITableView, dragSessionDidEnd session: UIDragSession) { isDragging = false }
    }
}


/// The cloud icon at the end of a song row. It is drawn small but its tappable area is at least 44 by 44 points.
struct CloudIconButton: View {
    let display: SongRowCloudDisplay
    let tapped: () -> Void

    var body: some View {
        Button(action: tapped) {
            icon
                .frame(width: cloudIconDrawnSize.width, height: cloudIconDrawnSize.height)
                .frame(minWidth: minimumCloudIconTapSize.width, minHeight: minimumCloudIconTapSize.height)
                .contentShape(Rectangle())
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
