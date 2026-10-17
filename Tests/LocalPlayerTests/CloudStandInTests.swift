import XCTest
@testable import LocalPlayer
@testable import PlayawayCore

/// The debug-only iCloud stand-in the end-to-end tests launch the built app with: how the setting is read, and that
/// the stand-in answers like the system does over a plain folder (placeholder = not on this Mac, the file appearing
/// = downloaded, the error marker = failed). A release build ignores the setting.
final class CloudStandInTests: XCTestCase {
    let dir = TempDir("standin")

    func testTheSettingIsReadOnlyInADebugBuild() {
        XCTAssertEqual(CloudStandIn.setting(environment: [:], debugBuild: true), .real)
        XCTAssertEqual(CloudStandIn.setting(environment: [CloudStandIn.environmentKey: ""], debugBuild: true), .real)
        XCTAssertEqual(CloudStandIn.setting(environment: [CloudStandIn.environmentKey: "none"], debugBuild: true), .unavailable)
        XCTAssertEqual(CloudStandIn.setting(environment: [CloudStandIn.environmentKey: dir.url.path], debugBuild: true),
                       .folder(URL(fileURLWithPath: dir.url.path, isDirectory: true)))
        XCTAssertEqual(CloudStandIn.setting(environment: [CloudStandIn.environmentKey: dir.url.path], debugBuild: false), .real,
                       "a release build never reads it")
        XCTAssertEqual(CloudStandIn.setting(environment: [CloudStandIn.environmentKey: "none"], debugBuild: false), .real)
    }

    /// Temp folders sit behind a symlink (/var -> /private/var); a song that is not here yet has no real path to resolve.
    func testASongThatIsNotHereYetUnderASymlinkedRootIsStillInside() throws {
        let link = dir.url.appendingPathComponent("link")
        let real = dir.url.appendingPathComponent("Real", isDirectory: true)
        try FileManager.default.createDirectory(at: real.appendingPathComponent("Dinner"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let absent = link.appendingPathComponent("Dinner/away.mp3")
        XCTAssertFalse(FileManager.default.fileExists(atPath: absent.path))
        XCTAssertTrue(CloudStandIn.isInside(absent, root: link))
        XCTAssertTrue(CloudStandIn.isInside(absent, root: real))
        XCTAssertTrue(CloudStandIn.isInside(real.appendingPathComponent("Dinner/away.mp3"), root: link))
        XCTAssertEqual(CloudStandIn.reading(of: absent, root: link).isDownloading, true)
        XCTAssertFalse(CloudStandIn.isInside(dir.url.appendingPathComponent("away.mp3"), root: link))
    }

    func testTheRealSettingHandsNothingOverAndTheOthersStandIn() {
        XCTAssertNil(CloudStandIn.cloudRoot(for: .real))
        XCTAssertNil(CloudStandIn.isUbiquitous(for: .real))
        XCTAssertNil(CloudStandIn.cloudSongs(for: .real))
        XCTAssertNil(CloudStandIn.cloudRoot(for: .unavailable)?())
        XCTAssertEqual(CloudStandIn.isUbiquitous(for: .unavailable)?(dir.url), false)
        XCTAssertNil(CloudStandIn.cloudSongs(for: .unavailable), "nothing to download from when iCloud is unavailable")
        let root = dir.url.appendingPathComponent("Cloud", isDirectory: true)
        XCTAssertEqual(CloudStandIn.cloudRoot(for: .folder(root))?(), root)
        XCTAssertEqual(CloudStandIn.isUbiquitous(for: .folder(root))?(root.appendingPathComponent("A/x.mp3")), true)
        XCTAssertEqual(CloudStandIn.isUbiquitous(for: .folder(root))?(dir.url.appendingPathComponent("x.mp3")), false)
        XCTAssertEqual(CloudStandIn.isUbiquitous(for: .folder(root))?(root), false, "the folder itself is not a song in it")
        XCTAssertNotNil(CloudStandIn.cloudSongs(for: .folder(root)))
    }

    func testTheStandInReadsAFolderLikeTheSystemReadsICloud() throws {
        let root = dir.url.appendingPathComponent("Cloud", isDirectory: true)
        let folder = root.appendingPathComponent("Dinner", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let here = folder.appendingPathComponent("here.mp3")
        let away = folder.appendingPathComponent("away.mp3")
        let outside = dir.url.appendingPathComponent("outside.mp3")
        try Data([1]).write(to: here)
        try Data().write(to: folder.appendingPathComponent(".away.mp3.icloud"))
        try Data([1]).write(to: outside)
        let songs = try XCTUnwrap(CloudStandIn.cloudSongs(for: .folder(root)) as? MacCloudSongs)
        XCTAssertEqual(songs.presence(of: here), .inCloudOnDevice)
        XCTAssertEqual(songs.presence(of: away), .inCloudNotOnDevice)
        XCTAssertEqual(songs.presence(of: outside), .localOnly)
        XCTAssertEqual(CloudStandIn.reading(of: here, root: root),
                       UbiquitousReading(isUbiquitous: true, status: ubiquitousStatusCurrent, isDownloading: false, hasError: false))
        XCTAssertEqual(CloudStandIn.reading(of: away, root: root),
                       UbiquitousReading(isUbiquitous: true, status: ubiquitousStatusNotDownloaded, isDownloading: true, hasError: false))
        XCTAssertEqual(CloudStandIn.reading(of: outside, root: root), UbiquitousReading())
        XCTAssertThrowsError(try songs.startDownloading(outside), "nothing outside the folder downloads")
        XCTAssertNoThrow(try songs.startDownloading(away))
    }

    func testADownloadFinishesWhenTheFileAppearsAndFailsOnTheErrorMarker() throws {
        let root = dir.url.appendingPathComponent("Cloud", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let away = root.appendingPathComponent("away.mp3")
        let failing = root.appendingPathComponent("failing.mp3")
        for url in [away, failing] { try Data().write(to: root.appendingPathComponent(".\(url.lastPathComponent).icloud")) }
        let songs = try XCTUnwrap(CloudStandIn.cloudSongs(for: .folder(root)) as? MacCloudSongs)
        var events: [DownloadEvent] = []
        songs.onEvent = { events.append($0) }
        songs.startDownload(of: MacSongs.id(for: away))
        songs.poll(MacSongs.id(for: away))
        XCTAssertEqual(events, [.progress(MacSongs.id(for: away), reportedPercent: nil)], "still on its way: progress without a percent")
        try Data([1]).write(to: away)
        songs.poll(MacSongs.id(for: away))
        XCTAssertEqual(events.last, .finished(MacSongs.id(for: away)))
        XCTAssertFalse(songs.isWatching(MacSongs.id(for: away)))
        songs.startDownload(of: MacSongs.id(for: failing))
        try Data().write(to: CloudStandIn.errorMarker(for: failing))
        songs.poll(MacSongs.id(for: failing))
        XCTAssertEqual(events.last, .failed(MacSongs.id(for: failing)))
        XCTAssertFalse(songs.isWatching(MacSongs.id(for: failing)))
    }
}

/// The stand-in over the real app wiring, in-process: a synced playlist with a song that is only a placeholder,
/// played from its row, downloads through the real `MacCloudSongs` timer and plays when the test delivers the file.
@MainActor
final class CloudStandInWiringTests: XCTestCase {
    let dir = TempDir("standinwiring")
    var app: TestApp!

    override func tearDown() async throws { app?.tearDown() }

    func testARowPlayedThroughTheStandInDownloadsAndPlaysWhenTheFileArrives() throws {
        let root = dir.url.appendingPathComponent("Cloud", isDirectory: true)
        let folder = root.appendingPathComponent("Trip", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let here = folder.appendingPathComponent("track1.mp3"), absent = folder.appendingPathComponent("track3.mp3")
        try FileManager.default.copyItem(at: Fixtures.url("track1.mp3"), to: here)
        try Data().write(to: folder.appendingPathComponent(".track3.mp3.icloud"))
        let songs = try XCTUnwrap(CloudStandIn.cloudSongs(for: .folder(root)))
        app = TestApp(cloudRoot: { root }, cloudSongs: songs)
        app.services.cloud.isUbiquitous = CloudStandIn.isUbiquitous(for: .folder(root))!
        let tracks = [Track(id: UUID(), reference: TrackReference.make(for: here)!),
                      Track(id: UUID(), reference: TrackReference(bookmark: Data(), lastKnownPath: absent.path, fileName: "track3.mp3"))]
        let doc = app.openSaved(Playlist(tracks: tracks), at: folder.appendingPathComponent("Trip.\(playlistFileExtension)"))
        var done = false; doc.resolveStatuses { done = true }; spin { done }
        let window = app.window(of: doc)
        window.reload()
        let cell = { (row: Int) in window.tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as! TrackCellView }
        XCTAssertEqual(cell(1).cloudKind, .outline); XCTAssertTrue(cell(1).isGreyedOut)
        window.playRow(1)
        spin { cell(1).cloudKind == .pieDownload }
        XCTAssertEqual(cell(1).cloudKind, .pieDownload, "the real timer-driven download is under way")
        XCTAssertNil(app.services.engine.currentURL)
        let temp = folder.appendingPathComponent(".delivering")
        try FileManager.default.copyItem(at: Fixtures.url("track3.mp3"), to: temp)
        try FileManager.default.moveItem(at: temp, to: absent)
        try FileManager.default.removeItem(at: folder.appendingPathComponent(".track3.mp3.icloud"))
        spin(timeout: 5) { self.app.services.engine.currentURL != nil }
        XCTAssertEqual(app.services.engine.currentURL?.canonicalPath, absent.canonicalPath, "plays when it arrives; mark: \(app.services.marks.mark(of: tracks[1]))")
        XCTAssertEqual(cell(1).cloudKind, .outline); XCTAssertFalse(cell(1).isGreyedOut)
    }

    /// The script route: `play track` waits inside its own run-loop loop while the stand-in's timer polls; the file
    /// arrives on a timer of the test, as another process would deliver it.
    func testAScriptedPlayThroughTheStandInReturnsOnceTheDeliveredSongPlays() throws {
        let root = dir.url.appendingPathComponent("Cloud", isDirectory: true)
        let folder = root.appendingPathComponent("Trip", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let absent = folder.appendingPathComponent("track3.mp3")
        try Data().write(to: folder.appendingPathComponent(".track3.mp3.icloud"))
        let songs = try XCTUnwrap(CloudStandIn.cloudSongs(for: .folder(root)))
        app = TestApp(cloudRoot: { root }, cloudSongs: songs)
        app.services.cloud.isUbiquitous = CloudStandIn.isUbiquitous(for: .folder(root))!
        let track = Track(id: UUID(), reference: TrackReference(bookmark: Data(), lastKnownPath: absent.path, fileName: "track3.mp3"))
        let doc = app.openSaved(Playlist(tracks: [track]), at: folder.appendingPathComponent("Trip.\(playlistFileExtension)"))
        var done = false; doc.resolveStatuses { done = true }; spin { done }
        let actions = AppActions(services: app.services)
        actions.isReady = { true }
        let delivery = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
            let temp = folder.appendingPathComponent(".delivering")
            try! FileManager.default.copyItem(at: Fixtures.url("track3.mp3"), to: temp)
            try! FileManager.default.moveItem(at: temp, to: absent)
        }
        RunLoop.main.add(delivery, forMode: .common)
        XCTAssertNoThrow(try actions.playTrack(1, inPlaylist: "Trip"), "state: \(app.services.downloads.state(of: MacSongs.id(for: absent))) mark: \(app.services.marks.mark(of: track))")
        XCTAssertEqual(app.services.engine.currentURL?.canonicalPath, absent.canonicalPath)
    }
}
