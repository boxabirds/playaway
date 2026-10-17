import PlayawayCore
import Foundation
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
         conflictVersions: ConflictVersionReading = MacConflictVersions()) {
        self.defaults = defaults
        self.engine = engine ?? AVPlaybackEngine(settings: VolumeSettingsStore(defaults: defaults))
        self.settings = PlayModeSettings(store: PlayModeStore(defaults: defaults))
        self.notices = notices
        self.classifier = classifier
        let cloud = CloudFolderLocator(find: cloudRoot)
        self.cloud = cloud
        self.conflictVersions = conflictVersions
        self.resolver = resolver ?? TrackResolver(cloudDocuments: cloud.root)
        self.gate = gate
        self.store = store
        self.shuffleOrder = shuffleOrder
        transport = TransportViewModel(engine: self.engine, registry: registry, runsTimer: runsTimer)
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
        transport.startHandler = { [weak self] in self?.startFromIdle() ?? false }
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
