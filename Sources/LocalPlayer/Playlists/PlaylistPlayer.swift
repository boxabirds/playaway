import Foundation
import Combine

/// Playback of one playlist document: advances, shuffles, repeats, skips unreadable and missing tracks.
/// There is one per open playlist document; the shared `ActiveSessionRegistry` keeps only one active.
final class PlaylistPlayer: SessionEnding {
    private enum Attempt { case started, refused, noOutputDevice }
    private enum Prepared { case refused, ready(URL) }

    private let playlistProvider: () -> Playlist
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

    private var sessionActive = false {
        didSet { if oldValue != sessionActive { changesSubject.send() } }
    }
    private var cancellables = Set<AnyCancellable>()
    private(set) var current: Track? {
        didSet { if oldValue != current { changesSubject.send() } }
    }
    private let changesSubject = PassthroughSubject<Void, Never>()
    /// Fires whenever the current track, or whether this playlist has a session, changes.
    var changes: AnyPublisher<Void, Never> { changesSubject.eraseToAnyPublisher() }
    private var pass: [Track] = []
    private var passIsShuffled = false
    /// The order the current track was started in, so the decider can carry on from where a removed track was.
    private var startedOrder: [Track] = []

    init(playlist: @escaping () -> Playlist, settings: PlayModeSettings,
         decider: AdvanceDeciding = AdvanceDecider(), order: ShuffleOrdering = ShuffleOrder(),
         resolver: TrackResolving = TrackResolver(), gate: PlaybackGating = PlaybackGate(),
         classifier: FormatClassifying = FormatClassifier(), engine: PlaybackEngine,
         marks: ReadabilityMarkStoring, registry: ActiveSessionRegistry,
         reporter: TrackResolutionReporting? = nil) {
        self.playlistProvider = playlist
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

    convenience init(playlist: Playlist, settings: PlayModeSettings, decider: AdvanceDeciding = AdvanceDecider(),
                     order: ShuffleOrdering = ShuffleOrder(), resolver: TrackResolving = TrackResolver(),
                     gate: PlaybackGating = PlaybackGate(), classifier: FormatClassifying = FormatClassifier(),
                     engine: PlaybackEngine, marks: ReadabilityMarkStoring, registry: ActiveSessionRegistry) {
        self.init(playlist: { playlist }, settings: settings, decider: decider, order: order, resolver: resolver,
                  gate: gate, classifier: classifier, engine: engine, marks: marks, registry: registry)
    }

    /// True while this playlist's session is active and something is playing or paused.
    var isPlaying: Bool { sessionActive && engine.state != .idle }
    var isSessionActive: Bool { sessionActive }

    /// The current track's 1-based place in the playlist as listed, and the playlist's length. Nil when there is
    /// no current track or it has since been removed.
    var currentPosition: (place: Int, of: Int)? {
        guard let current else { return nil }
        let tracks = playlistProvider().tracks
        guard let index = tracks.firstIndex(where: { $0.id == current.id }) else { return nil }
        return (index + 1, tracks.count)
    }

    // MARK: Start

    /// Starts the playlist. A playlist with no tracks starts nothing and stops nothing.
    func start() {
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
    func play(track: Track) {
        guard playlistProvider().track(withID: track.id) != nil else { return }
        guard case .ready(let url) = prepare(track) else {
            marks.markUnreadable(track)
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

    // MARK: Next and previous

    func next() {
        guard sessionActive else { return }
        playLoop(first: .skipForward)
    }

    func previous() {
        guard sessionActive else { return }
        playLoop(first: .skipBackward)
    }

    // MARK: Ending

    /// Detaches this session so it no longer advances. Does not stop audio: the caller is about to replace it.
    func end() {
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
        guard case .ready(let url) = prepare(track) else {
            marks.markUnreadable(track)
            return .refused
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
        let (status, reference) = resolver.resolve(track.reference)
        reporter?.trackResolved(id: track.id, status: status, reference: reference)
        switch gate.decide(for: status) {
        case .refuse:
            return .refused
        case .play(let url):
            if case .unsupported = classifier.classify(url) { return .refused }
            return .ready(url)
        }
    }
}
