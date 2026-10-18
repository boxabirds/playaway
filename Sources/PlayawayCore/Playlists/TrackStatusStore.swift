import Foundation
import Combine

package protocol TrackStatusProviding: AnyObject {
    func status(of id: UUID) -> TrackStatus?
}

/// What an open playlist document must offer so references can be refreshed or relinked. `PlaylistDocument`
/// is the only conforming document type.
@MainActor
package protocol PlaylistDocumentEditing: AnyObject {
    var playlist: Playlist { get }
    func apply(_ updatedReference: TrackReference, toTrack id: UUID)
}

/// Told whenever a track is resolved, so the document can show it normal or greyed and take a refreshed
/// reference through its normal editing path.
@MainActor
package protocol TrackResolutionReporting: AnyObject {
    func trackResolved(id: UUID, status: TrackStatus, reference: TrackReference)
}

/// In-memory resolved-or-missing status per track of one open playlist. Never written to disk.
package final class TrackStatusStore: TrackStatusProviding {
    package init() {}
    private var statuses: [UUID: TrackStatus] = [:]
    private let subject = PassthroughSubject<Void, Never>()

    package var changes: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }

    package func status(of id: UUID) -> TrackStatus? { statuses[id] }

    package func set(_ status: TrackStatus, for id: UUID) {
        guard statuses[id] != status else { return }
        statuses[id] = status
        subject.send()
    }

    package func setAll(_ updates: [UUID: TrackStatus]) {
        var changed = false
        for (id, status) in updates where statuses[id] != status {
            statuses[id] = status
            changed = true
        }
        if changed { subject.send() }
    }

    package func isMissing(_ id: UUID) -> Bool { statuses[id] == .missing }
}
