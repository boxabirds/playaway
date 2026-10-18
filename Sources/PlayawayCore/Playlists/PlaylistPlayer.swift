import Foundation
import Combine

/// Playback of one playlist document: advances, shuffles, repeats, skips unreadable and missing tracks.
/// There is one per open playlist document; the shared `ActiveSessionRegistry` keeps only one active.
@MainActor
package final class PlaylistPlayer: SessionEnding {
    private enum Attempt { case started, refused, noOutputDevice }
    private enum Prepared: Equatable { case refused, ready(URL), awaitingDownload }

    private let playlistProvider: () -> Playlist
    /// Where the playlist's file is (nil before it has one), so a song another device stored can be found beside it.
    private let playlistFolder: () -> URL?
    private let settings: PlayModeSettings
    private let decider: AdvanceDeciding
    private let order: ShuffleOrdering
    private let resolver: TrackResolving
    private let gate: PlaybackGating
    private let classifier: FormatClassifying
    private let engine: PlaybackEngine
    private let marks: ReadabilityMarkStoring
    private let registry: ActiveSessionRegistry
    private weak var reporter: TrackResolutionReporting?
    /// Whether the file at a URL is on this device; an iCloud file may be only a placeholder. The adapter answers.
    package var isOnDevice: (URL) -> Bool = { _ in true }
    /// The last track any play attempt was made for (a double-click, a script, Next, play-through, a restore), whether
    /// or not it could start. A song that arrives from iCloud is played only while it is still this one: nothing else
    /// has been asked for since. The current song is not the measure: it also changes when a song ends or the
    /// playlist runs out, and that is not the person moving on.
    package private(set) var lastAsked: Track?
    /// A playable track whose file is not on this device: the adapter downloads it and plays it when it arrives
    /// (story 31's download-on-play, the same from every entry point). Until then nothing plays and nothing is marked.
    package var wantsDownload: ((Track, URL) -> Void)?

    private var sessionActive = false {
        didSet { if oldValue != sessionActive { changesSubject.send() } }
    }
    private var cancellables = Set<AnyCancellable>()
    package private(set) var current: Track? {
        didSet { if oldValue != current { changesSubject.send() } }
    }
    private let changesSubject = PassthroughSubject<Void, Never>()
    /// Fires whenever the current track, or whether this playlist has a session, changes.
    package var changes: AnyPublisher<Void, Never> { changesSubject.eraseToAnyPublisher() }
    private var pass: [Track] = []
    private var passIsShuffled = false
    /// The order the current track was started in, so the decider can carry on from where a removed track was.
    private var startedOrder: [Track] = []

    package init(playlist: @escaping () -> Playlist, playlistFolder: @escaping () -> URL? = { nil },
         settings: PlayModeSettings,
         decider: AdvanceDeciding = AdvanceDecider(), order: ShuffleOrdering = ShuffleOrder(),
         resolver: TrackResolving = TrackResolver(), gate: PlaybackGating = PlaybackGate(),
         classifier: FormatClassifying = FormatClassifier(), engine: PlaybackEngine,
         marks: ReadabilityMarkStoring, registry: ActiveSessionRegistry,
         reporter: TrackResolutionReporting? = nil) {
        self.playlistProvider = playlist
        self.playlistFolder = playlistFolder
        self.settings = settings
        self.decider = decider
        self.order = order
        self.resolver = resolver
        self.gate = gate
        self.classifier = classifier
        self.engine = engine
        self.marks = marks
        self.registry = registry
        self.reporter = reporter
    }

    package convenience init(playlist: Playlist, settings: PlayModeSettings, decider: AdvanceDeciding = AdvanceDecider(),
                     order: ShuffleOrdering = ShuffleOrder(), resolver: TrackResolving = TrackResolver(),
                     gate: PlaybackGating = PlaybackGate(), classifier: FormatClassifying = FormatClassifier(),
                     engine: PlaybackEngine, marks: ReadabilityMarkStoring, registry: ActiveSessionRegistry) {
        self.init(playlist: { playlist }, settings: settings, decider: decider, order: order, resolver: resolver,
                  gate: gate, classifier: classifier, engine: engine, marks: marks, registry: registry)
    }

    /// True while this playlist's session is active and something is playing or paused.
    package var isPlaying: Bool { sessionActive && engine.state != .idle }
    package var isSessionActive: Bool { sessionActive }

    /// The current track's 1-based place in the playlist as listed, and the playlist's length. Nil when there is
    /// no current track or it has since been removed.
    package var currentPosition: (place: Int, of: Int)? {
        guard let current else { return nil }
        let tracks = playlistProvider().tracks
        guard let index = tracks.firstIndex(where: { $0.id == current.id }) else { return nil }
        return (index + 1, tracks.count)
    }

    // MARK: Start

    /// Starts the playlist. A playlist with no tracks starts nothing and stops nothing.
    package func start() {
        guard !playlistProvider().tracks.isEmpty else { return }
        beginSession()
        current = nil
        pass = []
        startedOrder = []
        passIsShuffled = settings.shuffleOn
        playLoop(first: .start)
    }

    // MARK: Double-click on a track

    /// A playable track plays from 0:00 and becomes the current track. A missing or unreadable one is marked
    /// and leaves anything already playing, and any session, unchanged: the session only changes hands once
    /// the engine has actually started the file.
    package func play(track: Track) {
        guard playlistProvider().track(withID: track.id) != nil else { return }
        let prepared = prepare(track)
        guard case .ready(let url) = prepared else {
            if prepared == .refused { marks.markUnreadable(track) }
            return
        }
        switch engine.play(url) {
        case .playing:
            beginSession()
            current = track
            passIsShuffled = settings.shuffleOn
            pass = settings.shuffleOn ? order.pass(for: playlistProvider(), startingWith: track) : []
            noteStartedOrder()
        case .failed:
            marks.markUnreadable(track)
        case .noOutputDevice:
            break
        }
    }

    /// Loads a song paused at a remembered place and makes it the current song of this playlist, so the player shows it
    /// exactly as it shows any paused song and Play carries on from there. Nothing is heard. A song that cannot be loaded
    /// changes nothing.
    @discardableResult
    package func load(track: Track, atSeconds seconds: Double) -> Bool {
        guard playlistProvider().track(withID: track.id) != nil, case .ready(let url) = prepare(track) else { return false }
        guard engine.prepare(url, at: seconds) == .ready else { return false }
        beginSession()
        current = track
        passIsShuffled = settings.shuffleOn
        pass = settings.shuffleOn ? order.pass(for: playlistProvider(), startingWith: track) : []
        noteStartedOrder()
        return true
    }

    // MARK: Next and previous

    package func next() {
        guard sessionActive else { return }
        playLoop(first: .skipForward)
    }

    package func previous() {
        guard sessionActive else { return }
        playLoop(first: .skipBackward)
    }

    // MARK: Ending

    /// Detaches this session so it no longer advances. Does not stop audio: the caller is about to replace it.
    package func end() {
        guard sessionActive else { return }
        finishSession()
    }

    // MARK: Internals

    private func beginSession() {
        registry.begin(self)
        guard !sessionActive else { return }
        sessionActive = true
        engine.events.sink { [weak self] event in self?.handle(event) }.store(in: &cancellables)
        settings.didChange.sink { [weak self] in self?.modesChanged() }.store(in: &cancellables)
    }

    private func finishSession() {
        sessionActive = false
        cancellables.removeAll()
        current = nil
        pass = []
        startedOrder = []
        registry.didEnd(self)
    }

    private func handle(_ event: EngineEvent) {
        guard sessionActive else { return }
        switch event {
        case .finished: playLoop(first: .trackFinished)
        case .stopped: finishSession()
        case .stateChanged, .levelChanged: break
        }
    }

    /// Turning shuffle on keeps the current track and shuffles the tracks after it; turning it off carries on
    /// in listed order from the current track. Repeat changes apply to the next decision on their own.
    private func modesChanged() {
        guard sessionActive, let current, settings.shuffleOn != passIsShuffled else { return }
        passIsShuffled = settings.shuffleOn
        pass = settings.shuffleOn ? order.pass(for: playlistProvider(), startingWith: current) : []
        noteStartedOrder()
    }

    private func noteStartedOrder() {
        startedOrder = passIsShuffled ? pass : playlistProvider().tracks
    }

    private func context() -> AdvanceContext {
        AdvanceContext(playlist: playlistProvider(), current: current, repeatMode: settings.repeatMode,
                       shuffleOn: settings.shuffleOn, pass: pass, shuffler: order, startedOrder: startedOrder)
    }

    /// Asks the decider what is next and plays it, skipping tracks that cannot be played. Iterative, and bounded
    /// by the number of tracks so a playlist with nothing playable cannot loop forever.
    private func playLoop(first: PlaybackEvent) {
        var event = first
        let retryEvent: PlaybackEvent = first == .skipBackward ? .skipBackward : .skipForward
        let originalCurrent = current
        var refusals = 0
        while true {
            let advance = decider.advance(event: event, context: context())
            if let newPass = advance.newPass {
                pass = newPass
                passIsShuffled = settings.shuffleOn
            }
            switch advance.next {
            case .stay:
                current = originalCurrent
                return
            case .stop:
                engine.stop()
                finishSession()
                return
            case .play(let track):
                current = track
                noteStartedOrder()
                switch attempt(track) {
                case .started:
                    return
                case .noOutputDevice:
                    finishSession()
                    return
                case .refused:
                    refusals += 1
                    if refusals >= playlistProvider().tracks.count {
                        engine.stop()
                        finishSession()
                        return
                    }
                    event = retryEvent
                }
            }
        }
    }

    private func attempt(_ track: Track) -> Attempt {
        let prepared = prepare(track)
        guard case .ready(let url) = prepared else {
            if prepared == .refused { marks.markUnreadable(track) }
            return .refused                                    // a download in progress is skipped like a missing track
        }
        switch engine.play(url) {
        case .playing:
            return .started
        case .failed:
            marks.markUnreadable(track)
            return .refused
        case .noOutputDevice:
            return .noOutputDevice
        }
    }

    /// Resolve, gate, classify, in that order, so a blocked track never touches the engine.
    private func prepare(_ track: Track) -> Prepared {
        lastAsked = track
        let (status, reference) = resolver.resolve(track.reference, besidePlaylistAt: playlistFolder())
        reporter?.trackResolved(id: track.id, status: status, reference: reference)
        switch gate.decide(for: status) {
        case .refuse:
            return .refused
        case .play(let url):
            guard isOnDevice(url) else { wantsDownload?(track, url); return .awaitingDownload }
            if case .unsupported = classifier.classify(url) { return .refused }
            return .ready(url)
        }
    }
}
