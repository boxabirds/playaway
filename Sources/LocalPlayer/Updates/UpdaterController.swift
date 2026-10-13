import PlayawayCore
import Foundation
import os
import Sparkle

/// What the controller needs from an updater. Sparkle is behind this so state logic needs no Sparkle runtime.
protocol UpdaterDriver: AnyObject {
    /// True while an update session (scheduled or manual) is running.
    var sessionInProgress: Bool { get }
    func start() throws
    func checkForUpdates()
}

/// Owns the updater lifecycle. Created at launch without starting anything; started only once the first window
/// is on screen (`FirstWindowObserver`), so update checking never delays that window.
final class UpdaterController: FirstWindowObserver {
    enum State { case notStarted, idle, failed }

    /// The id the AppleScript story's action manifest uses for this action.
    static let checkForUpdatesActionID = "checkForUpdates"

    private(set) var state: State = .notStarted
    private(set) var issues: [ConfigIssue] = []
    let configuration: UpdateConfiguration
    private var driver: UpdaterDriver?
    private let driverFactory: () -> UpdaterDriver
    private let log: (String) -> Void
    private static let logger = Logger(subsystem: "LocalPlayer", category: "updates")

    /// The driver is built lazily at start, so nothing from Sparkle exists before the first window.
    init(configuration: UpdateConfiguration,
         driverFactory: @escaping () -> UpdaterDriver = { SparkleUpdaterDriver() },
         log: @escaping (String) -> Void = { UpdaterController.logger.error("\($0, privacy: .public)") }) {
        self.configuration = configuration
        self.driverFactory = driverFactory
        self.log = log
    }

    func firstWindowPresented() { startAfterFirstWindow() }

    /// Starts the updater once. Invalid configuration, or a start error, leaves the app working with updates off.
    func startAfterFirstWindow() {
        guard state == .notStarted else { return }
        issues = validate(configuration)
        guard issues.isEmpty else {
            state = .failed
            log("Updates disabled: " + issues.map(\.description).joined(separator: "; "))
            return
        }
        let driver = driverFactory()
        do {
            try driver.start()
            self.driver = driver
            state = .idle
        } catch {
            state = .failed
            log("Updates disabled: the updater could not start: \(error.localizedDescription)")
        }
    }

    /// True when choosing Check for Updates would start a check.
    var canCheckForUpdates: Bool { state == .idle && driver?.sessionInProgress == false }

    /// A manual check. Ignored while another check or update session is running.
    @discardableResult
    func checkForUpdates() -> Bool {
        guard canCheckForUpdates, let driver else { return false }
        driver.checkForUpdates()
        return true
    }
}

/// The real updater: Sparkle's standard controller, created without starting.
final class SparkleUpdaterDriver: NSObject, UpdaterDriver, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    }

    var sessionInProgress: Bool { controller.updater.sessionInProgress }
    func start() throws { try controller.updater.start() }
    func checkForUpdates() { controller.checkForUpdates(nil) }

    /// Debug builds only: lets tests point the updater at a local fixture feed. Always nil in release.
    func feedURLString(for updater: SPUUpdater) -> String? { FeedURLOverride.resolve() }
}
