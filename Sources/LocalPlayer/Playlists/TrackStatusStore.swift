import Foundation
import Combine

protocol TrackStatusProviding: AnyObject {
    func status(of id: UUID) -> TrackStatus?
}

/// What an open playlist document must offer so references can be refreshed or relinked. `PlaylistDocument`
/// is the only conforming document type.
protocol PlaylistDocumentEditing: AnyObject {
    var playlist: Playlist { get }
    func apply(_ updatedReference: TrackReference, toTrack id: UUID)
}

/// Told whenever a track is resolved, so the document can show it normal or greyed and take a refreshed
/// reference through its normal editing path.
protocol TrackResolutionReporting: AnyObject {
    func trackResolved(id: UUID, status: TrackStatus, reference: TrackReference)
}

/// In-memory resolved-or-missing status per track of one open playlist. Never written to disk.
final class TrackStatusStore: TrackStatusProviding {
    private var statuses: [UUID: TrackStatus] = [:]
    private let subject = PassthroughSubject<Void, Never>()

    var changes: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }

    func status(of id: UUID) -> TrackStatus? { statuses[id] }

    func set(_ status: TrackStatus, for id: UUID) {
        guard statuses[id] != status else { return }
        statuses[id] = status
        subject.send()
    }

    func setAll(_ updates: [UUID: TrackStatus]) {
        var changed = false
        for (id, status) in updates where statuses[id] != status {
            statuses[id] = status
            changed = true
        }
        if changed { subject.send() }
    }

    func isMissing(_ id: UUID) -> Bool { statuses[id] == .missing }
}
