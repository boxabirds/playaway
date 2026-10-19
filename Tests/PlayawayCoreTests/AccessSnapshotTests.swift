import XCTest
@testable import PlayawayCore

/// The access snapshot moved out of the iPhone model into the core so that it can run off the main thread while a playlist
/// opens. These pin every way a song counts (audit F5 and the open-feedback work).
final class AccessSnapshotTests: XCTestCase {
    private struct Resolver: TrackResolving {
        var needsAccess: Set<String> = []          // file names whose folder this device may not read
        var found: Set<String> = []                // file names found by their own means
        func resolve(_ ref: TrackReference) -> (TrackStatus, TrackReference) { resolve(ref, besidePlaylistAt: nil) }
        func resolve(_ ref: TrackReference, besidePlaylistAt folder: URL?) -> (TrackStatus, TrackReference) {
            (found.contains(ref.fileName) ? .resolved(URL(fileURLWithPath: "/x/\(ref.fileName)")) : .missing, ref)
        }
        func accessNeeded(for ref: TrackReference, besidePlaylistAt folder: URL?) -> String? {
            needsAccess.contains(ref.fileName) ? "Mixdowns" : nil
        }
    }

    private func track(_ name: String, in folder: String = "Mixdowns") -> Track {
        var reference = TrackReference(bookmark: Data(), lastKnownPath: "/x/\(name)", fileName: name)
        reference.cloudPath = .iCloudDrive("\(folder)/\(name)")
        return Track(id: UUID(), reference: reference)
    }

    func testAPlaylistWithNoSongsInTheDriveNeedsNothing() {
        var reference = TrackReference(bookmark: Data(), lastKnownPath: "/Users/me/a.mp3", fileName: "a.mp3")
        reference.cloudPath = nil
        let snapshot = AccessSnapshot.make(tracks: [Track(id: UUID(), reference: reference)], folder: nil, resolver: Resolver(), reaches: { _ in false })
        XCTAssertEqual(snapshot, .empty)
    }

    func testSongsThatNeedAccessAreLockedAndPlanned() {
        let a = track("a.mp3"), b = track("b.mp3")
        let snapshot = AccessSnapshot.make(tracks: [a, b], folder: nil, resolver: Resolver(needsAccess: ["a.mp3", "b.mp3"]), reaches: { _ in false })
        XCTAssertEqual(snapshot.locked, [a.id, b.id])
        XCTAssertEqual(snapshot.plan?.trackCount, 2)
        XCTAssertEqual(snapshot.unfound.map(\.fileName).sorted(), ["a.mp3", "b.mp3"])
    }

    func testAFolderWhereSomeSongIsFoundIsNotAskedFor() {
        let a = track("a.mp3"), b = track("b.mp3")
        let snapshot = AccessSnapshot.make(tracks: [a, b], folder: nil, resolver: Resolver(needsAccess: ["a.mp3"], found: ["b.mp3"]), reaches: { _ in false })
        XCTAssertTrue(snapshot.locked.isEmpty, "b is found in the same folder, so the folder is readable and a is simply missing")
        XCTAssertNil(snapshot.plan)
    }

    func testProgressCountsEverySongOnceInOrder() {
        var seen: [Int] = []
        _ = AccessSnapshot.make(tracks: (0..<5).map { track("t\($0).mp3") }, folder: nil, resolver: Resolver(), reaches: { _ in false }) { seen.append($0) }
        XCTAssertEqual(seen, [1, 2, 3, 4, 5])
    }

    func testResolutionReportsProgressPerTrack() {
        var seen: [Int] = []
        let results = PlaylistResolution.resolve((0..<4).map { track("t\($0).mp3") }, with: Resolver(found: ["t1.mp3"]), besidePlaylistAt: nil) { seen.append($0) }
        XCTAssertEqual(seen, [1, 2, 3, 4])
        XCTAssertEqual(results.count, 4)
        XCTAssertEqual(results.filter { if case .resolved = $0.status { return true } else { return false } }.count, 1)
    }

    // MARK: What the row shows

    func testProgressStaysHiddenUntilTheDelayHasPassed() {
        XCTAssertFalse(OpeningProgress.isOverdue(elapsed: 0))
        XCTAssertFalse(OpeningProgress.isOverdue(elapsed: 0.299))
        XCTAssertTrue(OpeningProgress.isOverdue(elapsed: 0.3))
        XCTAssertTrue(OpeningProgress.isOverdue(elapsed: 5))
    }

    func testProgressFractionAndLabel() {
        XCTAssertEqual(OpeningProgress(done: 12, total: 45).label, "Loading 12 of 45")
        XCTAssertEqual(OpeningProgress(done: 12, total: 48).fraction, 0.25, accuracy: 1e-9)
        XCTAssertEqual(OpeningProgress(done: 0, total: 0).fraction, 1, "an empty playlist is complete")
        XCTAssertEqual(OpeningProgress(done: 60, total: 45).fraction, 1, "never past full")
        XCTAssertEqual(OpeningProgress(done: 60, total: 45).label, "Loading 45 of 45")
    }
}
