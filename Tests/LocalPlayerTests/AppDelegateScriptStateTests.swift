import XCTest
import AppKit
@testable import LocalPlayer

/// The KVC state properties on the real AppDelegate (AppDelegate+Scripting.swift), built headlessly the way
/// DualPathTests builds its rig: a real AppDelegate instance given a real AppActions over a TestApp. The app is not
/// launched and NSApp.delegate is never touched. (task 9.5, TC-57, TC-58, TC-71)
@MainActor
final class AppDelegateScriptStateTests: XCTestCase {
    private static let readOnlyKeys = ["scriptIsPlaying", "scriptCurrentTrack", "scriptPosition"]
    private static let settableKeys = ["scriptVolume", "scriptMuted", "scriptShuffle", "scriptRepeat"]
    private static let unlistedKey = "scriptDeleteEverything"
    private static let playlistName = "Morning"
    private static let playedPosition = 2
    private static let playedFileName = "track2.mp3"
    private static let seekSeconds = 2.0
    private static let halfVolume = 50
    private static let overMaxVolume = scriptVolumeMax + 1
    private static let belowMinVolume = scriptVolumeMin - 1
    private static let positionTolerance = 0.5
    private static let invalidRepeat = "sideways"

    private struct Snapshot: Equatable {
        let playing: Bool, track: String, position: Double, volume: Int, muted: Bool, shuffle: Bool, repeatMode: String
    }

    private var app: TestApp!
    private var delegate: AppDelegate!
    private var actions: AppActions!
    private let dir = TempDir("delegatestate")
    private let fixture = PlaylistFixture(trackNames: ["track1.mp3", "track2.mp3", "track3.mp3"])

    override func setUp() async throws {
        try await super.setUp()
        app = TestApp()
        actions = AppActions(services: app.services)
        actions.isReady = { true }
        actions.defaultSaveDirectory = dir.url
        delegate = AppDelegate()
        delegate.actions = actions
        _ = app.openSaved(fixture.playlist, at: dir.path("\(Self.playlistName).lplaylist"))
    }

    override func tearDown() async throws {
        app.tearDown()
        try await super.tearDown()
    }

    private func snapshot() -> Snapshot {
        Snapshot(playing: delegate.scriptIsPlaying, track: delegate.scriptCurrentTrack, position: delegate.scriptPosition,
                 volume: delegate.scriptVolume, muted: delegate.scriptMuted, shuffle: delegate.scriptShuffle,
                 repeatMode: delegate.scriptRepeat)
    }

    // MARK: delegateHandlesKey

    func testDelegateHandlesEveryWhitelistedKey() {
        for key in Self.readOnlyKeys + Self.settableKeys {
            XCTAssertTrue(delegate.application(NSApplication.shared, delegateHandlesKey: key), key)
        }
        XCTAssertEqual(Set(Self.readOnlyKeys + Self.settableKeys), AppDelegate.scriptKVCKeys)
    }

    func testDelegateRefusesUnlistedKeys() {
        for key in [Self.unlistedKey, "services", "actions", "scriptTrackCount", "", "scriptvolume"] {
            XCTAssertFalse(delegate.application(NSApplication.shared, delegateHandlesKey: key), key)
        }
    }

    // MARK: Getters through the real code

    func testGettersReportPlayingState() throws {
        try actions.playTrack(Self.playedPosition, inPlaylist: Self.playlistName)
        XCTAssertTrue(delegate.scriptIsPlaying)
        XCTAssertEqual(delegate.scriptCurrentTrack, Self.playedFileName)
        XCTAssertEqual(delegate.scriptPosition, actions.position)
        XCTAssertEqual(delegate.value(forKey: "scriptIsPlaying") as? Bool, true)
        XCTAssertEqual(delegate.value(forKey: "scriptCurrentTrack") as? String, Self.playedFileName)
    }

    func testGettersReportPausedState() throws {
        try actions.playTrack(Self.playedPosition, inPlaylist: Self.playlistName)
        try actions.pause()
        XCTAssertFalse(delegate.scriptIsPlaying)
        XCTAssertEqual(delegate.scriptCurrentTrack, Self.playedFileName)
    }

    func testPositionFollowsSeek() throws {
        try actions.playTrack(Self.playedPosition, inPlaylist: Self.playlistName)
        try actions.seek(toSeconds: Self.seekSeconds)
        XCTAssertEqual(delegate.scriptPosition, actions.position)
        XCTAssertEqual(delegate.scriptPosition, Self.seekSeconds, accuracy: Self.positionTolerance)
    }

    func testVolumeMutedShuffleRepeatGettersMatchActions() throws {
        try actions.setVolume(percent: Self.halfVolume)
        try actions.setMuted(true)
        try actions.setShuffle(true)
        try actions.setRepeat(RepeatMode.all.rawValue)
        XCTAssertEqual(delegate.scriptVolume, Self.halfVolume)
        XCTAssertTrue(delegate.scriptMuted)
        XCTAssertTrue(delegate.scriptShuffle)
        XCTAssertEqual(delegate.scriptRepeat, RepeatMode.all.rawValue)
        XCTAssertEqual(delegate.value(forKey: "scriptVolume") as? Int, Self.halfVolume)
    }

    func testIdleStateWithAPlayerThatHasNotPlayed() {
        XCTAssertFalse(delegate.scriptIsPlaying)
        XCTAssertEqual(delegate.scriptCurrentTrack, "")
        XCTAssertEqual(delegate.scriptPosition, 0)
    }

    // MARK: Idle defaults when the app is not ready (actions nil)

    func testIdleDefaultsWhenActionsAreNil() {
        let idle = AppDelegate()
        XCTAssertNil(idle.actions)
        XCTAssertFalse(idle.scriptIsPlaying)
        XCTAssertEqual(idle.scriptCurrentTrack, "")
        XCTAssertEqual(idle.scriptPosition, 0)
        XCTAssertEqual(idle.scriptVolume, scriptVolumeMax)
        XCTAssertEqual(idle.scriptMuted, muteDefault)
        XCTAssertFalse(idle.scriptShuffle)
        XCTAssertEqual(idle.scriptRepeat, RepeatMode.off.rawValue)
    }

    func testSettingWithoutActionsDoesNothingAndDoesNotCrash() {
        let idle = AppDelegate()
        idle.scriptVolume = Self.halfVolume
        idle.scriptMuted = true
        idle.scriptShuffle = true
        idle.scriptRepeat = RepeatMode.one.rawValue
        XCTAssertEqual(idle.scriptVolume, scriptVolumeMax)
        XCTAssertFalse(idle.scriptMuted)
        XCTAssertFalse(idle.scriptShuffle)
        XCTAssertEqual(idle.scriptRepeat, RepeatMode.off.rawValue)
    }

    func testSettingWhileNotReadyIsRefusedAndChangesNothing() {
        actions.isReady = { false }
        let before = snapshot()
        delegate.scriptVolume = Self.halfVolume
        delegate.scriptMuted = true
        delegate.scriptShuffle = true
        delegate.scriptRepeat = RepeatMode.one.rawValue
        XCTAssertEqual(snapshot(), before)
    }

    // MARK: Settable properties change state through the same handlers

    func testSettablePropertiesChangeStateThroughTheHandlers() {
        delegate.scriptVolume = Self.halfVolume
        delegate.scriptMuted = true
        delegate.scriptShuffle = true
        delegate.scriptRepeat = RepeatMode.one.rawValue
        XCTAssertEqual(actions.volumePercent, Self.halfVolume)
        XCTAssertTrue(actions.isMuted)
        XCTAssertTrue(actions.shuffleOn)
        XCTAssertEqual(actions.repeatName, RepeatMode.one.rawValue)
        XCTAssertEqual(app.services.settings.repeatMode, .one)
        XCTAssertTrue(app.services.settings.shuffleOn)
    }

    func testSettingThroughKVCReachesTheSameHandlers() {
        delegate.setValue(Self.halfVolume, forKey: "scriptVolume")
        delegate.setValue(true, forKey: "scriptMuted")
        delegate.setValue(true, forKey: "scriptShuffle")
        delegate.setValue(RepeatMode.all.rawValue, forKey: "scriptRepeat")
        XCTAssertEqual(actions.volumePercent, Self.halfVolume)
        XCTAssertTrue(actions.isMuted)
        XCTAssertTrue(actions.shuffleOn)
        XCTAssertEqual(actions.repeatName, RepeatMode.all.rawValue)
    }

    func testSettersPersistThroughTheSameStoreAsTheScriptCommands() {
        delegate.scriptShuffle = true
        delegate.scriptRepeat = RepeatMode.all.rawValue
        let defaults = app.services.defaults
        XCTAssertEqual(defaults.object(forKey: shuffleSettingKey) as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: repeatSettingKey) as? String, RepeatMode.all.rawValue)
    }

    func testRefusedValuesLeaveStateUnchanged() {
        delegate.scriptVolume = Self.halfVolume
        let before = snapshot()
        delegate.scriptVolume = Self.overMaxVolume
        delegate.scriptVolume = Self.belowMinVolume
        delegate.scriptRepeat = Self.invalidRepeat
        XCTAssertEqual(snapshot(), before)
    }

    // MARK: Read-only properties are not settable

    func testReadOnlyPropertiesHaveNoSetter() {
        for key in Self.readOnlyKeys {
            let setter = NSSelectorFromString("set" + key.prefix(1).uppercased() + key.dropFirst() + ":")
            XCTAssertFalse(delegate.responds(to: setter), "\(key) must not be settable")
            XCTAssertTrue(delegate.responds(to: NSSelectorFromString(key)), "\(key) must be readable")
        }
    }

    func testSettablePropertiesHaveSetters() {
        for key in Self.settableKeys {
            let setter = NSSelectorFromString("set" + key.prefix(1).uppercased() + key.dropFirst() + ":")
            XCTAssertTrue(delegate.responds(to: setter), "\(key) must be settable")
        }
    }

    // MARK: Reading never changes state

    func testReadingIdleStateChangesNothing() {
        let before = snapshot()
        for _ in 0..<Self.readRepeats { _ = snapshot() }
        for key in AppDelegate.scriptKVCKeys { _ = delegate.value(forKey: key) }
        XCTAssertEqual(snapshot(), before)
    }

    func testReadingWhilePlayingChangesNothing() throws {
        try actions.playTrack(Self.playedPosition, inPlaylist: Self.playlistName)
        let startedBefore = app.backend.startedNames
        let before = snapshot()
        for key in AppDelegate.scriptKVCKeys { _ = delegate.value(forKey: key) }
        let after = snapshot()
        XCTAssertEqual(after.playing, before.playing)
        XCTAssertEqual(after.track, before.track)
        XCTAssertEqual(after.volume, before.volume)
        XCTAssertEqual(after.muted, before.muted)
        XCTAssertEqual(after.shuffle, before.shuffle)
        XCTAssertEqual(after.repeatMode, before.repeatMode)
        XCTAssertEqual(app.backend.startedNames, startedBefore)
    }

    private static let readRepeats = 3
}
