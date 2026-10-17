import XCTest
@testable import PlayawayCore

/// Story 21 (TC-96 to TC-98): the one shared flow gives the same outcome for the same songs whichever way they arrive.
/// The entry kind is recorded, never consulted. Real temp audio files and a temp Playaway folder; no real iCloud.
final class SongIntakeParityTests: XCTestCase {
    private final class Answering: FilesPromptPresenting {
        let answer: FilesChoice
        private(set) var asked = 0, messages: [String] = []
        init(_ answer: FilesChoice) { self.answer = answer }
        func askFilesChoice() async -> FilesChoice { asked += 1; return answer }
        func show(message: String) async { messages.append(message) }
    }

    private var dir: TempDir!
    private var root: URL!
    private var kept: [PlaylistFixture] = []

    override func setUp() {
        dir = TempDir("parity")
        root = dir.url.appendingPathComponent("Playaway")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// The same songs (fresh copies) for each run, so one entry's move cannot affect another's.
    private func songs(_ count: Int) -> Playlist {
        let fixture = PlaylistFixture(trackNames: Array(Fixtures.trackNames.prefix(count)))
        kept.append(fixture)
        return fixture.playlist
    }

    private func run(_ playlist: Playlist, name: String, source: IntakeSource, answer: FilesChoice) async -> (IntakeOutcome, Answering) {
        let presenter = Answering(answer)
        let flow = SongIntakeFlow(root: root, isUbiquitous: { [root] in isStrictlyInside($0, folder: root) }, resolve: { track in
            if case .resolved(let url) = TrackResolver().resolve(track.reference).0 { return url } else { return nil }
        }, presenter: presenter)
        return (await flow.run(playlist: playlist, playlistName: name, tracks: playlist.tracks, source: source), presenter)
    }

    /// What an outcome looks like with the song files' identities abstracted away: the same shape for every entry.
    private func shape(_ outcome: IntakeOutcome, _ presenter: Answering, name: String) -> [String] {
        let rows = outcome.playlist.tracks.map { track -> String in
            let path = URL(fileURLWithPath: track.reference.lastKnownPath).canonicalPath
            return (path.hasPrefix(root.appendingPathComponent(name).canonicalPath) ? "folder/" : "outside/") + track.reference.fileName
        }
        return ["asked \(presenter.asked)", "choice \(String(describing: outcome.choice))", "moved \(outcome.result.moved)",
                "copied \(outcome.result.copied)", "copiedInstead \(outcome.result.copiedInstead)", "failures \(outcome.result.failures.count)"]
            + presenter.messages + rows
    }

    func testEveryEntryGivesTheSameDecisionTransferAndRowsForTheSameSongs() async {           // TC-96, TC-100, TC-101
        for answer in [FilesChoice.moveToICloud, .copyToICloud, .doNothing] {
            var shapes: [IntakeSource: [String]] = [:]
            for source in [IntakeSource.turnOnSync, .drop, .script, .iPhoneAdd] {
                let name = "P-\(answer)-\(source)"
                let (outcome, presenter) = await run(songs(3), name: name, source: source, answer: answer)
                shapes[source] = shape(outcome, presenter, name: name)
            }
            XCTAssertEqual(Set(shapes.values).count, 1, "\(answer): every entry the same, got \(shapes)")
        }
    }

    func testZeroOneAndManySongsGiveTheSameNumberOfQuestionsFromEveryEntry() async {           // TC-98
        for count in [0, 1, 3] {
            var asked: Set<Int> = []
            for source in [IntakeSource.turnOnSync, .drop, .script, .iPhoneAdd] {
                let (_, presenter) = await run(songs(count), name: "Q-\(count)-\(source)", source: source, answer: .doNothing)
                asked.insert(presenter.asked)
            }
            XCTAssertEqual(asked, [count == 0 ? 0 : 1], "\(count) songs: one question or none, alike for every entry")
        }
    }

    func testThereIsOneDialogDefinitionWithTheOwnersLabelsAndRoles() {                           // TC-97
        XCTAssertEqual(FilesPrompt.title, "Sync with iCloud: Files")
        XCTAssertEqual(FilesPrompt.message, "This is an iCloud playlist, and Some of the files in your playlist are not in iCloud.")
        XCTAssertEqual(FilesPrompt.buttons.map(\.label), ["Move to iCloud", "Copy to iCloud", "Add Without Syncing"])
        XCTAssertEqual(FilesPrompt.buttons.map(\.role), [.destructive, .defaultAction, .plain], "Move destructive, Copy the default")
        XCTAssertFalse(FilesPrompt.buttons.contains { $0.label.contains("Do Nothing") }, "the old label appears nowhere a person sees")
    }
}
