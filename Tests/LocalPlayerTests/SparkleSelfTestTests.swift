import CryptoKit
import XCTest
@testable import LocalPlayer
@testable import PlayawayCore

private func lines(_ run: (@escaping (String) -> Void) -> Int32) -> (status: Int32, lines: [String]) {
    var output: [String] = []
    let status = run { output.append($0) }
    return (status, output)
}

/// Sparkle's own wording when an update's signature does not verify (observed with Sparkle 2.10.0).
private let sparkleBadSignatureText = "improperly signed"

private let validInfo: [String: Any] = [
    "SUFeedURL": wellFormedTestFeed, "SUPublicEDKey": wellFormedTestKey, "SUEnableAutomaticChecks": true,
    "LSMinimumSystemVersion": "26.0",
]

final class SparkleSelfTestHarnessTests: XCTestCase {
    private func config(_ info: [String: Any], bundlePath: String = "/not/an/app", repoRoot: URL? = nil) -> (status: Int32, lines: [String]) {
        lines { SparkleSelfTest.runConfig(info: info, bundlePath: bundlePath, repoRoot: repoRoot, output: $0) }
    }

    func testValidConfigurationPrintsOneLinePerCheckAndExitsZero_TC70() {
        let result = config(validInfo, repoRoot: RepoLayout.root)
        XCTAssertEqual(result.status, 0, result.lines.joined(separator: "\n"))
        let checkLines = result.lines.filter { $0.hasPrefix("PASS") || $0.hasPrefix("FAIL") || $0.hasPrefix("SKIP") }
        XCTAssertEqual(checkLines.count, result.lines.count - 1, "every line is a check except the RESULT summary")
        XCTAssertTrue(result.lines.last?.hasPrefix("RESULT:") == true)
        XCTAssertTrue(result.lines.contains { $0.hasPrefix("PASS Package.swift declares the Sparkle dependency") })
        XCTAssertTrue(result.lines.contains { $0.hasPrefix("PASS Minimum macOS version is consistent") })
        XCTAssertFalse(result.lines.contains { $0.hasPrefix("FAIL") })
        // Not running from an .app bundle is reported as a skip with a reason, not as a pass.
        XCTAssertTrue(result.lines.contains { $0.hasPrefix("SKIP Sparkle.framework is embedded") && $0.contains("not running from an .app") })
    }

    func testMissingAutomaticChecksKeyFailsNamingIt_TC72() {
        var info = validInfo
        info.removeValue(forKey: "SUEnableAutomaticChecks")
        let result = config(info)
        XCTAssertNotEqual(result.status, 0)
        let failing = result.lines.filter { $0.hasPrefix("FAIL") }
        XCTAssertEqual(failing.count, 1, "\(failing)")
        XCTAssertTrue(failing[0].contains("SUEnableAutomaticChecks"))
        XCTAssertTrue(failing[0].contains("SparkleConfigTest.swift:"), "failure carries file and line: \(failing[0])")
        info["SUEnableAutomaticChecks"] = false
        XCTAssertNotEqual(config(info).status, 0)
    }

    func testEachBadValueFailsItsOwnLine_TC20_TC28() {
        func failures(_ key: String, _ value: Any) -> [String] {
            var info = validInfo
            info[key] = value
            return config(info).lines.filter { $0.hasPrefix("FAIL") }
        }
        XCTAssertTrue(failures("SUFeedURL", "http://x.example.test/a.xml").contains { $0.contains("https") })
        XCTAssertTrue(failures("SUFeedURL", "https://PLACEHOLDER-FEED-HOST/a.xml").contains { $0.contains("placeholder") })
        XCTAssertTrue(failures("SUPublicEDKey", foreignProductKey).contains { $0.contains("another product's key") })
        XCTAssertTrue(failures("SUPublicEDKey", "AAAAAAAA").contains { $0.contains("longer than") })
        XCTAssertTrue(failures("SUPublicEDKey", "***").contains { $0.contains("base64") })
        XCTAssertEqual(config([:]).status, 1)
    }

    func testMinOSDisagreementFailsTheConfigRun_TC41() throws {
        let copy = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("selftest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: copy) }
        try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
        for item in ["scripts", "Resources", "Package.swift"] {
            try FileManager.default.copyItem(at: RepoLayout.url(item), to: copy.appendingPathComponent(item))
        }
        let package = copy.appendingPathComponent("Package.swift")
        try String(contentsOf: package, encoding: .utf8).replacingOccurrences(of: ".macOS(.v26)", with: ".macOS(.v15)").write(to: package, atomically: true, encoding: .utf8)
        let result = config(validInfo, repoRoot: copy)
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.lines.contains { $0.hasPrefix("FAIL Minimum macOS version is consistent") })
        XCTAssertTrue(result.lines.contains { $0.contains("FAIL Package.swift") }, "the validator's own output is shown")
    }

    func testRepoRootDiscovery() {
        XCTAssertEqual(SparkleSelfTest.findRepoRoot(environment: [SparkleSelfTest.repoRootKey: RepoLayout.root.path], bundlePath: "/x", currentDirectory: "/"),
                       RepoLayout.root)
        XCTAssertNil(SparkleSelfTest.findRepoRoot(environment: [:], bundlePath: "/x/LocalPlayer.app", currentDirectory: "/"))
    }

    func testIntegrationModeWithoutAFeedAddressFailsLoudly_TC71() {
        for feed in [nil, ""] as [String?] {
            let result = lines { SparkleSelfTest.runIntegration(feed: feed, tamperedFeed: nil, hostBundle: .main, output: $0) }
            XCTAssertEqual(result.status, 1)
            XCTAssertTrue(result.lines.contains { $0.hasPrefix("FAIL fixture feed address is required") }, "\(result.lines)")
        }
    }

    func testIntegrationModeChecksTheMenuActionAndDeferredStart_TC71() {
        let result = lines { SparkleSelfTest.runIntegration(feed: nil, tamperedFeed: nil, hostBundle: .main, output: $0) }
        XCTAssertTrue(result.lines.contains("PASS Check for Updates menu action is Sparkle's checkForUpdates:"))
        XCTAssertTrue(result.lines.contains("PASS Check for Updates action id is checkForUpdates"))
        XCTAssertTrue(result.lines.contains { $0.hasPrefix("PASS Updater is created deferred") })
    }

    func testReportCountsAndExitCodes() {
        var printed: [String] = []
        let report = SelfTestReport(output: { printed.append($0) })
        report.check("a", true)
        report.skip("b", reason: "because")
        XCTAssertEqual(report.finish(), 0)
        report.check("c", false)
        XCTAssertEqual(report.finish(), 1)
        XCTAssertEqual(printed.first, "PASS a")
        XCTAssertEqual(printed[1], "SKIP b: because")
        XCTAssertTrue(printed[2].hasPrefix("RESULT: 1 passed, 0 failed, 1 skipped"))
    }
}

#if DEBUG
/// The real Sparkle updater, headless, against a local fixture feed served by python's http.server.
/// Keys are generated for the run; nothing touches the keychain and nothing is ever installed.
final class SparkleFixtureIntegrationTests: XCTestCase {
    private var root: URL!
    private var server: Process?
    private var port = 0
    private var hostApp: URL!
    private var privateKey: Curve25519.Signing.PrivateKey!
    private let python = "/usr/bin/python3"
    private let startupTimeoutSeconds = 10.0
    private var signUpdate: String { RepoLayout.url(".build/artifacts/sparkle/Sparkle/bin/sign_update").path }

    override func setUpWithError() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: python), "python3 not available for the fixture server")
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: signUpdate), "sign_update not resolved")
        root = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().appendingPathComponent("fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("site"), withIntermediateDirectories: true)
        privateKey = Curve25519.Signing.PrivateKey()
        try makeHostApp()
        try makeDMG()
        try startServer()
        try writeFeeds()
    }

    override func tearDown() {
        server?.terminate()
        server?.waitUntilExit()
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    private var site: URL { root.appendingPathComponent("site") }
    private func feed(_ name: String) -> String { "http://127.0.0.1:\(port)/\(name)" }

    /// A minimal app bundle at version 1.0 carrying the throwaway public key.
    private func makeHostApp() throws {
        hostApp = root.appendingPathComponent("Host.app")
        let contents = hostApp.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "test.fixture.host.\(UUID().uuidString)", "CFBundleName": "FixtureHost", "CFBundleExecutable": "FixtureHost",
            "CFBundleVersion": "1.0", "CFBundleShortVersionString": "1.0", "CFBundlePackageType": "APPL",
            "SUFeedURL": "https://fixture.example.test/appcast.xml", "SUEnableAutomaticChecks": true,
            "SUPublicEDKey": privateKey.publicKey.rawRepresentation.base64EncodedString(),
        ]
        try (info as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))
        try "fixture".write(to: contents.appendingPathComponent("MacOS/FixtureHost"), atomically: true, encoding: .utf8)
    }

    private func makeDMG() throws {
        let payload = root.appendingPathComponent("payload")
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        // The update is a copy of the host app at version 2.0, so a genuine signature gets through extraction.
        let updated = payload.appendingPathComponent("Host.app")
        try FileManager.default.copyItem(at: hostApp, to: updated)
        let plistURL = updated.appendingPathComponent("Contents/Info.plist")
        let info = NSMutableDictionary(contentsOf: plistURL)!
        info["CFBundleVersion"] = "2.0"
        info["CFBundleShortVersionString"] = "2.0"
        try info.write(to: plistURL)
        let result = try ScriptRunner.run("/usr/bin/hdiutil", arguments: ["create", "-volname", "Fixture", "-srcfolder", payload.path, "-ov",
                                                                       "-format", "UDZO", site.appendingPathComponent("Fixture-2.0.dmg").path], environment: [:])
        XCTAssertEqual(result.status, 0, result.output)
    }

    private func startServer() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = ["-u", "-m", "http.server", "0", "--bind", "127.0.0.1", "--directory", site.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        server = process
        var collected = ""
        let deadline = Date().addingTimeInterval(startupTimeoutSeconds)
        while port == 0, Date() < deadline {
            let chunk = pipe.fileHandleForReading.availableData
            collected += String(decoding: chunk, as: UTF8.self)
            if let range = collected.range(of: "port (\\d+)", options: .regularExpression),
               let value = Int(collected[range].dropFirst("port ".count)) { port = value }
        }
        XCTAssertNotEqual(port, 0, "fixture server did not report a port: \(collected)")
    }

    private func sign(_ file: URL) throws -> (signature: String, length: String) {
        let keyFile = root.appendingPathComponent("test.key")
        try privateKey.rawRepresentation.base64EncodedString().write(to: keyFile, atomically: true, encoding: .utf8)
        let out = try ScriptRunner.run(signUpdate, arguments: ["--ed-key-file", keyFile.path, file.path], environment: [:]).output
        let signature = try XCTUnwrap(out.range(of: "sparkle:edSignature=\"([^\"]+)\"", options: .regularExpression)
            .map { String(out[$0]).replacingOccurrences(of: "sparkle:edSignature=\"", with: "").dropLast() })
        let length = try XCTUnwrap(out.range(of: "length=\"(\\d+)\"", options: .regularExpression)
            .map { String(out[$0]).replacingOccurrences(of: "length=\"", with: "").dropLast() })
        return (String(signature), String(length))
    }

    private func appcast(version: String, minimumOS: String, signature: String, length: String) -> String {
        """
        <?xml version="1.0" standalone="yes"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel><title>Fixture</title>
        <item><title>Fixture \(version)</title><sparkle:version>\(version)</sparkle:version>
        <sparkle:shortVersionString>\(version)</sparkle:shortVersionString>
        <sparkle:minimumSystemVersion>\(minimumOS)</sparkle:minimumSystemVersion>
        <enclosure url="http://127.0.0.1:\(port)/Fixture-2.0.dmg" length="\(length)" type="application/octet-stream" sparkle:edSignature="\(signature)"/>
        </item></channel></rss>
        """
    }

    private func writeFeeds() throws {
        let good = try sign(site.appendingPathComponent("Fixture-2.0.dmg"))
        // One byte of the decoded signature changed: still well-formed, no longer valid.
        var bytes = try XCTUnwrap(Data(base64Encoded: good.signature))
        bytes[0] ^= 0xFF
        let altered = bytes.base64EncodedString()
        let files = [
            "newer.xml": appcast(version: "2.0", minimumOS: "26.0", signature: good.signature, length: good.length),
            "same.xml": appcast(version: "1.0", minimumOS: "26.0", signature: good.signature, length: good.length),
            "future-os.xml": appcast(version: "2.0", minimumOS: "99.0", signature: good.signature, length: good.length),
            "tampered.xml": appcast(version: "2.0", minimumOS: "26.0", signature: altered, length: good.length),
        ]
        for (name, text) in files { try text.write(to: site.appendingPathComponent(name), atomically: true, encoding: .utf8) }
    }

    private func check(_ name: String, install: Bool = false) -> FixtureResult {
        FixtureCheck.run(feedURL: feed(name), hostBundle: Bundle(url: hostApp)!, installOffered: install)
    }

    func testNewerVersionIsOffered_TC09_TC10() {
        let result = check("newer.xml")
        XCTAssertNil(result.startError)
        XCTAssertEqual(result.outcome, .updateAvailable("2.0"))
        XCTAssertFalse(result.permissionQuestionAsked, "no automatic-check permission question (TC-88)")
    }

    func testCurrentVersionReportsUpToDate_TC10() {
        XCTAssertEqual(check("same.xml").outcome, .upToDate)
    }

    func testItemRequiringANewerMacIsNeverOffered_TC13_TC82() {
        XCTAssertEqual(check("future-os.xml").outcome, .upToDate)
    }

    func testUnreachableFeedDoesNotCrashAndReportsAnError_TC12() {
        let result = FixtureCheck.run(feedURL: "http://127.0.0.1:1/appcast.xml", hostBundle: Bundle(url: hostApp)!, installOffered: false)
        if case .error = result.outcome {} else { XCTFail("expected an error, got \(result.outcome)") }
    }

    func testAlteredSignatureIsRefusedAndTheBundleIsUnchanged_TC11_TC81() {
        let before = FixtureCheck.digest(of: hostApp)
        let result = check("tampered.xml", install: true)
        XCTAssertEqual(result.outcome, .errorAfterInstallChoice, "\(result.outcome)")
        XCTAssertFalse(result.reachedReadyToInstall)
        XCTAssertTrue(result.downloadStarted, "the update was downloaded before being refused")
        XCTAssertTrue(result.errorText?.contains(sparkleBadSignatureText) == true, "refusal is about the signature: \(result.errorText ?? "nil")")
        XCTAssertEqual(FixtureCheck.digest(of: hostApp), before)
    }

    /// Safety: the self-test never chooses install for an update whose signature is genuine. It would otherwise
    /// replace the app under test.
    func testAGenuineUpdateIsNeverInstalledByTheSelfTest_TC80() {
        let before = FixtureCheck.digest(of: hostApp)
        let result = check("newer.xml", install: true)
        guard case .installDeclined(let reason) = result.outcome else { return XCTFail("\(result.outcome)") }
        XCTAssertTrue(reason.contains("not tampered"), reason)
        XCTAssertFalse(result.downloadStarted)
        XCTAssertEqual(FixtureCheck.digest(of: hostApp), before)
        var output: [String] = []
        let status = SparkleSelfTest.runIntegration(feed: feed("newer.xml"), tamperedFeed: feed("newer.xml"),
                                                    hostBundle: Bundle(url: hostApp)!, output: { output.append($0) })
        XCTAssertEqual(status, 1, "a tampered feed that is not tampered fails the self-test")
        XCTAssertTrue(output.contains { $0.hasPrefix("FAIL altered-signature update is refused") && $0.contains("not tampered") }, "\(output)")
    }

    func testTheSelfTestEntryPointAgainstTheFixtureFeeds_TC71() {
        var output: [String] = []
        let status = SparkleSelfTest.runIntegration(feed: feed("newer.xml"), tamperedFeed: feed("tampered.xml"),
                                                    hostBundle: Bundle(url: hostApp)!, output: { output.append($0) })
        XCTAssertEqual(status, 0, output.joined(separator: "\n"))
        XCTAssertTrue(output.contains { $0.hasPrefix("PASS manual check completes (update available: 2.0)") }, "\(output)")
        XCTAssertTrue(output.contains { $0.hasPrefix("PASS host bundle is unchanged") })
    }

    func testTheSelfTestSkipsTheTamperedRunWhenNoTamperedFeedIsGiven() {
        var output: [String] = []
        _ = SparkleSelfTest.runIntegration(feed: feed("same.xml"), tamperedFeed: nil, hostBundle: Bundle(url: hostApp)!, output: { output.append($0) })
        XCTAssertTrue(output.contains { $0.hasPrefix("SKIP altered-signature update") })
    }
}
#endif
