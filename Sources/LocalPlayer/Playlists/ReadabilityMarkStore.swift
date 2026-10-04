import Foundation
import Combine

/// The hazard icon. Means "could not be played this session" for unreadable and missing tracks alike.
/// Session-only and never written to the playlist file.
enum ReadabilityMark: Equatable {
    case readable, unreadable
}

protocol ReadabilityMarkStoring: AnyObject {
    func mark(of track: Track) -> ReadabilityMark
    func markUnreadable(_ track: Track)
    func clearMark(of track: Track)
}

final class ReadabilityMarkStore: ReadabilityMarkStoring {
    private var unreadable = Set<UUID>()
    private let subject = PassthroughSubject<Void, Never>()

    var changes: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }

    func mark(of track: Track) -> ReadabilityMark {
        unreadable.contains(track.id) ? .unreadable : .readable
    }

    func markUnreadable(_ track: Track) {
        guard unreadable.insert(track.id).inserted else { return }
        subject.send()
    }

    func clearMark(of track: Track) {
        guard unreadable.remove(track.id) != nil else { return }
        subject.send()
    }
}
