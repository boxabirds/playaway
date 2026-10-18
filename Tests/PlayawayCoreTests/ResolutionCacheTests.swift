import XCTest
@testable import PlayawayCore

/// Audit I4/F4: the iPhone looked for every missing song on every redraw. Each way an answer is remembered, expires or is
/// dropped is pinned here, because this is the code that decides whether a row shows a stale answer.
final class ResolutionCacheTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_000_000)
    private let song = UUID(), other = UUID()
    private let place = URL(fileURLWithPath: "/music/a.mp3")

    private func makeCache(lifetime: TimeInterval = 2) -> ResolutionCache {
        ResolutionCache(unfoundLifetime: lifetime, clock: { [unowned self] in self.now })
    }

    func testNothingIsKnownAboutASongNeverLookedFor() {
        XCTAssertEqual(makeCache().lookup(song), .unknown)
    }

    func testAFoundSongStaysFoundHoweverMuchTimePasses() {
        let cache = makeCache()
        cache.store(song, url: place)
        now.addTimeInterval(3600)
        XCTAssertEqual(cache.lookup(song), .found(place))
    }

    func testANotFoundAnswerIsKeptWithinItsLifetimeSoARedrawDoesNotSearchAgain() {
        let cache = makeCache(lifetime: 2)
        cache.store(song, url: nil)
        XCTAssertEqual(cache.lookup(song), .unfound)
        now.addTimeInterval(1.9)
        XCTAssertEqual(cache.lookup(song), .unfound)
    }

    func testANotFoundAnswerExpiresSoAFileThatArrivedIsNoticed() {
        let cache = makeCache(lifetime: 2)
        cache.store(song, url: nil)
        now.addTimeInterval(2)
        XCTAssertEqual(cache.lookup(song), .unknown, "at the lifetime the answer is no longer trusted")
        cache.store(song, url: place)
        XCTAssertEqual(cache.lookup(song), .found(place))
    }

    func testFindingASongReplacesAnEarlierNotFoundAndTheOtherWayRound() {
        let cache = makeCache()
        cache.store(song, url: nil)
        cache.store(song, url: place)
        XCTAssertEqual(cache.lookup(song), .found(place))
        cache.store(song, url: nil)
        XCTAssertEqual(cache.lookup(song), .unfound, "a found song that is searched for again and not found is not found")
    }

    func testAnswersBelongToTheirOwnSong() {
        let cache = makeCache()
        cache.store(song, url: place)
        cache.store(other, url: nil)
        XCTAssertEqual(cache.lookup(song), .found(place))
        XCTAssertEqual(cache.lookup(other), .unfound)
        XCTAssertEqual(cache.lookup(UUID()), .unknown)
    }

    func testRemoveAllForgetsFoundAndNotFoundAlike() {
        let cache = makeCache()
        cache.store(song, url: place)
        cache.store(other, url: nil)
        cache.removeAll()
        XCTAssertEqual(cache.lookup(song), .unknown)
        XCTAssertEqual(cache.lookup(other), .unknown)
    }
}
