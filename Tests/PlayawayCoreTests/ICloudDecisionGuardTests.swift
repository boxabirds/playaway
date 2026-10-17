import XCTest
@testable import PlayawayCore

/// Story 19's drift guards: the "is this file in iCloud" decision exists in one shared place and the platform seams
/// that read the system's answer; the Mac's turn-on adapter holds no flow logic of its own (it only calls the one
/// shared SongIntakeFlow). A second copy of either would let the Mac, the iPhone and the dialogs disagree.
final class ICloudDecisionGuardTests: XCTestCase {
    private let root = Fixtures.directory.deletingLastPathComponent().deletingLastPathComponent()

    private func swiftFiles(under folders: [String]) -> [URL] {
        folders.flatMap { folder -> [URL] in
            let base = root.appendingPathComponent(folder)
            guard let walk = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
            return walk.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        }
    }

    private func files(containing needle: String, under folders: [String] = ["Sources", "ios/App"]) -> Set<String> {
        Set(swiftFiles(under: folders).filter { (try? String(contentsOf: $0, encoding: .utf8))?.contains(needle) == true }
            .map { $0.path.replacingOccurrences(of: root.path + "/", with: "") })
    }

    func testTheSystemsICloudAnswerIsReadOnlyByThePlatformSeams() {                                 // 19.15
        XCTAssertEqual(files(containing: "isUbiquitousItemKey"),
                       ["ios/App/CloudSongs.swift", "Sources/LocalPlayer/Sync/CloudFolderLocator.swift", "Sources/LocalPlayer/Sync/MacCloudSongs.swift"],
                       "the system is asked whether a file is in iCloud Drive only by each platform's cloud seam")
    }

    func testTheLocationRuleIsSharedAndUsedOnlyByTheSyncCoreAndTheSeams() {                        // 19.15
        XCTAssertEqual(files(containing: "isStrictlyInside("),
                       ["Sources/PlayawayCore/Sync/ICloudLocation.swift", "Sources/PlayawayCore/Sync/PlaylistSync.swift", "ios/App/CloudSongs.swift"],
                       "strictly-inside-the-Playaway-folder is written once and read by the playlist sync core and the phone's fake cloud")
    }

    func testTheMacTurnOnAdapterOnlyCallsTheSharedFlow() throws {                                   // TC-111, TC-117
        let adapter = try String(contentsOf: root.appendingPathComponent("Sources/LocalPlayer/Sync/PlaylistSyncController.swift"), encoding: .utf8)
        XCTAssertTrue(adapter.contains("SongIntakeFlow("), "the adapter calls the one shared flow")
        for forbidden in ["FilesPrompt.", "runTransfer(", "FileAssessor(", "transferDestination(", ".doNothing", "copiedInsteadReport"] {
            XCTAssertFalse(adapter.contains(forbidden), "no flow logic of its own: found \(forbidden)")
        }
    }
}
