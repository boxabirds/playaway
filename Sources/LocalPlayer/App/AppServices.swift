import PlayawayCore
import Foundation
import Combine
import AppKit

/// The objects every window shares: one engine, one active-session registry, one set of settings.
/// Built at launch; tests build their own with a recording sink and isolated defaults.
final class AppServices {
    static var shared: AppServices!

    let defaults: UserDefaults
    let engine: PlaybackEngine
    let settings: PlayModeSettings
    let marks = ReadabilityMarkStore()
    let registry = ActiveSessionRegistry()
    let notices: NoticePresenting
    let classifier: FormatClassifying
    let resolver: TrackResolving
    let gate: PlaybackGating
    let store: PlaylistStoring
    let transport: TransportViewModel
    /// The Playaway folder in iCloud Drive on this Mac, when there is one.
    let cloud: CloudFolderLocator
    /// iCloud's conflict versions of a playlist file (story 39).
    let conflictVersions: ConflictVersionReading
    /// Where a song file is (local, in iCloud, not downloaded) and the downloads the coordinator asks for (story 20).
    let cloudSongs: CloudSongsProviding
    /// The shared download-on-play rules (story 31), one for the app; the Mac side plays through `starter`.
    let starter = MacPlaybackStarter()
    private(set) lazy var downloads = DownloadOnPlayCoordinator(downloader: cloudSongs, player: starter)
    /// Fires after every download event, so rows redraw their cloud icons.
    let downloadChanges = PassthroughSubject<Void, Never>()
    private(set) var openCoordinator: OpenCoordinator!
    private(set) var playlistRouter: PlaylistOpenRouter!
    private(set) var lastSingleFile: URL?

    init(defaults: UserDefaults = .standard,
         engine: PlaybackEngine? = nil,
         notices: NoticePresenting = NoticePresenter(),
         classifier: FormatClassifying = FormatClassifier(),
         resolver: TrackResolving? = nil,
         gate: PlaybackGating = PlaybackGate(),
         store: PlaylistStoring = PlaylistStore(),
         shuffleOrder: ShuffleOrdering = ShuffleOrder(),
         runsTimer: Bool = true,
         cloudRoot: @escaping () -> URL? = { CloudFolder.documentsOnThisDevice() },
         driveRoot: @escaping () -> URL? = { CloudFolder.driveRootOnThisDevice() },
         conflictVersions: ConflictVersionReading = MacConflictVersions(),
         cloudSongs: CloudSongsProviding? = nil) {
        self.defaults = defaults
        self.engine = engine ?? AVPlaybackEngine(settings: VolumeSettingsStore(defaults: defaults))
        self.settings = PlayModeSettings(store: PlayModeStore(defaults: defaults))
        self.notices = notices
        self.classifier = classifier
        let cloud = CloudFolderLocator(find: cloudRoot)
        self.cloud = cloud
        self.conflictVersions = conflictVersions
        self.cloudSongs = cloudSongs ?? MacCloudSongs()
        // The Mac reads both iCloud roots directly (story 40): the Playaway folder and iCloud Drive itself.
        self.resolver = resolver ?? TrackResolver(roots: DirectCloudRoots(playawayDocuments: cloud.root, driveRoot: driveRoot()))
        self.gate = gate
        self.store = store
        self.shuffleOrder = shuffleOrder
        transport = TransportViewModel(engine: self.engine, registry: registry, runsTimer: runsTimer)
        self.cloudSongs.onEvent = { [weak self] event in
            guard let self else { return }
            downloads.handle(event)
            downloadChanges.send()
        }
    }

    // MARK: Download on play (stories 20 and 31)

    /// A playable track whose file is not on this Mac: download it and play it when it arrives, if the person has
    /// not moved on by then.
    func requestDownload(of track: Track, at url: URL, in document: PlaylistDocument) {
        let song = MacSongs.id(for: url)
        DebugTrace.log("requestDownload \(url.lastPathComponent) state=\(downloads.state(of: song))")
        starter.pending[song] = MacPlaybackStarter.Pending(document: document, track: track)
        downloads.request(song, source: .list, isOnDevice: false)
        downloadChanges.send()
    }

    func cancelDownload(of song: SongID) {
        downloads.cancel(song)
        starter.pending[song] = nil
        downloadChanges.send()
    }

    func retryDownload(of track: Track, at url: URL, in document: PlaylistDocument) {
        let song = MacSongs.id(for: url)
        starter.pending[song] = MacPlaybackStarter.Pending(document: document, track: track)
        downloads.retry(song)
        downloadChanges.send()
    }

    let shuffleOrder: ShuffleOrdering

    /// Wires the pieces that need each other. Called once after init.
    func connect(controller: PlaylistDocumentController) {
        playlistRouter = PlaylistOpenRouter(controller: controller, registry: registry)
        openCoordinator = OpenCoordinator(classifier: classifier, engine: engine, notices: notices, playlists: playlistRouter)
        openCoordinator.onPlayResult = { [weak self] url, result in
            if result == .playing { self?.lastSingleFile = url }
        }
        transport.activePlayerProvider = { [weak self] in
            self?.registry.active as? PlaylistPlayer
        }
        transport.startHandler = { [weak self] in
            guard let self else { return false }
            if downloads.transportPlay() == .ignored { return true }     // Play waits while a song downloads (story 31)
            return startFromIdle()
        }
    }

    /// Play pressed with nothing loaded.
    private func startFromIdle() -> Bool {
        if let document = PlaylistDocumentController.current.frontPlaylistDocument(), !document.playlist.tracks.isEmpty {
            document.player.start()
            return document.player.isSessionActive
        }
        if let url = lastSingleFile {
            return openCoordinator.open(url) == .played(.playing)
        }
        return false
    }
}
