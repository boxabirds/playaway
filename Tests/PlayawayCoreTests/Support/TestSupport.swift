import Foundation
import XCTest
import Combine
@testable import PlayawayCore

// MARK: - Fixtures

enum Fixtures {
    static let directory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    static func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    static let trackNames = ["track1.mp3", "track2.mp3", "track3.mp3", "track4.mp3", "track5.mp3"]
}

/// A temporary directory removed when released, and in any case when the test process exits.
final class TempDir {
    let url: URL

    /// Every temp folder of this test run lives under one root that is removed at exit, because XCTest keeps test
    /// case instances (and so their folders) alive until the end of the run.
    static let root: URL = {
        let base = URL(fileURLWithPath: FileManager.default.temporaryDirectory.canonicalPath)
        let root = base.appendingPathComponent("lp-tests-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        atexit { try? FileManager.default.removeItem(at: TempDir.root) }
        return root
    }()

    init(_ label: String = "lp") {
        url = Self.root.appendingPathComponent("\(label)-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        try? FileManager.default.removeItem(at: url)
    }

    func path(_ name: String) -> URL { url.appendingPathComponent(name) }

    /// Copies a fixture in, under its own name or a new one.
    @discardableResult
    func copyFixture(_ name: String, as newName: String? = nil) -> URL {
        let destination = path(newName ?? name)
        try! FileManager.default.copyItem(at: Fixtures.url(name), to: destination)
        return destination
    }

    func makeSubfolder(_ name: String) -> URL {
        let folder = path(name)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

/// A real mp3 that audio tools cannot open. Name, extension and size are unchanged; it is not a zero-byte stub.
/// MP3 is a stream format that decoders resynchronise into, so zeroing only the header still plays: the whole
/// body is zeroed (found by experiment: AVAudioPlayer decoded a file with only its first 4 KB zeroed).
func makeUnreadableMP3(in dir: TempDir, name: String = "damaged.mp3") -> URL {
    let url = dir.copyFixture("track1.mp3", as: name)
    let size = try! Data(contentsOf: url).count
    try! Data(count: size).write(to: url)
    return url
}

func isolatedDefaults(_ label: String = "lp-test") -> UserDefaults {
    let name = "\(label)-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

func checksum(of url: URL) -> Int {
    let data = try! Data(contentsOf: url)
    return data.hashValue
}

struct FileSnapshot: Equatable {
    let size: Int
    let modified: Date
    let checksum: Int
    let path: String

    init(_ url: URL) {
        let attributes = try! FileManager.default.attributesOfItem(atPath: url.path)
        size = (attributes[.size] as! NSNumber).intValue
        modified = attributes[.modificationDate] as! Date
        checksum = PlayawayCoreTests.checksum(of: url)
        path = url.path
    }
}

// MARK: - Recording audio sink

/// Every fake sound producer (the fake song players and the fake scrub loop) reports to one of these. Two sounds at the
/// same time is a failure of whichever test it happens in, wherever in the code it happens.
final class SoundLedger {
    private(set) var sounding: [String] = []
    private(set) var overlaps: [String] = []

    func began(_ sound: String) {
        sounding.append(sound)
        if sounding.count > 1 {
            let overlap = sounding.joined(separator: " + ")
            overlaps.append(overlap)
            XCTFail("two sounds at once: \(overlap)")
        }
    }

    func ended(_ sound: String) { sounding.removeAll { $0 == sound } }
}

final class RecordingPlayerHandle: AudioPlayerHandle {
    let url: URL
    var duration: TimeInterval
    var currentTime: TimeInterval = 0
    var gain: Float = 1
    var onFinish: (() -> Void)?
    private(set) var running = false
    private weak var backend: RecordingAudioBackend?
    private var soundName: String { "song:\(url.lastPathComponent)" }

    init(url: URL, duration: TimeInterval, backend: RecordingAudioBackend) {
        self.url = url
        self.duration = duration
        self.backend = backend
    }

    func start() -> Bool {
        if backend?.failStart == true { return false }
        running = true
        backend?.log.append("start:\(url.lastPathComponent)@\(currentTime)")
        backend?.ledger.began(soundName)
        return true
    }

    func pause() {
        running = false
        backend?.log.append("pause:\(url.lastPathComponent)@\(currentTime)")
        backend?.ledger.ended(soundName)
    }

    func stop() {
        running = false
        currentTime = 0
        backend?.log.append("stop:\(url.lastPathComponent)")
        backend?.ledger.ended(soundName)
    }

    /// Simulates the file playing to its end.
    func finish() {
        running = false
        backend?.ledger.ended(soundName)
        onFinish?()
    }
}

/// The scrub loop as a test double. It shares the backend's ledger, so a loop sounding under a song is caught.
final class FakeLoopingPreview: LoopingPreviewing {
    private(set) var isPlaying = false
    private(set) var starts: [(url: URL, seconds: Double, length: Double)] = []
    private(set) var stops = 0
    /// What was asked to be got ready, and how many scrubs were ended.
    private(set) var prepares: [(url: URL, seconds: Double, length: Double)] = []
    private(set) var sessionsEnded = 0
    var canStart = true
    /// Where the loop is when it is stopped; the start of the snippet when not set.
    var placeWhenStopped: Double?
    private let ledger: SoundLedger?
    private static let soundName = "loop"

    init(ledger: SoundLedger? = nil) { self.ledger = ledger }

    func prepare(url: URL, at seconds: Double, length: Double) { prepares.append((url, seconds, length)) }
    func endSession() { sessionsEnded += 1 }

    func start(url: URL, at seconds: Double, length: Double) -> Bool {
        guard canStart else { return false }
        starts.append((url, seconds, length)); isPlaying = true
        ledger?.began(Self.soundName)
        return true
    }

    @discardableResult func stop() -> Double? {
        guard isPlaying else { return nil }
        isPlaying = false; stops += 1
        ledger?.ended(Self.soundName)
        return placeWhenStopped ?? starts.last?.seconds
    }
}

final class RecordingAudioBackend: AudioBackend {
    var log: [String] = []
    var players: [RecordingPlayerHandle] = []
    var unreadableNames: Set<String> = []
    var failStart = false
    var defaultDuration: TimeInterval = 4
    let ledger = SoundLedger()
    /// The scrub loop of the same fake audio output, so the ledger sees both.
    private(set) lazy var preview = FakeLoopingPreview(ledger: ledger)

    func makePlayer(for url: URL) throws -> AudioPlayerHandle {
        if unreadableNames.contains(url.lastPathComponent) {
            throw NSError(domain: "RecordingAudioBackend", code: 1, userInfo: [NSLocalizedDescriptionKey: "unreadable"])
        }
        let handle = RecordingPlayerHandle(url: url, duration: defaultDuration, backend: self)
        players.append(handle)
        return handle
    }

    var playing: RecordingPlayerHandle? { players.last { $0.running } }
    var latest: RecordingPlayerHandle? { players.last }
    var startedNames: [String] { log.compactMap { $0.hasPrefix("start:") ? String($0.dropFirst(6).split(separator: "@")[0]) : nil } }
}

struct StubOutputDevices: OutputDeviceProviding {
    var hasOutputDevice: Bool
}

final class InMemoryVolumeStore: VolumeSettingsStoring {
    var volume: Double
    var muted: Bool
    var savedVolumes: [Double] = []
    var savedMutes: [Bool] = []

    init(volume: Double = volumeDefault, muted: Bool = muteDefault) {
        self.volume = volume
        self.muted = muted
    }

    func load() -> (volume: Double, isMuted: Bool) { (volume, muted) }
    func saveVolume(_ volume: Double) { self.volume = volume; savedVolumes.append(volume) }
    func saveMuted(_ muted: Bool) { self.muted = muted; savedMutes.append(muted) }
}

func makeEngine(backend: RecordingAudioBackend = RecordingAudioBackend(), hasDevice: Bool = true,
                store: VolumeSettingsStoring = InMemoryVolumeStore()) -> AVPlaybackEngine {
    AVPlaybackEngine(backend: backend, devices: StubOutputDevices(hasOutputDevice: hasDevice), settings: store,
                     preview: backend.preview)
}

final class RecordingNotices: NoticePresenting {
    var shown: [Notice] = []
    func show(_ notice: Notice) { shown.append(notice) }
}

final class RecordingPlaylistOpener: PlaylistOpening {
    var log: [String] = []
    var openable: (URL) -> Bool = { $0.pathExtension == playlistFileExtension }
    func canOpen(_ url: URL) -> Bool { openable(url) }
    func open(_ url: URL) { log.append("open:\(url.lastPathComponent)") }
    func endActivePlayback() { log.append("end") }
}

// MARK: - Playlist fixtures

/// Real audio files copied into a temp folder, referenced by real bookmarks.
final class PlaylistFixture {
    let dir: TempDir
    var urls: [URL] = []
    var tracks: [Track] = []

    init(trackNames: [String] = Fixtures.trackNames, dir: TempDir = TempDir("playlist")) {
        self.dir = dir
        for name in trackNames {
            let url = dir.copyFixture(name)
            urls.append(url)
            tracks.append(Track(id: UUID(), reference: TrackReference.make(for: url)!))
        }
    }

    var playlist: Playlist { Playlist(tracks: tracks) }
    func deleteFile(at index: Int) { try! FileManager.default.removeItem(at: urls[index]) }
}

/// Tracks that carry no real file, for decider-level tests.
func bareTracks(_ count: Int) -> [Track] {
    (0..<count).map { index in
        Track(id: UUID(), reference: TrackReference(bookmark: Data(), lastKnownPath: "/nowhere/\(index + 1).mp3",
                                                    fileName: "\(index + 1).mp3"))
    }
}

func seededShuffler(_ seed: UInt64 = 7) -> ShuffleOrder {
    ShuffleOrder(makeGenerator: { SeededGenerator(seed: seed) })
}

func makeSettings(shuffle: Bool = false, repeatMode: RepeatMode = .off,
                  defaults: UserDefaults = isolatedDefaults()) -> PlayModeSettings {
    let store = PlayModeStore(defaults: defaults)
    store.saveShuffle(shuffle)
    store.saveRepeat(repeatMode)
    return PlayModeSettings(store: store)
}

/// Everything a PlaylistPlayer needs, wired with a recording sink.
@MainActor
final class PlayerRig {
    let fixture: PlaylistFixture
    let backend = RecordingAudioBackend()
    let engine: AVPlaybackEngine
    let settings: PlayModeSettings
    let marks = ReadabilityMarkStore()
    let registry = ActiveSessionRegistry()
    let statuses = TrackStatusStore()
    var player: PlaylistPlayer!
    var playlist: Playlist

    init(fixture: PlaylistFixture = PlaylistFixture(), shuffle: Bool = false, repeatMode: RepeatMode = .off,
         seed: UInt64 = 7, hasDevice: Bool = true) {
        self.fixture = fixture
        self.playlist = fixture.playlist
        engine = makeEngine(backend: backend, hasDevice: hasDevice)
        settings = makeSettings(shuffle: shuffle, repeatMode: repeatMode)
        player = makePlayer(seed: seed)
    }

    func makePlayer(seed: UInt64 = 7, registry: ActiveSessionRegistry? = nil) -> PlaylistPlayer {
        PlaylistPlayer(playlist: { [unowned self] in self.playlist }, settings: settings,
                       order: seededShuffler(seed), engine: engine, marks: marks, registry: registry ?? self.registry)
    }

    var startedNames: [String] { backend.startedNames }
    var currentName: String? { engine.currentURL?.lastPathComponent }
    func finishCurrent() { backend.playing?.finish() }
}
