import XCTest
@testable import PlayawayCore

final class ListeningMemoryTests: XCTestCase {
    private let song = UUID()
    private let other = UUID()
    private func point(_ name: String = "Road", _ id: UUID? = nil, _ at: Double = 42.5) -> ResumePoint {
        ResumePoint(playlistFileName: name, trackID: id ?? song, positionSeconds: at)
    }
    private func freshDefaults() -> UserDefaults {
        let suite = "ListeningMemoryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testStoreRoundTripsWhatWasSaved() {
        let store = ListeningMemoryStore(defaults: freshDefaults())
        let memory = ListeningMemory(openPlaylists: ["Road", "Gym"], nowPlaying: point())
        store.save(memory)
        XCTAssertEqual(store.load(), memory)
    }

    func testNothingStoredGivesEmptyMemory() {
        XCTAssertEqual(ListeningMemoryStore(defaults: freshDefaults()).load(), .empty)
    }

    func testUnreadableStoredDataGivesEmptyMemory() {
        let defaults = freshDefaults()
        defaults.set(Data("not json".utf8), forKey: listeningMemoryDefaultsKey)
        XCTAssertEqual(ListeningMemoryStore(defaults: defaults).load(), .empty)
        defaults.set("a string", forKey: listeningMemoryDefaultsKey)
        XCTAssertEqual(ListeningMemoryStore(defaults: defaults).load(), .empty)
    }

    func testEverythingStillThereIsKept() {
        let memory = ListeningMemory(openPlaylists: ["Road"], nowPlaying: point())
        let kept = memory.restoring(existingPlaylists: ["Road", "Gym"]) { _, _ in true }
        XCTAssertEqual(kept, memory)
    }

    func testDeletedOpenPlaylistIsDroppedAndOthersStay() {
        let memory = ListeningMemory(openPlaylists: ["Gone", "Road"], nowPlaying: nil)
        let kept = memory.restoring(existingPlaylists: ["Road"]) { _, _ in true }
        XCTAssertEqual(kept.openPlaylists, ["Road"])
    }

    func testSongInADeletedPlaylistIsForgotten() {
        let memory = ListeningMemory(openPlaylists: [], nowPlaying: point("Gone"))
        XCTAssertNil(memory.restoring(existingPlaylists: ["Road"]) { _, _ in true }.nowPlaying)
    }

    func testSongRemovedFromItsPlaylistIsForgotten() {
        let memory = ListeningMemory(openPlaylists: [], nowPlaying: point("Road", other))
        let kept = memory.restoring(existingPlaylists: ["Road"]) { _, id in id == self.song }
        XCTAssertNil(kept.nowPlaying)
    }

    func testBadPositionBecomesTheStartOfTheSong() {
        for bad in [-3.0, .nan, .infinity] {
            let memory = ListeningMemory(openPlaylists: [], nowPlaying: point("Road", nil, bad))
            XCTAssertEqual(memory.restoring(existingPlaylists: ["Road"]) { _, _ in true }.nowPlaying?.positionSeconds, 0)
        }
    }

    func testPositionWritesAreThrottled() {
        let start = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(shouldSavePosition(lastSaved: nil, now: start))
        XCTAssertFalse(shouldSavePosition(lastSaved: start, now: start.addingTimeInterval(listeningMemorySaveInterval - 0.1)))
        XCTAssertTrue(shouldSavePosition(lastSaved: start, now: start.addingTimeInterval(listeningMemorySaveInterval)))
    }
}
