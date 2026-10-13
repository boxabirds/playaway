import PlayawayCore
import AppKit
import CryptoKit
import Foundation
import Sparkle

// Self-test for the update setup, run from the built app by `--test-sparkle-config` and
// `--test-sparkle-integration` (the app's launch-flag parser calls the two entry points below).
// One line per check: "PASS name", "FAIL name (file:line)" or "SKIP name: reason". A final RESULT line
// summarises. The exit code is non-zero when any check failed.

/// Collects check results and prints one line each.
final class SelfTestReport {
    private(set) var passed = 0
    private(set) var failed = 0
    private(set) var skipped = 0
    private let output: (String) -> Void

    init(output: @escaping (String) -> Void) { self.output = output }

    func check(_ name: String, _ condition: Bool, file: String = #fileID, line: Int = #line) {
        if condition {
            passed += 1
            output("PASS \(name)")
        } else {
            failed += 1
            output("FAIL \(name) (\(file):\(line))")
        }
    }

    func fail(_ name: String, _ detail: String, file: String = #fileID, line: Int = #line) {
        failed += 1
        output("FAIL \(name): \(detail) (\(file):\(line))")
    }

    func skip(_ name: String, reason: String) {
        skipped += 1
        output("SKIP \(name): \(reason)")
    }

    /// Prints the summary line and returns the process exit code.
    func finish() -> Int32 {
        output("RESULT: \(passed) passed, \(failed) failed, \(skipped) skipped")
        return failed == 0 ? SelfTestExit.success : SelfTestExit.failure
    }
}

enum SelfTestExit {
    static let success: Int32 = 0
    static let failure: Int32 = 1
}

/// `--test-sparkle-config`: proves from the app's own bundle that update checking and verification are set up.
func runSparkleConfigTest() -> Int32 {
    SparkleSelfTest.runConfig(info: Bundle.main.infoDictionary ?? [:], bundlePath: Bundle.main.bundlePath,
                              repoRoot: SparkleSelfTest.findRepoRoot(), output: { print($0) })
}

/// `--test-sparkle-integration <feed>`: runs the real updater against a local fixture feed. The feed address is
/// required; a missing address fails loudly instead of passing.
func runSparkleIntegrationTest(feed: String?) -> Int32 {
    SparkleSelfTest.runIntegration(feed: feed, tamperedFeed: ProcessInfo.processInfo.environment[SparkleSelfTest.tamperedFeedKey],
                                   hostBundle: .main, output: { print($0) })
}

enum SparkleSelfTest {
    static let tamperedFeedKey = "LOCALPLAYER_TEST_TAMPERED_FEED_URL"
    static let repoRootKey = "LOCALPLAYER_REPO_ROOT"
    static let sparkleDependencyMarker = "sparkle-project/Sparkle"
    static let checkTimeoutSeconds: TimeInterval = 30
    static let runLoopSliceSeconds: TimeInterval = 0.05
    /// How many folders above the app bundle are searched for the source checkout.
    static let repoSearchDepth = 6
    static let appBundleSuffix = ".app"
    static let minOSScript = "scripts/check-min-os.sh"
    static let sparkleFrameworkPath = "/Contents/Frameworks/Sparkle.framework"

    // MARK: Config

    static func runConfig(info: [String: Any], bundlePath: String, repoRoot: URL?,
                          output: @escaping (String) -> Void) -> Int32 {
        let report = SelfTestReport(output: output)
        let configuration = UpdateConfiguration.from(info: info)
        let issues = validate(configuration)
        func no(_ issue: ConfigIssue) -> Bool { !issues.contains(issue) }

        report.check("SUFeedURL is present in Info.plist", no(.feedURLMissing))
        report.check("SUFeedURL uses https", !configuration.feedURL.isEmpty && no(.feedURLNotHTTPS))
        report.check("SUFeedURL is a valid URL", !configuration.feedURL.isEmpty && no(.feedURLUnparsable))
        report.check("SUFeedURL is not a placeholder", no(.feedURLPlaceholder))
        report.check("SUPublicEDKey is present and non-empty", no(.publicKeyMissing))
        report.check("SUPublicEDKey is valid base64", !configuration.publicEDKey.isEmpty && no(.publicKeyNotBase64))
        report.check("SUPublicEDKey is longer than \(UpdateConfigurationRules.minimumPublicKeyLength) characters",
                     !configuration.publicEDKey.isEmpty && no(.publicKeyTooShort))
        report.check("SUPublicEDKey is not a placeholder", no(.publicKeyPlaceholder))
        report.check("SUPublicEDKey is not another product's key", no(.publicKeyIsCutawayKey))
        report.check("SUEnableAutomaticChecks is true (no permission question is shown)", no(.automaticChecksNotEnabled))

        if bundlePath.hasSuffix(appBundleSuffix) {
            report.check("Sparkle.framework is embedded in Contents/Frameworks",
                         FileManager.default.fileExists(atPath: bundlePath + sparkleFrameworkPath))
        } else {
            report.skip("Sparkle.framework is embedded in Contents/Frameworks", reason: "not running from an .app bundle")
        }

        if let repoRoot {
            let manifest = (try? String(contentsOf: repoRoot.appendingPathComponent("Package.swift"), encoding: .utf8)) ?? ""
            report.check("Package.swift declares the Sparkle dependency", packageDeclaresSparkle(manifest))
            let script = repoRoot.appendingPathComponent(minOSScript).path
            let (status, text) = runProcess(script, arguments: [])
            report.check("Minimum macOS version is consistent (scripts/check-min-os.sh)", status == 0)
            if status != 0 { output("     " + text.replacingOccurrences(of: "\n", with: "\n     ")) }
        } else {
            report.check("Sparkle is linked into the app", NSClassFromString("SPUStandardUpdaterController") != nil)
            report.skip("Minimum macOS version is consistent (scripts/check-min-os.sh)",
                        reason: "no source checkout found (set \(repoRootKey))")
        }
        return report.finish()
    }

    static func packageDeclaresSparkle(_ manifest: String) -> Bool {
        manifest.contains(sparkleDependencyMarker) && manifest.contains("\"Sparkle\"")
    }

    static func findRepoRoot(environment: [String: String] = ProcessInfo.processInfo.environment,
                             bundlePath: String = Bundle.main.bundlePath,
                             currentDirectory: String = FileManager.default.currentDirectoryPath) -> URL? {
        var candidates: [URL] = []
        if let explicit = environment[repoRootKey] { candidates.append(URL(fileURLWithPath: explicit)) }
        candidates.append(URL(fileURLWithPath: currentDirectory))
        var url = URL(fileURLWithPath: bundlePath)
        for _ in 0..<repoSearchDepth { url = url.deletingLastPathComponent(); candidates.append(url) }
        return candidates.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent(minOSScript).path)
                && FileManager.default.fileExists(atPath: $0.appendingPathComponent("Package.swift").path)
        }
    }

    @discardableResult
    static func runProcess(_ path: String, arguments: [String]) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (SelfTestExit.failure, "could not run \(path): \(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    // MARK: Integration

    static func runIntegration(feed: String?, tamperedFeed: String?, hostBundle: Bundle,
                               output: @escaping (String) -> Void) -> Int32 {
        let report = SelfTestReport(output: output)

        // The action the menu item sends is Sparkle's own check-for-updates selector.
        let expectedAction = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
        let item = UpdateMenu.makeItem(target: nil)
        report.check("Check for Updates menu action is Sparkle's checkForUpdates:", item.action == expectedAction)
        report.check("Check for Updates action id is checkForUpdates", UpdateMenu.actionID == "checkForUpdates")

        // The updater is created without starting, and only the first-window signal starts it.
        var factoryCalls = 0
        let probe = UpdaterController(configuration: UpdateConfiguration.from(info: hostBundle.infoDictionary ?? [:]),
                                      driverFactory: { factoryCalls += 1; return SparkleUpdaterDriver() }, log: { _ in })
        report.check("Updater is created deferred (not started, Sparkle not created)", probe.state == .notStarted && factoryCalls == 0)

        guard let feed, !feed.isEmpty, URL(string: feed) != nil else {
            report.fail("fixture feed address is required", "pass the local fixture feed URL after --test-sparkle-integration")
            return report.finish()
        }

        #if DEBUG
        runUpdaterAgainstFixture(report: report, feed: feed, tamperedFeed: tamperedFeed, hostBundle: hostBundle)
        #else
        report.fail("real updater against the fixture feed", "the feed override is compiled out of release builds; use a debug build")
        #endif
        return report.finish()
    }

    #if DEBUG
    private static func runUpdaterAgainstFixture(report: SelfTestReport, feed: String, tamperedFeed: String?, hostBundle: Bundle) {
        // 1. A manual check completes and reports an available update or up to date. Nothing is ever installed.
        let manual = FixtureCheck.run(feedURL: feed, hostBundle: hostBundle, installOffered: false)
        report.check("updater starts against the fixture feed", manual.startError == nil)
        if let error = manual.startError { report.fail("updater start error", error) }
        report.check("manual check completes (\(manual.outcome.description))", manual.outcome.isFinished)
        report.check("no automatic-check permission question was shown", !manual.permissionQuestionAsked)

        // 2. A fixture item with an altered signature is refused and the host bundle is unchanged.
        guard let tamperedFeed, !tamperedFeed.isEmpty else {
            report.skip("altered-signature update is refused and the bundle is unchanged",
                        reason: "set \(tamperedFeedKey) to the fixture feed whose item signature is altered")
            return
        }
        let before = FixtureCheck.digest(of: hostBundle.bundleURL)
        let tampered = FixtureCheck.run(feedURL: tamperedFeed, hostBundle: hostBundle, installOffered: true)
        if case .installDeclined(let reason) = tampered.outcome {
            report.fail("altered-signature update is refused and the bundle is unchanged", "install not attempted: \(reason)")
            return
        }
        report.check("altered-signature update was offered then refused (\(tampered.outcome.description))",
                     tampered.outcome == .errorAfterInstallChoice)
        report.check("refused update never reached ready-to-install", !tampered.reachedReadyToInstall)
        report.check("host bundle is unchanged after the refused update", FixtureCheck.digest(of: hostBundle.bundleURL) == before)
    }
    #endif
}

/// What a headless run of the real updater observed.
enum FixtureOutcome: Equatable, CustomStringConvertible {
    case pending
    case updateAvailable(String)
    case upToDate
    case error(String)
    /// An install was chosen for an offered update and Sparkle then refused with an error.
    case errorAfterInstallChoice
    /// The driver declined to choose install because it could not prove the offered signature invalid.
    case installDeclined(String)

    var isFinished: Bool {
        switch self {
        case .updateAvailable, .upToDate: return true
        default: return false
        }
    }

    var description: String {
        switch self {
        case .pending: return "no result before the timeout"
        case .updateAvailable(let version): return "update available: \(version)"
        case .upToDate: return "up to date"
        case .error(let message): return "error: \(message)"
        case .errorAfterInstallChoice: return "refused with an error"
        case .installDeclined(let reason): return "install declined: \(reason)"
        }
    }
}

struct FixtureResult {
    var outcome: FixtureOutcome = .pending
    var startError: String?
    var permissionQuestionAsked = false
    var reachedReadyToInstall = false
    /// The text of the last error Sparkle reported, if any.
    var errorText: String?
    /// True once Sparkle started downloading an offered update.
    var downloadStarted = false
}

/// A user driver that shows nothing. It records what Sparkle asked for, answers "dismiss" (or "install" when
/// told to) and never relaunches anything.
final class HeadlessUserDriver: NSObject, SPUUserDriver {
    var result = FixtureResult()
    let installOffered: Bool
    private let publicKey: Data?
    private var installChosen = false

    /// `publicKey` is the host's SUPublicEDKey. It is used only for the safety check before an install is chosen.
    init(installOffered: Bool, publicKey: Data?) {
        self.installOffered = installOffered
        self.publicKey = publicKey
    }

    /// Install is chosen only for an update whose signature this driver can positively show to be INVALID, so a
    /// genuine update (a wrong fixture, a real feed) can never be installed by the self-test.
    /// Returns nil when the offered update's signature is provably invalid, otherwise the reason not to install.
    func reasonNotToInstall(_ item: SUAppcastItem) -> String? {
        guard let publicKey, let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else {
            return "the host has no usable SUPublicEDKey to pre-check the signature"
        }
        guard let enclosure = item.propertiesDictionary["enclosure"] as? [String: Any],
              let signatureText = enclosure["sparkle:edSignature"] as? String,
              let signature = Data(base64Encoded: signatureText), let url = item.fileURL,
              let archive = try? Data(contentsOf: url) else {
            return "the offered update's signature or archive could not be read to pre-check it"
        }
        return key.isValidSignature(signature, for: archive) ? "the offered update's signature is valid (the fixture is not tampered)" : nil
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        result.permissionQuestionAsked = true
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if installOffered {
            if let reason = reasonNotToInstall(appcastItem) {
                result.outcome = .installDeclined(reason)
                reply(.dismiss)
            } else {
                installChosen = true
                reply(.install)
            }
        } else {
            result.outcome = .updateAvailable(appcastItem.displayVersionString)
            reply(.dismiss)
        }
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        result.outcome = .upToDate
        acknowledgement()
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        result.errorText = [error.localizedDescription, (error as NSError).localizedFailureReason].compactMap { $0 }.joined(separator: " ")
        result.outcome = installChosen ? .errorAfterInstallChoice : .error(error.localizedDescription)
        acknowledgement()
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { result.downloadStarted = true }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        result.reachedReadyToInstall = true
        reply(.dismiss)
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func showUpdateInFocus() {}
    func dismissUpdateInstallation() {}
}

#if DEBUG
/// Runs Sparkle's real updater against a fixture feed with a headless user driver.
enum FixtureCheck {
    final class Delegate: NSObject, SPUUpdaterDelegate {
        let feed: String
        init(feed: String) { self.feed = feed }
        func feedURLString(for updater: SPUUpdater) -> String? { feed }
    }

    static func run(feedURL: String, hostBundle: Bundle, installOffered: Bool,
                    timeout: TimeInterval = SparkleSelfTest.checkTimeoutSeconds) -> FixtureResult {
        let publicKey = (hostBundle.object(forInfoDictionaryKey: UpdateConfiguration.publicKeyKey) as? String).flatMap { Data(base64Encoded: $0) }
        let driver = HeadlessUserDriver(installOffered: installOffered, publicKey: publicKey)
        let delegate = Delegate(feed: feedURL)
        let updater = SPUUpdater(hostBundle: hostBundle, applicationBundle: hostBundle, userDriver: driver, delegate: delegate)
        do {
            try updater.start()
        } catch {
            driver.result.startError = error.localizedDescription
            return driver.result
        }
        updater.checkForUpdates()
        let deadline = Date().addingTimeInterval(timeout)
        while driver.result.outcome == .pending, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(SparkleSelfTest.runLoopSliceSeconds))
        }
        updater.resetUpdateCycle()
        return driver.result
    }

    /// A digest of every file's path, size and modification time under the bundle.
    static func digest(of bundle: URL) -> String {
        var lines: [String] = []
        let enumerator = FileManager.default.enumerator(at: bundle, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
        while let url = enumerator?.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            lines.append("\(url.path)|\(values?.fileSize ?? -1)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)")
        }
        return lines.sorted().joined(separator: "\n")
    }
}
#endif
