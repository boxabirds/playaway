import AppKit
import XCTest
@testable import LocalPlayer
@testable import PlayawayCore

final class StubUpdaterDriver: UpdaterDriver {
    var startCalls = 0
    var checkCalls = 0
    var sessionInProgress = false
    var startError: Error?
    /// When true a check keeps the session open until the test finishes it.
    var checkKeepsSessionOpen = true

    func start() throws {
        startCalls += 1
        if let startError { throw startError }
    }

    func checkForUpdates() {
        checkCalls += 1
        if checkKeepsSessionOpen { sessionInProgress = true }
    }
}

private struct StubStartError: Error {}

private func validConfiguration() -> UpdateConfiguration {
    UpdateConfiguration(feedURL: wellFormedTestFeed, publicEDKey: wellFormedTestKey, automaticChecksEnabled: true)
}

private func invalidConfiguration() -> UpdateConfiguration {
    UpdateConfiguration(feedURL: "https://PLACEHOLDER-FEED-HOST/appcast.xml", publicEDKey: "PLACEHOLDER-PUBLIC-ED-KEY",
                        automaticChecksEnabled: true)
}

final class UpdaterControllerTests: XCTestCase {
    private var logged: [String] = []
    private var factoryCalls = 0

    private func makeController(_ configuration: UpdateConfiguration = validConfiguration(),
                                driver: StubUpdaterDriver = StubUpdaterDriver()) -> (UpdaterController, StubUpdaterDriver) {
        let controller = UpdaterController(configuration: configuration,
                                           driverFactory: { [unowned self] in factoryCalls += 1; return driver },
                                           log: { [unowned self] in logged.append($0) })
        return (controller, driver)
    }

    func testCreatedControllerHasNotStartedSparkle_TC30() {
        let (controller, driver) = makeController()
        XCTAssertEqual(controller.state, .notStarted)
        XCTAssertEqual(factoryCalls, 0, "the updater is not even created before the first window")
        XCTAssertEqual(driver.startCalls, 0)
        XCTAssertFalse(controller.canCheckForUpdates)
    }

    func testFirstWindowStartsExactlyOnce_TC31() {
        let (controller, driver) = makeController()
        controller.firstWindowPresented()
        XCTAssertEqual(driver.startCalls, 1)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(logged.isEmpty)
    }

    func testSecondStartIsIgnored_TC32() {
        let (controller, driver) = makeController()
        controller.startAfterFirstWindow()
        controller.startAfterFirstWindow()
        controller.firstWindowPresented()
        XCTAssertEqual(driver.startCalls, 1)
        XCTAssertEqual(factoryCalls, 1)
        XCTAssertEqual(controller.state, .idle)
    }

    func testInvalidConfigurationFailsLogsAndDisablesTheMenuItem_TC33() {
        let (controller, driver) = makeController(invalidConfiguration())
        controller.firstWindowPresented()
        XCTAssertEqual(controller.state, .failed)
        XCTAssertEqual(driver.startCalls, 0)
        XCTAssertEqual(factoryCalls, 0)
        XCTAssertEqual(logged.count, 1)
        XCTAssertTrue(logged[0].contains("SUFeedURL"), logged[0])
        XCTAssertTrue(controller.issues.contains(.publicKeyPlaceholder))
        XCTAssertFalse(controller.checkForUpdates())
        XCTAssertEqual(driver.checkCalls, 0)

        let delegate = AppDelegate()
        delegate.updater = controller
        let item = UpdateMenu.makeItem(target: delegate)
        XCTAssertFalse(delegate.validateMenuItem(item))
        // A failed state is final: a later signal does not retry.
        controller.firstWindowPresented()
        XCTAssertEqual(controller.state, .failed)
        XCTAssertEqual(logged.count, 1)
    }

    func testStartErrorFailsWithoutCrashing_TC33() {
        let driver = StubUpdaterDriver()
        driver.startError = StubStartError()
        let (controller, _) = makeController(driver: driver)
        controller.firstWindowPresented()
        XCTAssertEqual(controller.state, .failed)
        XCTAssertEqual(logged.count, 1)
    }

    /// The shipped Info.plist: a valid configuration starts Sparkle once the first window is up; an invalid one
    /// (a placeholder left behind) fails, logs and never creates Sparkle.
    func testTheShippedConfigurationStartsSparkleOnlyWhenItIsValid_TC33() throws {
        let configuration = UpdateConfiguration.from(info: try shippedInfo())
        var created = 0
        let controller = UpdaterController(configuration: configuration, driverFactory: {
            created += 1
            return StubUpdaterDriver()
        }, log: { [unowned self] in logged.append($0) })
        controller.firstWindowPresented()
        if validate(configuration).isEmpty {
            XCTAssertEqual(controller.state, .idle)
            XCTAssertEqual(created, 1, "the shipped configuration is valid, so Sparkle is created once")
        } else {
            XCTAssertEqual(created, 0, "Sparkle must not be created for an invalid configuration")
            XCTAssertEqual(controller.state, .failed)
            XCTAssertFalse(logged.isEmpty)
        }
    }

    func testStartComesOnlyAfterTheFirstWindowOfEitherKind_TC39_TC83() {
        for kind in ["restored playlist window", "untitled new-playlist window"] {
            let (controller, driver) = makeController()
            let trace = LaunchTrace(resultsPath: nil)
            let probe = OrderProbe(trace: trace, controller: controller)
            let windows = DeferredWindows()
            let coordinator = LaunchCoordinator(trace: trace, observers: [probe, controller], windows: windows)
            coordinator.start()
            XCTAssertEqual(driver.startCalls, 0, "\(kind): no window presented yet, start must not be called")
            XCTAssertEqual(controller.state, .notStarted)
            windows.present()
            XCTAssertEqual(driver.startCalls, 1, kind)
            XCTAssertEqual(controller.state, .idle)
            XCTAssertEqual(probe.phaseWhenSignalled, .windowShown, "start is signalled only after the window is recorded as shown")
            XCTAssertFalse(probe.stateWhenSignalledWasStarted, "the updater had not started before the first-window signal")
        }
    }

    // MARK: Menu (updates.menu.check)

    func testMenuItemPresentExactlyOnceWithTitleAndAction_TC35() {
        let delegate = AppDelegate()
        let menu = AppMenu.makeMenuBar(target: delegate)
        var items: [NSMenuItem] = []
        func collect(_ menu: NSMenu) {
            for item in menu.items {
                if item.action == NSSelectorFromString("checkForUpdates:") { items.append(item) }
                if let submenu = item.submenu { collect(submenu) }
            }
        }
        collect(menu)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.title, "Check for Updates…")
        XCTAssertEqual(items.first?.title, UpdateMenu.title)
        XCTAssertEqual(NSStringFromSelector(UpdateMenu.action), "checkForUpdates:")
        XCTAssertEqual(UpdateMenu.actionID, "checkForUpdates")
        XCTAssertTrue(items.first?.target === delegate)
        XCTAssertEqual(menu.items.first?.submenu?.items.filter { $0.title == UpdateMenu.title }.count, 1, "in the app menu")
    }

    func testChoosingDuringARunningCheckStartsNoSecondCheck_TC36() {
        let (controller, driver) = makeController()
        controller.firstWindowPresented()
        XCTAssertTrue(controller.checkForUpdates())
        XCTAssertEqual(driver.checkCalls, 1)
        XCTAssertFalse(controller.checkForUpdates(), "second choice while the check is running")
        XCTAssertFalse(controller.checkForUpdates())
        XCTAssertEqual(driver.checkCalls, 1)
        driver.sessionInProgress = false
        XCTAssertTrue(controller.checkForUpdates(), "a new check is allowed once the first has finished")
        XCTAssertEqual(driver.checkCalls, 2)
    }

    func testMenuItemEnabledOnlyWhenTheUpdaterIsIdle_TC37() {
        let delegate = AppDelegate()
        let item = UpdateMenu.makeItem(target: delegate)
        let (controller, _) = makeController()
        delegate.updater = controller
        XCTAssertFalse(delegate.validateMenuItem(item), "not started")
        controller.firstWindowPresented()
        XCTAssertTrue(delegate.validateMenuItem(item), "idle")

        let (failed, _) = makeController(invalidConfiguration())
        failed.firstWindowPresented()
        delegate.updater = failed
        XCTAssertFalse(delegate.validateMenuItem(item), "failed")
    }

    func testMenuActionForwardsToTheUpdater() {
        let (controller, driver) = makeController()
        controller.firstWindowPresented()
        let delegate = AppDelegate()
        delegate.updater = controller
        delegate.checkForUpdates(nil)
        XCTAssertEqual(driver.checkCalls, 1)
    }

    private func shippedInfo() throws -> [String: Any] {
        let data = try Data(contentsOf: RepoLayout.url("Resources/Info.plist"))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
}

/// Provides a window only when the test says so.
private final class DeferredWindows: LaunchWindowProviding {
    private var completion: (() -> Void)?
    func presentFirstWindow(completion: @escaping () -> Void) { self.completion = completion }
    func present() { completion?() }
}

/// Records what the launch phase and the updater state were when the first-window signal arrived.
private final class OrderProbe: FirstWindowObserver {
    let trace: LaunchTrace
    let controller: UpdaterController
    var phaseWhenSignalled: LaunchPhase?
    var stateWhenSignalledWasStarted = false

    init(trace: LaunchTrace, controller: UpdaterController) {
        self.trace = trace
        self.controller = controller
    }

    func firstWindowPresented() {
        phaseWhenSignalled = trace.recorded.last?.phase
        stateWhenSignalledWasStarted = controller.state != .notStarted
    }
}
