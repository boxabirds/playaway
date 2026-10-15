import XCTest
@testable import PlayawayCore

final class LaunchTimingTests: XCTestCase {
    private let boot = Date(timeIntervalSince1970: 1_000)
    private func freshDefaults() -> UserDefaults {
        let suite = "LaunchTimingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testFirstEverLaunchIsCold() { XCTAssertEqual(launchKind(previousLaunch: nil, deviceBoot: boot), .cold) }
    func testLaunchBeforeTheLastBootIsCold() {
        XCTAssertEqual(launchKind(previousLaunch: boot.addingTimeInterval(-5), deviceBoot: boot), .cold)
    }
    func testLaunchAfterTheLastBootIsWarm() {
        XCTAssertEqual(launchKind(previousLaunch: boot.addingTimeInterval(5), deviceBoot: boot), .warm)
    }

    func testTimerReportsTheTimeToTheFirstScreen() {
        let start = Date(timeIntervalSince1970: 2_000)
        let report = LaunchTimer(processStart: start, kind: .warm).firstScreenShown(at: start.addingTimeInterval(0.42))
        XCTAssertEqual(report.kind, .warm)
        XCTAssertEqual(report.seconds, 0.42, accuracy: 0.0001)
    }

    func testAClockGoingBackwardsReportsZeroNotANegativeTime() {
        let start = Date(timeIntervalSince1970: 2_000)
        XCTAssertEqual(LaunchTimer(processStart: start, kind: .cold).firstScreenShown(at: start.addingTimeInterval(-3)).seconds, 0)
    }

    func testColdAndWarmAreAveragedSeparately() {
        let store = LaunchReportStore(defaults: freshDefaults())
        XCTAssertNil(store.average(.cold))
        store.add(LaunchReport(kind: .cold, seconds: 2))
        store.add(LaunchReport(kind: .cold, seconds: 4))
        store.add(LaunchReport(kind: .warm, seconds: 0.5))
        XCTAssertEqual(store.average(.cold), 3)
        XCTAssertEqual(store.average(.warm), 0.5)
    }

    func testOnlyTheMostRecentReportsAreKept() {
        let store = LaunchReportStore(defaults: freshDefaults())
        for index in 0..<(launchReportsKept + 5) { store.add(LaunchReport(kind: .warm, seconds: Double(index))) }
        XCTAssertEqual(store.reports().count, launchReportsKept)
        XCTAssertEqual(store.reports().first?.seconds, 5)
    }

    func testLastLaunchRoundTrips() {
        let store = LaunchReportStore(defaults: freshDefaults())
        XCTAssertNil(store.lastLaunch)
        store.noteLaunch(at: boot)
        XCTAssertEqual(store.lastLaunch, boot)
    }

    func testTheSystemFactsAreReadable() {
        XCTAssertNotNil(LaunchFacts.processStart())
        XCTAssertNotNil(LaunchFacts.deviceBoot())
        XCTAssertLessThan(LaunchFacts.deviceBoot()!, LaunchFacts.processStart()!)
    }
}
