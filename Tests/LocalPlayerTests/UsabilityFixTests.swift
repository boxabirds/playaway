import XCTest
import AppKit
@testable import LocalPlayer
@testable import PlayawayCore

/// Fixes from the HIG review: undo, Delete and Return in the list, spoken missing state, Space, layout.
@MainActor
final class UsabilityFixTests: XCTestCase {
    var app: TestApp!
    var folders: [TempDir] = []
    var fixtures: [PlaylistFixture] = []
    override func setUp() async throws { app = TestApp() }
    override func tearDown() async throws { app.tearDown() }

    func open(_ names: [String]) -> PlaylistDocument {
        let dir = TempDir(); folders.append(dir)
        let fixture = PlaylistFixture(trackNames: names); fixtures.append(fixture)
        let doc = app.openSaved(fixture.playlist, at: dir.path("U.lplaylist"))
        doc.undoManager?.removeAllActions()
        return doc
    }

    func testUndoAndRedoOfRemoveMoveAndAdd() throws {
        let doc = open(["track1.mp3", "track2.mp3", "track3.mp3"])
        let original = doc.playlist
        try doc.removeTracks(at: [1])
        XCTAssertEqual(doc.playlist.tracks.count, 2)
        XCTAssertEqual(doc.undoManager?.undoActionName, "Remove from Playlist")
        doc.undoManager?.undo()
        XCTAssertEqual(doc.playlist, original, "undo puts the same tracks back in the same places")
        doc.undoManager?.redo()
        XCTAssertEqual(doc.playlist.tracks.count, 2)
        doc.undoManager?.undo()
        try doc.moveTrack(from: 2, to: 0)
        doc.undoManager?.undo()
        XCTAssertEqual(doc.playlist, original)
        doc.addFiles([Fixtures.url("tone.wav")])
        XCTAssertEqual(doc.playlist.tracks.count, 4)
        doc.undoManager?.undo()
        XCTAssertEqual(doc.playlist, original)
        waitForAutosave(doc)
        guard case .loaded(let onDisk) = PlaylistStore().load(from: doc.fileURL!) else { return XCTFail() }
        XCTAssertEqual(onDisk, original, "the undone state is what is autosaved")
    }

    func testUndoNeverTouchesTheAudioFiles() throws {
        let doc = open(["track1.mp3", "track2.mp3"])
        let snapshot = FileSnapshot(fixtures.last!.urls[0])
        try doc.removeTracks(at: [0]); doc.undoManager?.undo()
        XCTAssertEqual(FileSnapshot(fixtures.last!.urls[0]), snapshot)
    }

    func testDeleteKeyRemovesTheSelectedRowsThroughTheResponderChain() {
        let doc = open(["track1.mp3", "track2.mp3", "track3.mp3"])
        let window = app.window(of: doc)
        window.tableView.selectRowIndexes([0, 2], byExtendingSelection: false)
        window.deleteBackward(nil)
        XCTAssertEqual(doc.playlist.tracks.map(\.reference.fileName), ["track2.mp3"])
        window.tableView.selectRowIndexes([0], byExtendingSelection: false)
        window.deleteForward(nil)
        XCTAssertTrue(doc.playlist.tracks.isEmpty)
        window.deleteBackward(nil)      // nothing selected: nothing happens
    }

    func testReturnPlaysTheSelectedRowAndDoesNothingWithoutASelection() {
        let doc = open(["track1.mp3", "track2.mp3"])
        let window = app.window(of: doc)
        window.insertNewline(nil)
        XCTAssertTrue(app.backend.log.isEmpty)
        window.tableView.selectRowIndexes([1], byExtendingSelection: false)
        window.insertNewline(nil)
        XCTAssertEqual(app.services.engine.currentURL?.lastPathComponent, "track2.mp3")
    }

    func testMissingRowIsSpokenNotJustGrey() {
        let doc = open(["track1.mp3", "track2.mp3"])
        fixtures.last!.deleteFile(at: 1)
        var done = false; doc.resolveStatuses { done = true }; spin { done }
        let window = app.window(of: doc)
        window.reload()
        let missing = window.tableView.view(atColumn: 0, row: 1, makeIfNecessary: true) as! TrackCellView
        let fine = window.tableView.view(atColumn: 0, row: 0, makeIfNecessary: true) as! TrackCellView
        XCTAssertEqual(missing.accessibilityLabel(), "track2, file not found")
        XCTAssertEqual(fine.accessibilityLabel(), "track1")
        doc.player.play(track: doc.playlist.tracks[1])
        window.reload()
        XCTAssertEqual((window.tableView.view(atColumn: 0, row: 1, makeIfNecessary: true) as! TrackCellView).accessibilityLabel(),
                       "track2, could not be played")
    }

    func testSpaceMenuItemTogglesPlayPauseThroughTheSameHandler() {
        let delegate = AppDelegate()
        delegate.services = app.services
        _ = app.services.engine.play(Fixtures.url("track1.mp3"))
        delegate.togglePlayPause(nil)
        XCTAssertEqual(app.services.engine.state, .paused)
        delegate.togglePlayPause(nil)
        XCTAssertEqual(app.services.engine.state, .playing)
    }

    func testLayoutUsesTwentyPointMarginsAndCentresTheTransportButtons() {
        let doc = open(["track1.mp3"])
        let window = app.window(of: doc)
        guard let content = window.window?.contentView as? NSStackView else { return XCTFail() }
        XCTAssertEqual(content.edgeInsets.left, 20); XCTAssertEqual(content.edgeInsets.top, 20)
        window.window?.setContentSize(NSSize(width: 600, height: 640))
        window.window?.layoutIfNeeded()
        let transport = window.transport
        let buttons = transport.playPauseButton.superview!
        let centre = transport.convert(NSPoint(x: buttons.frame.midX, y: 0), from: buttons.superview).x
        XCTAssertEqual(centre, transport.bounds.midX, accuracy: 1.5, "the Previous/Play/Stop/Next cluster is centred")
    }

    func testOnlyAPlainNonRepeatingSpaceCountsAsTheShortcut() {
        func event(_ chars: String, _ flags: NSEvent.ModifierFlags, repeat isRepeat: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                             characters: chars, charactersIgnoringModifiers: chars, isARepeat: isRepeat, keyCode: 49)!
        }
        XCTAssertTrue(AppDelegate.isPlainSpace(event(" ", [])))
        XCTAssertFalse(AppDelegate.isPlainSpace(event(" ", .command)))
        XCTAssertFalse(AppDelegate.isPlainSpace(event(" ", .shift)))
        XCTAssertFalse(AppDelegate.isPlainSpace(event("a", [])))
        XCTAssertFalse(AppDelegate.isPlainSpace(event(" ", [], repeat: true)), "holding the key must not flicker pause/play")
    }
}
