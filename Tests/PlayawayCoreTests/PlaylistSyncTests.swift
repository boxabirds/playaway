import XCTest
@testable import PlayawayCore

/// Story 18: the playlist-level iCloud sync core shared by the Mac and the iPhone. "In iCloud" means the playlist
/// file is strictly inside the Playaway folder (owner decision 2026-10-13). Turning sync on for a playlist outside it
/// asks once, then moves the file to Playaway/<name>/<name>.lplaylist, the phone's layout; there is no way back.
@MainActor
final class PlaylistSyncTests: XCTestCase {
    private final class RecordingPresenter: PlaylistPromptPresenting {
        var answer: PlaylistChoice
        private(set) var asked = 0
        init(_ answer: PlaylistChoice) { self.answer = answer }
        func askPlaylistChoice() async -> PlaylistChoice { asked += 1; return answer }
    }

    private struct PlainMover: PlaylistMoving {
        func movePlaylist(from source: URL, to destination: URL) async throws {
            try FileManager.default.moveItem(at: source, to: destination)
        }
    }

    private struct RefusingMover: PlaylistMoving {
        struct Refused: Error {}
        func movePlaylist(from source: URL, to destination: URL) async throws { throw Refused() }
    }

    private func savedPlaylist(at url: URL, tracks: Int = 0) -> URL {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let list = Playlist(tracks: (0..<tracks).map { _ in Track(id: UUID(), reference: TrackReference(bookmark: Data(), lastKnownPath: "/x", fileName: "x.mp3")) })
        XCTAssertEqual(PlaylistStore().save(list, to: url), .saved)
        return url
    }

    private func core(root: URL?, answer: PlaylistChoice, mover: PlaylistMoving? = nil) -> (PlaylistSyncCore, RecordingPresenter) {
        let presenter = RecordingPresenter(answer)
        let availability: ICloudAvailability = root.map { .available(root: $0) } ?? .unavailable
        return (PlaylistSyncCore(availability: availability, mover: mover ?? PlainMover(), presenter: presenter), presenter)
    }

    // MARK: State is where the file is

    func testSyncStateIsWhereThePlaylistFileIs() {
        let root = TempDir("root")
        let inside = root.url.appendingPathComponent("Dinner").appendingPathComponent("Dinner.\(playlistFileExtension)")
        let outside = TempDir("docs").path("Dinner.\(playlistFileExtension)")
        XCTAssertEqual(playlistSyncState(of: inside, root: root.url), .on)
        XCTAssertEqual(playlistSyncState(of: outside, root: root.url), .off)
        XCTAssertEqual(playlistSyncState(of: inside, root: nil), .off, "no Playaway folder on this device: nothing is synced")
        XCTAssertEqual(playlistSyncState(of: nil, root: root.url), .off, "a playlist with no file yet is not synced")
        XCTAssertEqual(playlistSyncState(of: root.url, root: root.url), .off, "the folder itself is not inside itself")
    }

    // MARK: The switch's look

    func testTheSwitchDiffersByShapeAndSaysOnOrOff() {                                           // TC-18, TC-25
        let root = TempDir("root")
        let off = ICloudButtonPresentation(state: .off, availability: .available(root: root.url))
        let on = ICloudButtonPresentation(state: .on, availability: .available(root: root.url))
        XCTAssertEqual(off.symbolName, "icloud.slash")
        XCTAssertEqual(on.symbolName, "icloud.fill")
        XCTAssertNotEqual(off.symbolName, on.symbolName, "shape, not only colour")
        XCTAssertEqual(off.accessibilityLabel, "iCloud sync for this playlist")
        XCTAssertEqual(on.accessibilityLabel, off.accessibilityLabel)
        XCTAssertEqual(off.accessibilityValue, "off")
        XCTAssertEqual(on.accessibilityValue, "on")
        XCTAssertTrue(off.isEnabled && on.isEnabled)
        XCTAssertNil(off.reason)
    }

    func testWhileICloudIsUnavailableTheSwitchIsDisabledKeepsItsShapeAndCarriesTheReason() {     // TC-34, TC-35, TC-39
        let off = ICloudButtonPresentation(state: .off, availability: .unavailable)
        let on = ICloudButtonPresentation(state: .on, availability: .unavailable)
        XCTAssertFalse(off.isEnabled); XCTAssertFalse(on.isEnabled)
        XCTAssertEqual(off.symbolName, "icloud.slash"); XCTAssertEqual(on.symbolName, "icloud.fill")
        XCTAssertEqual(off.reason, ICloudAvailability.unavailableReason)
        XCTAssertFalse(ICloudAvailability.unavailableReason.contains("\n"), "one line")
        XCTAssertTrue(off.accessibilityValue.contains(ICloudAvailability.unavailableReason), "VoiceOver reads the reason")
        XCTAssertTrue(off.accessibilityValue.hasPrefix("off"))
        XCTAssertEqual(off.accessibilityLabel, "iCloud sync for this playlist")
    }

    func testTheReasonTextIsWrittenOnce() throws {                                                  // TC-36
        let sources = Fixtures.directory.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources")
        var hits: [String] = []
        for case let file as URL in FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)! where file.pathExtension == "swift" {
            if (try String(contentsOf: file, encoding: .utf8)).contains("\"\(ICloudAvailability.unavailableReason)\"") { hits.append(file.lastPathComponent) }
        }
        XCTAssertEqual(hits, ["PlaylistSync.swift"], "the reason is one constant: \(hits)")
    }

    // MARK: Turning on

    func testAPlaylistAlreadyInThePlayawayFolderTurnsOnWithoutAsking() async {                     // TC-05
        let root = TempDir("root")
        let file = savedPlaylist(at: root.url.appendingPathComponent("Dinner/Dinner.\(playlistFileExtension)"))
        let (core, presenter) = core(root: root.url, answer: .dontSync)
        let outcome = await core.turnOn(playlistAt: file)
        XCTAssertEqual(outcome, .on(file))
        XCTAssertEqual(presenter.asked, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testAPlaylistOutsideIsAskedAboutAndMoveMovesItIntoItsOwnFolder() async throws {           // TC-01, TC-02
        let root = TempDir("root"), docs = TempDir("docs")
        let file = savedPlaylist(at: docs.path("Dinner.\(playlistFileExtension)"), tracks: 2)
        let before = try Data(contentsOf: file)
        let (core, presenter) = core(root: root.url, answer: .move)
        let outcome = await core.turnOn(playlistAt: file)
        let expected = root.url.appendingPathComponent("Dinner").appendingPathComponent("Dinner.\(playlistFileExtension)")
        XCTAssertEqual(outcome, .on(expected))
        XCTAssertEqual(presenter.asked, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "moved, not copied")
        XCTAssertEqual(try Data(contentsOf: expected), before, "the same bytes arrive")
        XCTAssertEqual(playlistSyncState(of: expected, root: root.url), .on)
    }

    func testDontSyncLeavesTheFileAndTheFolderAsTheyWere() async throws {                           // TC-03, TC-04, TC-20
        let root = TempDir("root"), docs = TempDir("docs")
        let file = savedPlaylist(at: docs.path("Dinner.\(playlistFileExtension)"))
        let (core, presenter) = core(root: root.url, answer: .dontSync)
        let outcome = await core.turnOn(playlistAt: file)
        XCTAssertEqual(outcome, .left)
        XCTAssertEqual(presenter.asked, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.url.path), [], "nothing created in iCloud")
    }

    func testWhileICloudIsUnavailableNothingIsAskedAndNothingMoves() async throws {                 // TC-13, TC-30, TC-38
        let docs = TempDir("docs")
        let file = savedPlaylist(at: docs.path("Dinner.\(playlistFileExtension)"))
        let (core, presenter) = core(root: nil, answer: .move)
        let outcome = await core.turnOn(playlistAt: file)
        XCTAssertEqual(outcome, .unavailable)
        XCTAssertEqual(presenter.asked, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testAFailedMoveLeavesTheFileWhereItWasAndNoEmptyFolderBehind() async throws {              // TC-10, TC-21
        let root = TempDir("root"), docs = TempDir("docs")
        let file = savedPlaylist(at: docs.path("Dinner.\(playlistFileExtension)"), tracks: 1)
        let before = try Data(contentsOf: file)
        let (core, _) = core(root: root.url, answer: .move, mover: RefusingMover())
        guard case .failed(let why) = await core.turnOn(playlistAt: file) else { return XCTFail("expected a failure") }
        XCTAssertFalse(why.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.url.path), [], "the folder made for the move is taken back")
    }

    func testANameAlreadyTakenInICloudIsRefusedWithBothFilesIntact() async throws {                // TC-11 (open question 7: one defined state, nothing lost)
        let root = TempDir("root"), docs = TempDir("docs")
        let mine = savedPlaylist(at: docs.path("Dinner.\(playlistFileExtension)"), tracks: 1)
        let theirs = savedPlaylist(at: root.url.appendingPathComponent("Dinner/Dinner.\(playlistFileExtension)"), tracks: 3)
        let mineBytes = try Data(contentsOf: mine), theirBytes = try Data(contentsOf: theirs)
        let (core, _) = core(root: root.url, answer: .move)
        guard case .failed(let why) = await core.turnOn(playlistAt: mine) else { return XCTFail("expected a refusal") }
        XCTAssertTrue(why.contains("Dinner"), why)
        XCTAssertEqual(try Data(contentsOf: mine), mineBytes)
        XCTAssertEqual(try Data(contentsOf: theirs), theirBytes)
    }

    func testThereIsNoWayBackFromOn() async throws {                                                // TC-14, TC-23, TC-26
        let root = TempDir("root")
        let file = savedPlaylist(at: root.url.appendingPathComponent("Dinner/Dinner.\(playlistFileExtension)"))
        let (core, presenter) = core(root: root.url, answer: .move)
        let first = await core.turnOn(playlistAt: file)
        let second = await core.turnOn(playlistAt: file)
        XCTAssertEqual(first, .on(file))
        XCTAssertEqual(second, .on(file), "a second turn-on is the same no-op")
        XCTAssertEqual(presenter.asked, 0)
        let source = try String(contentsOf: Fixtures.directory.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PlayawayCore/Sync/PlaylistSync.swift"), encoding: .utf8)
        for forbidden in ["turnOff", "markUnsynced", "case off(", "func unsync"] {
            XCTAssertFalse(source.contains(forbidden), "no way back from on: found \(forbidden)")
        }
    }

    func testTheCloudLocationOfAPlaylistIsItsOwnFolderInThePlayawayFolder() {
        let root = URL(fileURLWithPath: "/cloud/Documents")
        let location = PlaylistLibrary.cloudPlaylistLocation(in: root, name: "Dinner")
        XCTAssertEqual(location.directory.path, "/cloud/Documents/Dinner")
        XCTAssertEqual(location.file.path, "/cloud/Documents/Dinner/Dinner.\(playlistFileExtension)")
    }
}
