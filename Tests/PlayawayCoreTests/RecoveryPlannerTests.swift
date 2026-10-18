import XCTest
@testable import PlayawayCore

/// Story 41, grant.recovery_plan: what to ask for, and judging what the person chose.
final class RecoveryPlannerTests: XCTestCase {
    let dir = TempDir("recovery")
    var drive: URL { dir.url.appendingPathComponent("Drive", isDirectory: true) }

    func roots(grants: InMemoryFolderGrantStore = InMemoryFolderGrantStore(), matches: InMemoryDeviceMatchStore = InMemoryDeviceMatchStore()) -> GrantedCloudRoots {
        let prefix = drive.canonicalPath + "/"
        return GrantedCloudRoots(playawayDocuments: nil, store: grants, matchStore: matches,
                                 drivePath: { url in url.canonicalPath.hasPrefix(prefix) ? String(url.canonicalPath.dropFirst(prefix.count)) : nil })
    }
    @discardableResult func make(_ relative: String, size: Int = 1) throws -> URL {
        let url = drive.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: size).write(to: url)
        return url
    }
    func song(_ path: String, size: Int64? = nil) -> UnfoundSong {
        UnfoundSong(id: UUID(), location: .iCloudDrive(path), fileName: String(path.split(separator: "/").last!), fileSize: size)
    }

    func testThePlanGroupsByTopFolderWithCounts() {                                 // TC-30
        let unfound = (0..<45).map { CloudPath.iCloudDrive("Mixdowns/s\($0).mp3") } + (0..<3).map { CloudPath.iCloudDrive("Live/l\($0).mp3") }
        let plan = RecoveryPlanner.plan(unfound: unfound, found: [])
        XCTAssertEqual(plan?.folders.map(\.name), ["Mixdowns", "Live"])
        XCTAssertEqual(plan?.folders.map(\.trackCount), [45, 3])
        XCTAssertEqual(plan?.trackCount, 48)
    }
    func testAFolderWithASongFoundOnThisDeviceIsNeverAskedFor() {                   // TC-31
        let unfound: [CloudPath] = [.iCloudDrive("Mixdowns/renamed.mp3")]
        XCTAssertNil(RecoveryPlanner.plan(unfound: unfound, found: [.iCloudDrive("Mixdowns/here.mp3")]), "the phone that made the playlist")
        XCTAssertEqual(RecoveryPlanner.plan(unfound: unfound, found: [.iCloudDrive("Other/x.mp3")])?.folders.map(\.name), ["Mixdowns"])
    }
    func testNothingToAskWhenNothingIsUnfoundOrOnlyPlayawayFolderPaths() {          // TC-32
        XCTAssertNil(RecoveryPlanner.plan(unfound: [], found: []))
        XCTAssertNil(RecoveryPlanner.plan(unfound: [.playawayFolder("Trip/a.mp3"), .iCloudDrive("root.mp3")], found: []))
    }
    func testThePickedFolderThatIsTheNeededOneRestoresEverything() throws {         // TC-33
        try make("Mixdowns/a.mp3"); try make("Mixdowns/Live/b.mp3")
        let store = InMemoryFolderGrantStore()
        let result = RecoveryPlanner.apply(picked: drive.appendingPathComponent("Mixdowns"), unfound: [song("Mixdowns/a.mp3"), song("Mixdowns/Live/b.mp3")], roots: roots(grants: store), listing: SystemFolderListing())
        XCTAssertEqual(result, RecoveryResult(restored: 2, needed: 2, kept: true, reason: nil))
        XCTAssertEqual(store.grants.map(\.drivePath), ["Mixdowns"])
    }
    func testAnAncestorFolderCoversTheNeededOne() throws {                          // TC-34
        try make("Music/Mixdowns/a.mp3")
        let result = RecoveryPlanner.apply(picked: drive.appendingPathComponent("Music"), unfound: [song("Music/Mixdowns/a.mp3")], roots: roots(), listing: SystemFolderListing())
        XCTAssertEqual(result.restored, 1); XCTAssertTrue(result.kept)
    }
    func testASubfolderRestoresPartAndCountsTheRest() throws {                      // TC-35
        try make("Mixdowns/a.mp3"); try make("Mixdowns/Live/b.mp3")
        let result = RecoveryPlanner.apply(picked: drive.appendingPathComponent("Mixdowns/Live"), unfound: [song("Mixdowns/a.mp3"), song("Mixdowns/Live/b.mp3")], roots: roots(), listing: SystemFolderListing())
        XCTAssertEqual(result.restored, 1); XCTAssertEqual(result.remaining, 1); XCTAssertTrue(result.kept)
    }
    func testAFolderOutsideICloudDriveIsNotKept() throws {                          // TC-36
        let elsewhere = dir.url.appendingPathComponent("Elsewhere"); try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let store = InMemoryFolderGrantStore()
        let result = RecoveryPlanner.apply(picked: elsewhere, unfound: [song("Mixdowns/a.mp3")], roots: roots(grants: store), listing: SystemFolderListing())
        XCTAssertFalse(result.kept); XCTAssertEqual(result.reason, .notInICloudDrive); XCTAssertEqual(store.grants, [])
    }
    func testAFolderHoldingNoneOfTheSongsIsRevokedAndNotKept() throws {             // TC-37
        try make("Empty/other.mp3")
        let store = InMemoryFolderGrantStore()
        let result = RecoveryPlanner.apply(picked: drive.appendingPathComponent("Empty"), unfound: [song("Mixdowns/a.mp3")], roots: roots(grants: store), listing: SystemFolderListing())
        XCTAssertFalse(result.kept); XCTAssertEqual(result.reason, .holdsNoneOfTheSongs); XCTAssertEqual(store.grants, [])
        XCTAssertEqual(RecoveryPlanner.apply(picked: nil, unfound: [song("Mixdowns/a.mp3")], roots: roots(), listing: SystemFolderListing()).reason, .cancelled)
    }
    func testTheHintIsTheFolderAsAnIOSDeviceLaysItOut() {                           // TC-38
        let folder = RecoveryFolder(name: "Mixdowns", drivePath: "Mixdowns", trackCount: 2)
        XCTAssertEqual(RecoveryPlanner.hint(for: folder)?.path, "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Mixdowns")
        XCTAssertNil(RecoveryPlanner.hint(for: RecoveryFolder(name: "", drivePath: "", trackCount: 0)))
    }
    func testADeletedGrantedFolderIsPlannedAgainAndAMovedSongIsFoundByName() throws {   // TC-39 (integration)
        let mixdowns = try make("Mixdowns/New/a.mp3").deletingLastPathComponent().deletingLastPathComponent()
        let grants = InMemoryFolderGrantStore(), matches = InMemoryDeviceMatchStore()
        let first = roots(grants: grants, matches: matches)
        let saved = song("Mixdowns/Old/a.mp3")
        let result = RecoveryPlanner.apply(picked: mixdowns, unfound: [saved], roots: first, listing: SystemFolderListing())
        XCTAssertEqual(result.restored, 1)
        XCTAssertEqual(matches.matches.moved, ["Mixdowns/Old/a.mp3": "Mixdowns/New/a.mp3"])
        XCTAssertNil(first.accessNeeded(for: saved.location), "before: nothing to ask")
        try FileManager.default.removeItem(at: mixdowns)
        let after = roots(grants: grants, matches: matches)
        XCTAssertEqual(after.accessNeeded(for: saved.location), "Mixdowns", "after: the folder is asked for again")
    }
    func testLocateKeepsAChosenFileForOneSongPerDevice() throws {
        let file = try make("Elsewhere/picked.mp3")
        let matches = InMemoryDeviceMatchStore()
        let r = roots(matches: matches)
        XCTAssertEqual(r.accessNeeded(for: .iCloudDrive("Mixdowns/a.mp3")), "Mixdowns")
        XCTAssertTrue(r.locate(savedPath: "Mixdowns/a.mp3", file: file))
        XCTAssertNil(r.accessNeeded(for: .iCloudDrive("Mixdowns/a.mp3")))
        XCTAssertEqual(roots(matches: matches).url(for: .iCloudDrive("Mixdowns/a.mp3"))?.canonicalPath, file.canonicalPath, "a new instance reopens it from the bookmark")
    }
}
