import XCTest
@testable import LocalPlayer

final class PlayModeTests: XCTestCase {
    func testRepeatCycleThreeStates() {
        let settings = makeSettings()
        XCTAssertEqual(settings.repeatMode, .off)
        settings.cycleRepeat(); XCTAssertEqual(settings.repeatMode, .all)   // TC-30
        settings.cycleRepeat(); XCTAssertEqual(settings.repeatMode, .one)   // TC-31
        settings.cycleRepeat(); XCTAssertEqual(settings.repeatMode, .off)   // TC-32/33
    }

    func testShuffleToggles() {
        let settings = makeSettings()
        settings.toggleShuffle(); XCTAssertTrue(settings.shuffleOn)         // TC-34
        settings.toggleShuffle(); XCTAssertFalse(settings.shuffleOn)        // TC-35
    }

    func testControlsAreIndependent() {
        let settings = makeSettings(shuffle: true)
        settings.cycleRepeat()
        XCTAssertTrue(settings.shuffleOn, "TC-36/72")
        let other = makeSettings(repeatMode: .all)
        other.toggleShuffle()
        XCTAssertEqual(other.repeatMode, .all, "TC-37/73")
    }

    func testPersistenceMatrix() {
        let shuffles = [false, true]
        for shuffle in shuffles {
            for mode in RepeatMode.allCases {
                let defaults = isolatedDefaults()
                let first = PlayModeSettings(store: PlayModeStore(defaults: defaults))
                first.setShuffle(shuffle); first.setRepeat(mode)
                let relaunched = PlayModeSettings(store: PlayModeStore(defaults: defaults))
                XCTAssertEqual(relaunched.shuffleOn, shuffle, "TC-50..55")
                XCTAssertEqual(relaunched.repeatMode, mode)
            }
        }
    }

    func testFirstLaunchIsOffAndOff() {
        let settings = PlayModeSettings(store: PlayModeStore(defaults: isolatedDefaults()))   // TC-56
        XCTAssertFalse(settings.shuffleOn)
        XCTAssertEqual(settings.repeatMode, .off)
    }

    func testInvalidValuesFallBackIndividually() {
        var defaults = isolatedDefaults()
        defaults.set(true, forKey: shuffleSettingKey)
        defaults.set("sometimes", forKey: repeatSettingKey)
        var loaded = PlayModeStore(defaults: defaults).load()
        XCTAssertTrue(loaded.shuffle, "TC-57: good shuffle survives a bad repeat")
        XCTAssertEqual(loaded.repeatMode, .off)

        defaults = isolatedDefaults()
        defaults.set("yes please", forKey: shuffleSettingKey)
        defaults.set("one", forKey: repeatSettingKey)
        loaded = PlayModeStore(defaults: defaults).load()
        XCTAssertFalse(loaded.shuffle, "TC-58: wrong type")
        XCTAssertEqual(loaded.repeatMode, .one)
    }

    func testFailedSaveKeepsNewValueForThisLaunch() {
        final class FailingStore: PlayModeStoring {
            func load() -> (shuffle: Bool, repeatMode: RepeatMode) { (false, .off) }
            func saveShuffle(_ on: Bool) {}
            func saveRepeat(_ mode: RepeatMode) {}
        }
        let settings = PlayModeSettings(store: FailingStore())
        settings.toggleShuffle(); settings.cycleRepeat()
        XCTAssertTrue(settings.shuffleOn, "TC-59")
        XCTAssertEqual(settings.repeatMode, .all)
    }

    func testTwoWindowsShareOneState() {
        // TC-104: one shared settings object backs every window's controls.
        let settings = makeSettings()
        let windowA = settings, windowB = settings
        windowA.toggleShuffle()
        XCTAssertEqual(windowB.shuffleOn, true)
    }

    func testOnlyOwnKeysAreWritten() {
        let defaults = isolatedDefaults()
        let settings = PlayModeSettings(store: PlayModeStore(defaults: defaults))
        settings.toggleShuffle(); settings.cycleRepeat()
        let keys = Set(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("shuffle") || $0.hasPrefix("repeat") })
        XCTAssertEqual(keys, [shuffleSettingKey, repeatSettingKey])
    }
}
