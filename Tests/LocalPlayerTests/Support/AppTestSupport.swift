import AppKit
import XCTest
@testable import LocalPlayer
@testable import PlayawayCore

/// Brings up the pieces the real app builds in main.swift, with a recording audio sink and isolated defaults.
@MainActor
final class TestApp {
    static var bootstrapped = false

    let backend = RecordingAudioBackend()
    let notices = RecordingNotices()
    let services: AppServices
    let controller: PlaylistDocumentController

    /// `cloudRoot` stands in for the Playaway folder in iCloud Drive (nil: iCloud unavailable); by default no iCloud.
    init(hasDevice: Bool = true, store: PlaylistStoring = PlaylistStore(), resolver: TrackResolving? = nil,
         cloudRoot: @escaping () -> URL? = { nil }, conflictVersions: ConflictVersionReading = NoConflictVersions(),
         cloudSongs: CloudSongsProviding? = nil) {
        if !Self.bootstrapped {
            _ = PlaylistDocumentController()      // the first controller created becomes the shared one
            _ = NSApplication.shared
            Self.bootstrapped = true
        }
        PlaylistWindowController.animatesWindows = false
        NoticePresenter.animatesAlerts = false
        precondition(NSDocumentController.shared is PlaylistDocumentController, "shared controller must be ours")
        controller = PlaylistDocumentController.current
        let defaults = isolatedDefaults()
        let engine = AVPlaybackEngine(backend: backend, devices: StubOutputDevices(hasOutputDevice: hasDevice),
                                      settings: VolumeSettingsStore(defaults: defaults))
        services = AppServices(defaults: defaults, engine: engine, notices: notices, resolver: resolver, store: store,
                               shuffleOrder: seededShuffler(), runsTimer: false, cloudRoot: cloudRoot, conflictVersions: conflictVersions,
                               cloudSongs: cloudSongs ?? ScriptedCloudSongs(root: cloudRoot))
        services.cloud.isUbiquitous = { url in isStrictlyInside(url, folder: cloudRoot()) }   // in the stand-in, "in iCloud" is inside the root
        AppServices.shared = services
        services.connect(controller: controller)
        controller.closeAllDocuments(withDelegate: nil, didCloseAllSelector: nil, contextInfo: nil)
    }

    func tearDown() {
        for document in controller.documents { document.close() }
    }

    func newDocument() -> PlaylistDocument {
        try! controller.openUntitledDocumentAndDisplay(true) as! PlaylistDocument
    }

    func window(of document: PlaylistDocument) -> PlaylistWindowController {
        document.windowControllers.first as! PlaylistWindowController
    }

    /// Saves an untitled document to `url` the way the Save panel would after the person confirms.
    func save(_ document: PlaylistDocument, to url: URL) {
        var done = false
        document.save(to: url, ofType: playlistTypeIdentifier, for: .saveOperation) { _ in done = true }
        spin { done }
    }

    /// A saved document with the given playlist content, opened through the real controller.
    func openSaved(_ playlist: Playlist, at url: URL) -> PlaylistDocument {
        XCTAssertEqual(PlaylistStore().save(playlist, to: url), .saved)
        var opened: NSDocument?
        var done = false
        controller.openDocument(withContentsOf: url, display: true) { document, _, _ in opened = document; done = true }
        spin { done }
        return opened as! PlaylistDocument
    }
}

/// Runs the main run loop until the condition holds, or the timeout passes.
func spin(timeout: TimeInterval = 5, until condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
}

func waitForAutosave(_ document: NSDocument) {
    spin { !document.isDocumentEdited }
}

/// The stand-in for iCloud on the Mac: a song is in iCloud when it is inside the stand-in root, and on this Mac unless
/// the test says otherwise; downloads happen when the test says they do.
final class ScriptedCloudSongs: CloudSongsProviding {
    var onEvent: ((DownloadEvent) -> Void)?
    private let root: () -> URL?
    /// Canonical paths of songs inside the root that are not downloaded to this Mac.
    var notOnDevice: Set<String> = []
    private(set) var started: [SongID] = []
    private(set) var cancelled: [SongID] = []

    init(root: @escaping () -> URL?) { self.root = root }

    func presence(of url: URL) -> SongPresence {
        guard isStrictlyInside(url, folder: root()) else { return .localOnly }
        return notOnDevice.contains(url.canonicalPath) ? .inCloudNotOnDevice : .inCloudOnDevice
    }
    func startDownload(of song: SongID) { started.append(song) }
    func cancelDownload(of song: SongID) { cancelled.append(song) }

    func progress(_ url: URL, percent: Double) { onEvent?(.progress(MacSongs.id(for: url), reportedPercent: percent)) }
    func finish(_ url: URL) { notOnDevice.remove(url.canonicalPath); onEvent?(.finished(MacSongs.id(for: url))) }
    func fail(_ url: URL) { onEvent?(.failed(MacSongs.id(for: url))) }
}
