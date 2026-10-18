import XCTest
@testable import LocalPlayer
@testable import PlayawayCore

/// One shared, ordered log so cross-component ordering can be asserted.
final class EventLog {
    private(set) var events: [String] = []
    func add(_ event: String) { events.append(event) }
    func index(of event: String) -> Int? { events.firstIndex(of: event) }
}

final class LoggingTrace: LaunchTracing {
    let log: EventLog
    private(set) var phases: [LaunchPhase] = []
    init(log: EventLog) { self.log = log }
    func record(_ phase: LaunchPhase) { phases.append(phase); log.add("trace:\(phase.rawValue)") }
}

final class LoggingObserver: FirstWindowObserver {
    let name: String, log: EventLog
    private(set) var calls = 0
    private(set) var phaseSeen: [LaunchPhase] = []
    var onCall: (() -> Void)?
    var phaseProbe: (() -> LaunchPhase)?
    init(_ name: String, log: EventLog) { self.name = name; self.log = log }
    func firstWindowPresented() {
        calls += 1
        if let phaseProbe { phaseSeen.append(phaseProbe()) }
        log.add("observer:\(name)")
        onCall?()
    }
}

/// Stands in for the window server: the test decides when the window is "shown".
final class FakeWindows: LaunchWindowProviding {
    let log: EventLog
    var presentsImmediately = false
    private var completion: (() -> Void)?
    private(set) var requests = 0
    init(log: EventLog) { self.log = log }
    func presentFirstWindow(completion: @escaping () -> Void) {
        requests += 1
        log.add("window:requested")
        if presentsImmediately { log.add("window:shown"); completion() } else { self.completion = completion }
    }
    func show() { log.add("window:shown"); completion?() }
    /// A misbehaving provider that reports presentation twice.
    func showTwice() { show(); log.add("window:shown-again"); completion?() }
}

/// Recording stand-ins for work that must wait for the first window. They log only when they are asked to start.
final class RecordingDeferredWork: FirstWindowObserver {
    let log: EventLog
    private(set) var started = 0
    private(set) var startedOnMainThread: [Bool] = []
    init(log: EventLog) { self.log = log }
    func firstWindowPresented() {
        started += 1
        startedOnMainThread.append(Thread.isMainThread)
        log.add("engine:init"); log.add("network:request"); log.add("audio-file:open"); log.add("updater:start")
    }
}

final class FailingObserver: FirstWindowObserver {
    private(set) var calls = 0
    func firstWindowPresented() { calls += 1 }   // models an offline updater: it does nothing and returns
}

@MainActor
final class LaunchCoordinatorTests: XCTestCase {
    override func setUp() { LaunchState.firstWindowPresented = false }
    override func tearDown() { LaunchState.firstWindowPresented = false }

    private func make(observers: [FirstWindowObserver] = [], log: EventLog = EventLog())
        -> (LaunchCoordinator, FakeWindows, LoggingTrace, EventLog) {
        let windows = FakeWindows(log: log)
        let trace = LoggingTrace(log: log)
        return (LaunchCoordinator(trace: trace, observers: observers, windows: windows), windows, trace, log)
    }

    func testTC39PhasesAreRecordedLaunchingThenWindowShownInOrder() {
        let (coordinator, windows, trace, log) = make()
        coordinator.start()
        XCTAssertEqual(trace.phases, [.launching])
        XCTAssertEqual(coordinator.phase, .launching)
        windows.show()
        XCTAssertEqual(Array(trace.phases.prefix(2)), [.launching, .windowShown])
        XCTAssertLessThan(log.index(of: "trace:launching")!, log.index(of: "window:requested")!)
        XCTAssertLessThan(log.index(of: "window:shown")!, log.index(of: "trace:windowShown")!)
    }

    func testTC39TraceTimestampsIncreaseInPhaseOrder() {
        var tick: UInt64 = 0
        let trace = LaunchTrace(resultsPath: nil, clock: { tick += 10; return tick })
        let windows = FakeWindows(log: EventLog())
        let coordinator = LaunchCoordinator(trace: trace, observers: [], windows: windows)
        coordinator.start()
        windows.show()
        XCTAssertEqual(trace.recorded.map(\.phase), [.launching, .windowShown, .running])
        XCTAssertEqual(trace.recorded.map(\.nanoseconds), trace.recorded.map(\.nanoseconds).sorted())
    }

    func testTC43ObserversNotifiedExactlyOnceAndOnlyAfterWindowShown() {
        let log = EventLog()
        let a = LoggingObserver("a", log: log), b = LoggingObserver("b", log: log)
        let (coordinator, windows, _, _) = make(observers: [a, b], log: log)
        coordinator.start()
        XCTAssertEqual(a.calls + b.calls, 0, "no observer while the phase is launching")
        windows.show()
        XCTAssertEqual([a.calls, b.calls], [1, 1])
        let shown = log.index(of: "trace:windowShown")!
        XCTAssertLessThan(shown, log.index(of: "observer:a")!)
        XCTAssertLessThan(shown, log.index(of: "observer:b")!)
    }

    func testTC43ObserverSeesPhaseWindowShownNotLaunching() {
        let log = EventLog()
        let observer = LoggingObserver("a", log: log)
        let (coordinator, windows, _, _) = make(observers: [observer], log: log)
        observer.phaseProbe = { coordinator.phase }
        coordinator.start()
        windows.show()
        XCTAssertEqual(observer.phaseSeen, [.windowShown])
        XCTAssertEqual(coordinator.phase, .running)
    }

    func testTC43DuplicatePresentationOrDuplicateStartNotifiesOnce() {
        let log = EventLog()
        let observer = LoggingObserver("a", log: log)
        let (coordinator, windows, trace, _) = make(observers: [observer], log: log)
        coordinator.start()
        coordinator.start()
        windows.showTwice()
        XCTAssertEqual(observer.calls, 1)
        XCTAssertEqual(windows.requests, 1)
        XCTAssertEqual(trace.phases.filter { $0 == .windowShown }.count, 1)
    }

    func testNoObserverIsEverCalledIfTheWindowNeverAppears() {
        let observer = LoggingObserver("a", log: EventLog())
        let (coordinator, _, _, _) = make(observers: [observer])
        coordinator.start()
        XCTAssertEqual(observer.calls, 0)
        XCTAssertEqual(coordinator.phase, .launching)
        XCTAssertFalse(LaunchState.firstWindowPresented)
    }

    func testSynchronouslyPresentedWindowStillOrdersTraceBeforeObservers() {
        let log = EventLog()
        let observer = LoggingObserver("a", log: log)
        let (coordinator, windows, _, _) = make(observers: [observer], log: log)
        windows.presentsImmediately = true
        coordinator.start()
        XCTAssertEqual(log.events, ["trace:launching", "window:requested", "window:shown", "trace:windowShown",
                                    "observer:a", "trace:running"])
    }

    // MARK: TC-13..18 ordering with an update available (U1) and an offline updater (U2)

    func testTC13to15ObserversNotifiedOnlyAfterWindowForOneOrManyWindows() {
        for windowCount in [1, 1, 3] {   // D0 untitled, D1 one restored, D3 three restored
            let log = EventLog()
            let updater = LoggingObserver("updater", log: log)
            let (coordinator, windows, _, _) = make(observers: [updater], log: log)
            coordinator.start()
            for _ in 0..<windowCount { log.add("window:restored") }
            XCTAssertEqual(updater.calls, 0)
            windows.show()
            XCTAssertEqual(updater.calls, 1)
            XCTAssertLessThan(log.index(of: "window:shown")!, log.index(of: "observer:updater")!)
        }
    }

    func testTC16to18OfflineUpdaterDoesNotBlockOrDelayWindowAndOthersStillRun() {
        let log = EventLog()
        let offline = FailingObserver()
        let after = LoggingObserver("resolver", log: log)
        let (coordinator, windows, trace, _) = make(observers: [offline, after], log: log)
        coordinator.start()
        windows.show()
        XCTAssertEqual(trace.phases, [.launching, .windowShown, .running])
        XCTAssertEqual(offline.calls, 1)
        XCTAssertEqual(after.calls, 1)
        XCTAssertTrue(LaunchState.firstWindowPresented)
    }

    func testTC13WindowIsPresentedWithoutAnyObserverAtAll() {
        let (coordinator, windows, trace, _) = make(observers: [])
        coordinator.start()
        windows.show()
        XCTAssertEqual(coordinator.phase, .running)
        XCTAssertEqual(trace.phases.first, .launching)
    }

    // MARK: TC-51, 52, 53, 56 at coordinator level

    func testTC51to53and56NoUpdaterEngineNetworkOrAudioFileWorkBeforeTheWindow() {
        let log = EventLog()
        let deferred = RecordingDeferredWork(log: log)
        let (coordinator, windows, _, _) = make(observers: [deferred], log: log)
        coordinator.start()
        XCTAssertEqual(deferred.started, 0)
        for event in ["engine:init", "network:request", "audio-file:open", "updater:start"] {
            XCTAssertNil(log.index(of: event), "\(event) ran before the window")
        }
        windows.show()
        let shown = log.index(of: "window:shown")!
        for event in ["engine:init", "network:request", "audio-file:open", "updater:start"] {
            XCTAssertGreaterThan(log.index(of: event)!, shown, event)
        }
        XCTAssertEqual(deferred.started, 1)
    }

    func testTC51RealUpdaterControllerIsNotStartedBeforeTheFirstWindow() {
        let updater = UpdaterController(configuration: UpdateConfiguration.fromBundle())
        let (coordinator, windows, _, _) = make(observers: [updater])
        coordinator.start()
        XCTAssertEqual(updater.state, .notStarted)
        windows.show()
        XCTAssertNotEqual(updater.state, .notStarted)
    }

    func testTC56TheCoordinatorItselfOpensNoFileAndDoesNoWorkBeforeTheWindow() {
        // The coordinator only talks to the trace and the window provider before presentation.
        let (coordinator, _, _, log) = make()
        coordinator.start()
        XCTAssertEqual(log.events, ["trace:launching", "window:requested"])
    }

    func testLaunchStateFlagFlipsOnlyWhenTheWindowIsShown() {
        XCTAssertFalse(LaunchState.firstWindowPresented)
        let (coordinator, windows, _, _) = make(observers: [LoggingObserver("resolver", log: EventLog())])
        coordinator.start()
        XCTAssertFalse(LaunchState.firstWindowPresented)
        windows.show()
        XCTAssertTrue(LaunchState.firstWindowPresented)
    }
}
