import PlayawayCore
import AppKit

/// A silent audio output used only by the element dump, so reaching the "playing" state makes no sound.
struct SilentAudioBackend: AudioBackend {
    private final class Handle: AudioPlayerHandle {
        var duration: TimeInterval = 180
        var currentTime: TimeInterval = 0
        var gain: Float = 0
        var onFinish: (() -> Void)?
        func start() -> Bool { true }
        func pause() {}
        func stop() {}
    }
    func makePlayer(for url: URL) throws -> AudioPlayerHandle { Handle() }
}

/// `--dump-window-elements <window-kind> <state>`: opens a fixture playlist document, reaches the state through
/// in-memory seams, prints the visible elements as JSON and exits. Nothing is written to Documents or any user folder.
@MainActor
final class UICheckMode {
    private let services: AppServices
    private let workDir: URL
    private let fixtureAudio: [URL]
    /// Test-only: a view added to the window before it is walked, to prove an unrecorded element is caught.
    var injectedView: NSView?

    init(fixtureAudio: [URL]) throws {
        workDir = FileManager.default.temporaryDirectory.appendingPathComponent("lp-uicheck-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        self.fixtureAudio = fixtureAudio
        let suite = "lp-uicheck-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let engine = AVPlaybackEngine(backend: SilentAudioBackend(), settings: VolumeSettingsStore(defaults: defaults))
        services = AppServices(defaults: defaults, engine: engine, notices: NoticePresenter(), runsTimer: false)
    }

    deinit { try? FileManager.default.removeItem(at: workDir) }

    func dump(kind: String, state stateName: String) throws -> [ObservedElement] {
        guard WindowKind(rawValue: kind) != nil else { throw ManifestError.unknownWindowKind(kind) }
        guard let state = WindowState(rawValue: stateName) else { throw EnumerationError.stateUnavailable(stateName) }
        return try visibleElements(in: state)
    }

    func visibleElements(in state: WindowState) throws -> [ObservedElement] {
        AppServices.shared = services
        services.connect(controller: PlaylistDocumentController.current)
        let document = try makeDocument(for: state)
        defer {
            (services.notices as? NoticePresenter)?.dismissCurrent()
            document.close()
        }
        guard let controller = document.windowControllers.first as? PlaylistWindowController, let window = controller.window else {
            throw EnumerationError.stateUnavailable(state.rawValue)
        }
        window.orderFront(nil)
        try arrange(state, document: document, controller: controller)
        return WindowElementWalker.elements(in: window)
    }

    private func makeDocument(for state: WindowState) throws -> PlaylistDocument {
        let controller = PlaylistDocumentController.current
        if state == .untitledEmpty {
            return try controller.openUntitledDocumentAndDisplay(true) as! PlaylistDocument
        }
        let url = workDir.appendingPathComponent("Fixture.\(playlistFileExtension)")
        let tracks = fixtureAudio.compactMap { TrackReference.make(for: $0) }.map { Track(id: UUID(), reference: $0) }
        guard PlaylistStore().save(Playlist(tracks: tracks), to: url) == .saved else {
            throw EnumerationError.stateUnavailable(state.rawValue)
        }
        var opened: NSDocument?
        var finished = false
        controller.openDocument(withContentsOf: url, display: true) { document, _, _ in opened = document; finished = true }
        let deadline = Date().addingTimeInterval(5)
        while !finished && Date() < deadline { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
        guard let document = opened as? PlaylistDocument else { throw EnumerationError.stateUnavailable(state.rawValue) }
        return document
    }

    private func arrange(_ state: WindowState, document: PlaylistDocument, controller: PlaylistWindowController) throws {
        switch state {
        case .idle, .untitledEmpty:
            break
        case .playing:
            document.player.start()
            guard document.player.isPlaying else { throw EnumerationError.stateUnavailable(state.rawValue) }
            services.transport.refresh()
        case .editingPlaylist:
            controller.tableView.selectRowIndexes([0], byExtendingSelection: false)
        case .noticeShown:
            services.notices.show(.unsupported(.unknownType("FLAC audio")))
        }
        if let injectedView, let root = controller.window?.contentView as? NSStackView { root.addArrangedSubview(injectedView) }
        controller.transport.render()
        controller.reload()
    }

    static func jsonString(_ elements: [ObservedElement]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? String(data: encoder.encode(elements), encoding: .utf8)) ?? "[]"
    }
}
