import XCTest
@testable import LocalPlayer
@testable import PlayawayCore

/// Story 18 task 18.10 and story 20 task 20.18 on the real thing: the built app against the Playaway container of the
/// iCloud account this Mac is signed in to. It writes one playlist with one fixture song into a folder of its own in
/// the container ("E2E Check (delete me)"), waits for the upload, evicts the song, and plays it through the app, which
/// downloads it again. The folder is removed at the end. It runs only when the owner asks for it:
///   LP_REAL_ICLOUD_E2E=1 swift test --filter RealICloudE2ETests   (after scripts/run-e2e.sh built the bundle)
/// because it reaches a real iCloud account and its other devices see the folder while the test runs.
final class RealICloudE2ETests: XCTestCase {
    static let approvalKey = "LP_REAL_ICLOUD_E2E"
    static let folderName = "E2E Check (delete me)"
    static let uploadTimeout: TimeInterval = 240
    static let evictTimeout: TimeInterval = 60
    static let downloadTimeout: TimeInterval = 120
    static let settle: TimeInterval = 2

    let app = E2EApp()
    let dir = TempDir("realicloud")
    var container: URL? { CloudFolder.documentsOnThisDevice() }
    var folder: URL { container!.appendingPathComponent(Self.folderName, isDirectory: true) }

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment[Self.approvalKey] == "1", "reaches a real iCloud account: set \(Self.approvalKey)=1 to run")
        try XCTSkipUnless(app.isBuilt, "dev bundle not built: run scripts/run-e2e.sh")
        try XCTSkipUnless(container != nil, "this Mac has no Playaway container in iCloud Drive")
        continueAfterFailure = false
        try? FileManager.default.removeItem(at: folder)
        app.reset()
    }

    override func tearDown() {
        app.tearDown()
        try? FileManager.default.removeItem(at: folder)
    }

    /// NSURL caches resource values on the object; a fresh URL for every read sees what iCloud says now.
    func fresh(_ url: URL) -> URL { URL(fileURLWithPath: url.path) }
    func status(of url: URL) -> String? { (try? fresh(url).resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus?.rawValue }
    func describe(_ url: URL) -> String {
        guard let v = try? fresh(url).resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey, .ubiquitousItemUploadingErrorKey]) else { return "unreadable" }
        return "ubiquitous=\(String(describing: v.isUbiquitousItem)) status=\(v.ubiquitousItemDownloadingStatus?.rawValue ?? "nil") uploaded=\(String(describing: v.ubiquitousItemIsUploaded)) uploading=\(String(describing: v.ubiquitousItemIsUploading)) error=\(String(describing: v.ubiquitousItemUploadingError))"
    }
    func isUploaded(_ url: URL) -> Bool { (try? fresh(url).resourceValues(forKeys: [.ubiquitousItemIsUploadedKey]))?.ubiquitousItemIsUploaded == true }

    func testASyncedPlaylistLandsInThePlaywayFolderAndAnEvictedSongIsDownloadedAgainWhenPlayed() throws {   // 18 E2E-2; 20 E2E-5
        let song = dir.copyFixture("long30.mp3")
        try app.launch()
        XCTAssertEqual(app.osa("new playlist at \(E2EApp.quoted(dir.path("\(Self.folderName).\(playlistFileExtension)").path))").out, Self.folderName)
        XCTAssertEqual(app.osa("add track \(E2EApp.quoted(song.path)) to \(E2EApp.quoted(Self.folderName))").status, 0)
        XCTAssertEqual(app.osa("get iCloud sync of playlist document \(E2EApp.quoted(Self.folderName))").out, "false")
        let report = app.osa("sync playlist \(E2EApp.quoted(Self.folderName)) answering \"move\" files \"copy to iCloud\"")
        XCTAssertEqual(report.status, 0, report.err)
        XCTAssertTrue(report.out.contains("copied:1"), report.out)
        let playlistFile = folder.appendingPathComponent("\(Self.folderName).\(playlistFileExtension)")
        let copy = folder.appendingPathComponent("long30.mp3")
        XCTAssertTrue(FileManager.default.fileExists(atPath: playlistFile.path), "the playlist is in Playaway/<name>/ of the real container")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path), "the song beside it")
        XCTAssertTrue(FileManager.default.fileExists(atPath: song.path), "copied: the original stays")
        XCTAssertEqual(app.osa("get iCloud sync of playlist document \(E2EApp.quoted(Self.folderName))").out, "true")
        XCTAssertEqual(app.osa("get track iCloud states of playlist document \(E2EApp.quoted(Self.folderName))").out, "in iCloud")
        XCTAssertEqual((try? fresh(copy).resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem, true, "the system calls the copy ubiquitous")
        XCTAssertTrue(app.wait(timeout: Self.uploadTimeout) { self.isUploaded(copy) }, "iCloud uploads the song: \(describe(copy))")
        XCTAssertTrue(app.wait(timeout: Self.uploadTimeout) { self.isUploaded(playlistFile) }, "and the playlist: \(describe(playlistFile))")
        // Evicted: the song is in iCloud and not on this Mac. The app, opened again on the playlist, downloads it on play.
        app.quit()
        try FileManager.default.evictUbiquitousItem(at: copy)
        XCTAssertTrue(app.wait(timeout: Self.evictTimeout) { self.status(of: copy) == ubiquitousStatusNotDownloaded }, "evicted: \(status(of: copy) ?? "nil")")
        try app.launch()
        app.open(playlistFile)
        XCTAssertTrue(app.wait { self.app.osa("get name of every playlist document").out.contains(Self.folderName) })
        XCTAssertEqual(app.osa("get track iCloud states of playlist document \(E2EApp.quoted(Self.folderName))").out, "in iCloud", "location only")
        if !E2EApp.isScreenLocked {
            XCTAssertEqual(app.cloudLabels(inWindow: Self.folderName), ["In iCloud, not on this Mac"])
            XCTAssertEqual(app.rowLabels(inWindow: Self.folderName), ["long30, not on this Mac"])
        }
        let play = app.osaInBackground("play track 1 in \(E2EApp.quoted(Self.folderName))")
        XCTAssertTrue(app.wait(timeout: Self.downloadTimeout) { !play.isRunning }, "the script returns once the song plays")
        XCTAssertEqual(play.terminationStatus, 0, "the script returned once the song played")
        XCTAssertTrue(app.waitFor("get playing", equals: "true"), "downloaded again and playing")
        XCTAssertEqual(app.osa("get current track").out, "long30.mp3")
        XCTAssertEqual(status(of: copy), ubiquitousStatusCurrent)
        if !E2EApp.isScreenLocked {
            XCTAssertEqual(app.cloudLabels(inWindow: Self.folderName), ["In iCloud"])
        }
        app.quit()
    }
}
