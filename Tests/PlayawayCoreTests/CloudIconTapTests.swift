import XCTest
@testable import PlayawayCore

final class CloudIconTapTests: XCTestCase {
    func testDecisionForEveryStateAndKind() {
        for kind in [SyncItemKind.song, .playlist] {
            XCTAssertEqual(cloudIconTapAction(state: .crossedOut, kind: kind), .openSyncDialog(kind))
            XCTAssertEqual(cloudIconTapAction(state: .outline, kind: kind), CloudIconTapAction.none)
            XCTAssertEqual(cloudIconTapAction(state: .pieDownload, kind: kind), .cancelDownload)
            XCTAssertEqual(cloudIconTapAction(state: .pieSync, kind: kind), .cancelSync)
            XCTAssertEqual(cloudIconTapAction(state: .exclamation, kind: kind), .retryDownload)
        }
    }

    func testTappableAreaIsAtLeast44Points() {
        XCTAssertGreaterThanOrEqual(minimumCloudIconTapSize.width, 44)
        XCTAssertGreaterThanOrEqual(minimumCloudIconTapSize.height, 44)
    }

    func testDrawnIconIsSmallerThanItsTappableArea() {
        XCTAssertLessThan(cloudIconDrawnSize.width, minimumCloudIconTapSize.width)
        XCTAssertLessThan(cloudIconDrawnSize.height, minimumCloudIconTapSize.height)
    }

    // MARK: Story 31, task 31.9: the dialog button sets, cancel from the dialog, no way to turn sync off

    func testTheExclamationMarkOnlyEverRetries() {                                              // TC-66
        for kind in [SyncItemKind.song, .playlist] {
            let action = cloudIconTapAction(state: .exclamation, kind: kind)
            XCTAssertEqual(action, .retryDownload)
            XCTAssertNotEqual(action, .cancelDownload)
            if case .openSyncDialog = action { XCTFail("never opens the dialog") }
        }
    }

    func testTheDialogButtonSetsComeFromTheirOwningStories() {                                   // TC-35
        XCTAssertEqual(FilesPrompt.buttons.map(\.label), ["Move to iCloud", "Copy to iCloud", "Add Without Syncing"],
                       "a song's dialog: the Files dialog of story 19 (its third button renamed by the owner's HIG review)")
        XCTAssertEqual([PlaylistPrompt.moveLabel, PlaylistPrompt.dontSyncLabel], ["Move", "Don't Sync"],
                       "a playlist's dialog: the Playlist dialog of story 18")
    }

    func testCancelFromTheDialogLeavesTheItemNotSyncedAndMovesNothing() async {                   // TC-36
        final class DontSync: PlaylistPromptPresenting { func askPlaylistChoice() async -> PlaylistChoice { .dontSync } }
        struct NeverMoves: PlaylistMoving { func movePlaylist(from: URL, to: URL) async throws { XCTFail("nothing moves") } }
        let dir = TempDir("tap-cancel"), root = TempDir("tap-root")
        let file = dir.path("Dinner.\(playlistFileExtension)")
        XCTAssertEqual(PlaylistStore().save(Playlist(), to: file), .saved)
        let core = PlaylistSyncCore(availability: .available(root: root.url), mover: NeverMoves(), presenter: DontSync())
        let outcome = await core.turnOn(playlistAt: file)
        XCTAssertEqual(outcome, .left)
        XCTAssertEqual(playlistSyncState(of: file, root: root.url), .off)
        XCTAssertEqual(FilesPrompt.dismissalChoice, .doNothing, "and the Files dialog's dismissal moves nothing either")
    }

    func testCancellingASyncIsADecisionOnlyAndNeverADownloadCommand() {                           // TC-37 (open question 9 not asserted)
        XCTAssertEqual(cloudIconTapAction(state: .pieSync, kind: .song), .cancelSync)
        XCTAssertEqual(cloudIconTapAction(state: .pieSync, kind: .playlist), .cancelSync)
        XCTAssertNotEqual(cloudIconTapAction(state: .pieSync, kind: .song), .cancelDownload)
    }

    func testNoIconStateLeadsFromSyncedToNotSynced() {                                            // owner decision 2026-10-13
        let everyAction: [CloudIconTapAction] = [.openSyncDialog(.song), .openSyncDialog(.playlist), .none, .cancelDownload, .cancelSync, .retryDownload]
        for state in [CloudIconState.crossedOut, .outline, .pieDownload, .pieSync, .exclamation] {
            for kind in [SyncItemKind.song, .playlist] {
                XCTAssertTrue(everyAction.contains(cloudIconTapAction(state: state, kind: kind)), "every decision is one of the six; none turns sync off")
            }
        }
        XCTAssertEqual(cloudIconTapAction(state: .outline, kind: .playlist), CloudIconTapAction.none, "the activated cloud does nothing")
    }
}
