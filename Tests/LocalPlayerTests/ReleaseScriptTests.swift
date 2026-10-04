import CryptoKit
import XCTest

/// Runs a script and captures its combined output.
enum ScriptRunner {
    struct Result { let status: Int32; let output: String }

    static func run(_ path: String, arguments: [String], environment: [String: String], cwd: URL? = nil) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        if let cwd { process.currentDirectoryURL = cwd }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}

/// A temp copy of the scripts and the files they read, plus recording shims that stand in for every tool that
/// would reach the outside world. Nothing here talks to Apple's notary service, a host or GitHub.
final class ScriptWorkspace {
    let root: URL
    let shims: URL
    let logs: URL
    let buildDir: URL
    let outputDir: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        root = base.appendingPathComponent("scripts-\(UUID().uuidString)")
        shims = root.appendingPathComponent("shims")
        logs = root.appendingPathComponent("logs")
        buildDir = root.appendingPathComponent("build-products")
        outputDir = root.appendingPathComponent("out")
        let fm = FileManager.default
        for directory in [root, shims, logs, buildDir, outputDir] { try fm.createDirectory(at: directory, withIntermediateDirectories: true) }
        try fm.copyItem(at: RepoLayout.url("scripts"), to: root.appendingPathComponent("scripts"))
        try fm.copyItem(at: RepoLayout.url("Resources"), to: root.appendingPathComponent("Resources"))
        try fm.copyItem(at: RepoLayout.url("Package.swift"), to: root.appendingPathComponent("Package.swift"))
        try writeShims()
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    var infoPlist: URL { root.appendingPathComponent("Resources/Info.plist") }
    var script: (String) -> String { { self.root.appendingPathComponent("scripts/\($0)").path } }
    func shim(_ name: String) -> String { shims.appendingPathComponent(name).path }
    func log(_ name: String) -> String { (try? String(contentsOf: logs.appendingPathComponent(name + ".log"), encoding: .utf8)) ?? "" }
    func logLines(_ name: String) -> [String] { log(name).split(separator: "\n").map(String.init) }

    func setPlist(_ key: String, _ value: String) throws {
        let r = try ScriptRunner.run("/usr/libexec/PlistBuddy", arguments: ["-c", "Set :\(key) \(value)", infoPlist.path], environment: [:])
        XCTAssertEqual(r.status, 0, r.output)
    }

    func plistValue(_ key: String) throws -> String {
        try ScriptRunner.run("/usr/libexec/PlistBuddy", arguments: ["-c", "Print :\(key)", infoPlist.path], environment: [:])
            .output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Replaces the repo's placeholders with obviously fake test values so the release script can run.
    func fillPlaceholders() throws {
        try setPlist("SUFeedURL", "https://updates.example.test/appcast.xml")
        try setPlist("SUPublicEDKey", wellFormedTestKey)
    }

    /// The tool and release-environment variables every script test uses.
    func environment(_ extra: [String: String] = [:]) -> [String: String] {
        var env: [String: String] = [
            "SWIFT_CMD": shim("swift"), "SECURITY_CMD": shim("security"), "NOTARYTOOL_CMD": shim("notarytool"),
            "STAPLER_CMD": shim("stapler"), "SPCTL_CMD": shim("spctl"), "CODESIGN_CMD": shim("codesign"),
            "GIT_CMD": shim("git"), "GH_CMD": shim("gh"), "WRANGLER_CMD": shim("wrangler"),
            "BUILD_DIR": buildDir.path, "OUTPUT_DIR": outputDir.path, "ALLOW_SINGLE_ARCH": "1",
            "STAPLE_RETRY_DELAY_SECONDS": "0", "LOG_DIR": logs.path,
            "HOSTING_PROJECT": "example-hosting-project", "RELEASE_REPO": "example-owner/example-repo",
            "NOTARY_PROFILE": "example-notary-profile", "APPCAST_DIR": root.appendingPathComponent("appcast-site").path,
            "BUILD_SCRIPT": script("build-app.sh"),
        ]
        env.merge(extra) { _, new in new }
        return env
    }

    private func writeShims() throws {
        func make(_ name: String, _ body: String) throws {
            let url = shims.appendingPathComponent(name)
            try ("#!/bin/bash\n" + body).write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        let record = "echo \"$@\" >> \"$LOG_DIR/$(basename \"$0\").log\"\n"
        try make("swift", record + "exit 0\n")
        try make("git", record + "exit 0\n")
        try make("gh", record + "echo https://example.test/release\nexit 0\n")
        try make("wrangler", record + "[[ \"${WRANGLER_FAIL:-0}\" == 1 ]] && { echo 'deploy failed' >&2; exit 1; }\nexit 0\n")
        try make("spctl", record + "exit 0\n")
        try make("security", record + "echo \"${SECURITY_OUTPUT:-     0 valid identities found}\"\n")
        // notarytool: NOTARY_MODE = accept (default) | reject (exit 0, status Invalid) | error (exit 1)
        try make("notarytool", record + """
        case "${NOTARY_MODE:-accept}" in
          accept) printf 'Processing complete\\n  id: 11111111-2222-3333-4444-555555555555\\n  status: Accepted\\n' ;;
          reject) printf 'Processing complete\\n  id: 11111111-2222-3333-4444-555555555555\\n  status: Invalid\\n' ;;
          error)  echo 'Error: could not reach the service' >&2; exit 1 ;;
        esac

        """)
        // stapler: the first STAPLER_FAILS "staple" calls fail
        try make("stapler", record + """
        if [[ "$1" == "staple" ]]; then
          counter="$LOG_DIR/stapler.count"; n=$(cat "$counter" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "$counter"
          if [[ $n -le ${STAPLER_FAILS:-0} ]]; then echo 'staple failed' >&2; exit 1; fi
        fi
        exit 0

        """)
        // codesign: records the original arguments, then runs the real tool with the network timestamp turned off.
        try make("codesign", record + """
        args=(); for a in "$@"; do if [[ "$a" == "--timestamp" ]]; then args+=("--timestamp=none"); else args+=("$a"); fi; done
        exec /usr/bin/codesign "${args[@]}"

        """)
    }

    /// Puts a real (debug) build of the app and Sparkle where `swift build` would have left them.
    func stageBuildProducts() throws {
        let debug = RepoLayout.url(".build/debug")
        let binary = debug.appendingPathComponent("LocalPlayer")
        let framework = debug.appendingPathComponent("Sparkle.framework")
        guard FileManager.default.fileExists(atPath: binary.path), FileManager.default.fileExists(atPath: framework.path) else {
            throw XCTSkip("no debug build products in .build/debug; run `swift build` first")
        }
        try FileManager.default.copyItem(at: binary, to: buildDir.appendingPathComponent("LocalPlayer"))
        try FileManager.default.copyItem(at: framework, to: buildDir.appendingPathComponent("Sparkle.framework"))
    }
}

private let adHocIdentity = "-"

final class BuildScriptTests: XCTestCase {
    private func build(_ workspace: ScriptWorkspace, flags: [String] = ["--no-launch"], extra: [String: String] = [:]) throws -> ScriptRunner.Result {
        try ScriptRunner.run(workspace.script("build-app.sh"), arguments: flags, environment: workspace.environment(extra))
    }

    func testSignedBundleVerifiesDeepStrictWithHardenedRuntimeEverywhere_TC50() throws {
        let w = try ScriptWorkspace()
        try w.stageBuildProducts()
        let result = try build(w, extra: ["SIGNING_IDENTITY": adHocIdentity])
        XCTAssertEqual(result.status, 0, result.output)

        let app = w.outputDir.appendingPathComponent("LocalPlayer.app")
        let verify = try ScriptRunner.run("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", app.path], environment: [:])
        XCTAssertEqual(verify.status, 0, verify.output)

        // Every Mach-O file, XPC service, nested app, the framework and the app carry the hardened-runtime flag.
        var signedTargets = 0
        var unsigned: [String] = []
        let enumerator = FileManager.default.enumerator(at: app, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])!
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { continue }
            let isBundle = ["xpc", "app", "framework"].contains(url.pathExtension)
            guard isBundle || (values.isRegularFile == true && isMachO(url)) else { continue }
            signedTargets += 1
            let info = try ScriptRunner.run("/usr/bin/codesign", arguments: ["-d", "--verbose=2", url.path], environment: [:]).output
            if !info.contains("runtime") { unsigned.append(url.lastPathComponent) }
        }
        XCTAssertGreaterThan(signedTargets, 5, "expected Sparkle's nested helpers to be found")
        XCTAssertEqual(unsigned, [], "targets without the hardened runtime flag")

        // Entitlements were applied to the app.
        let entitlements = try ScriptRunner.run("/usr/bin/codesign", arguments: ["-d", "--entitlements", "-", app.path], environment: [:]).output
        XCTAssertTrue(entitlements.contains("com.apple.security.network.client"), entitlements)
        XCTAssertFalse(entitlements.contains("com.apple.security.app-sandbox"))

        // Inside-out order and the secure timestamp flag, from the recorded codesign calls.
        let calls = w.logLines("codesign").filter { $0.contains("--sign") }
        let signing = calls.filter { $0.contains("--options runtime") }
        XCTAssertFalse(signing.isEmpty)
        XCTAssertTrue(signing.allSatisfy { $0.contains("--timestamp") }, "secure timestamp requested on every signature")
        XCTAssertTrue(signing.last?.hasSuffix("LocalPlayer.app") == true, "the app is signed last")
        let frameworkIndex = signing.firstIndex { $0.hasSuffix("Sparkle.framework") }
        let nestedIndex = signing.firstIndex { $0.contains(".xpc") || $0.contains("Autoupdate") }
        XCTAssertNotNil(frameworkIndex)
        XCTAssertNotNil(nestedIndex)
        if let frameworkIndex, let nestedIndex { XCTAssertLessThan(nestedIndex, frameworkIndex, "nested code is signed before the framework") }
    }

    func testAScriptingGapStopsTheBuildBeforeAnythingIsSigned_TC66() throws {
        let w = try ScriptWorkspace()
        try w.stageBuildProducts()
        let sdef = w.root.appendingPathComponent("Resources/LocalPlayer.sdef")
        guard FileManager.default.fileExists(atPath: sdef.path) else { throw XCTSkip("workspace has no sdef") }
        let gapped = try String(contentsOf: sdef, encoding: .utf8).replacingOccurrences(of: "<command name=\"seek\"", with: "<command name=\"seek-removed\"")
        try gapped.write(to: sdef, atomically: true, encoding: .utf8)
        let result = try build(w, extra: ["SIGNING_IDENTITY": adHocIdentity])
        XCTAssertNotEqual(result.status, 0, "a release with an unscriptable action must not build")
        XCTAssertTrue(result.output.contains("action 'seek' has no scripting command"), result.output)
        XCTAssertTrue(w.logLines("codesign").filter { $0.contains("--options runtime") }.isEmpty, "nothing was signed for release")
        XCTAssertFalse(FileManager.default.fileExists(atPath: w.outputDir.appendingPathComponent("LocalPlayer.dmg").path))
    }

    func testNoDeveloperIDIdentityAbortsBeforeBuilding_TC51() throws {
        let w = try ScriptWorkspace()
        try w.stageBuildProducts()
        let result = try build(w, extra: ["SECURITY_OUTPUT": "     0 valid identities found"])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("Developer ID Application"), result.output)
        XCTAssertEqual(w.log("swift"), "", "nothing was built")
        XCTAssertFalse(FileManager.default.fileExists(atPath: w.outputDir.appendingPathComponent("LocalPlayer.app").path))
    }

    func testRejectedNotarizationFailsAndPrintsHowToFetchTheLog_TC52() throws {
        let w = try ScriptWorkspace()
        try w.stageBuildProducts()
        // notarytool exiting 0 with status Invalid, and exiting non-zero, both fail the build.
        for mode in ["reject", "error"] {
            let result = try build(w, extra: ["SIGNING_IDENTITY": adHocIdentity, "NOTARY_MODE": mode])
            XCTAssertNotEqual(result.status, 0, "\(mode): \(result.output)")
            XCTAssertTrue(result.output.contains("notarytool log"), "\(mode): \(result.output)")
            XCTAssertTrue(result.output.contains("example-notary-profile"))
            XCTAssertEqual(w.log("stapler"), "", "nothing is stapled after a rejection")
        }
        let rejected = try build(w, extra: ["SIGNING_IDENTITY": adHocIdentity, "NOTARY_MODE": "reject"])
        XCTAssertTrue(rejected.output.contains("11111111-2222-3333-4444-555555555555"), "submission id is shown")
    }

    func testStaplingRetriedOnceThenSucceeds_TC53() throws {
        let w = try ScriptWorkspace()
        try w.stageBuildProducts()
        let result = try build(w, extra: ["SIGNING_IDENTITY": adHocIdentity, "STAPLER_FAILS": "1"])
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("retrying"))
        XCTAssertEqual(w.logLines("stapler").filter { $0.hasPrefix("staple") }.count, 3, "app twice, DMG once")
        XCTAssertTrue(FileManager.default.fileExists(atPath: w.outputDir.appendingPathComponent("LocalPlayer-\(try w.plistValue("CFBundleShortVersionString")).dmg").path))
    }

    func testStaplingFailingTwiceFailsTheBuild_TC54() throws {
        let w = try ScriptWorkspace()
        try w.stageBuildProducts()
        let result = try build(w, extra: ["SIGNING_IDENTITY": adHocIdentity, "STAPLER_FAILS": "2"])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("Stapling failed after retry"), result.output)
        XCTAssertEqual(w.logLines("stapler").filter { $0.hasPrefix("staple") }.count, 2, "exactly one retry")
    }

    func testSandboxEntitlementAbortsTheBuild_TC55() throws {
        let w = try ScriptWorkspace()
        try w.stageBuildProducts()
        let bad = w.root.appendingPathComponent("bad.entitlements")
        let body = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>com.apple.security.app-sandbox</key><true/></dict></plist>"
        try body.write(to: bad, atomically: true, encoding: .utf8)
        let result = try build(w, extra: ["SIGNING_IDENTITY": adHocIdentity, "ENTITLEMENTS_FILE": bad.path])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("must not be sandboxed"), result.output)
        XCTAssertEqual(w.log("swift"), "", "aborted before building")
        // The test mode alone reports the same, and the repository's real entitlements pass.
        XCTAssertNotEqual(try build(w, flags: ["--test-entitlements"], extra: ["ENTITLEMENTS_FILE": bad.path]).status, 0)
        XCTAssertEqual(try build(w, flags: ["--test-entitlements"]).status, 0)
    }

    func testRepositoryEntitlementsAreNotSandboxed() throws {
        let text = RepoLayout.text("Resources/LocalPlayer.entitlements")
        XCTAssertFalse(text.contains("app-sandbox"))
    }

    func testSkipNotarizeNeverCallsTheNotaryService() throws {
        let w = try ScriptWorkspace()
        try w.stageBuildProducts()
        let result = try build(w, flags: ["--skip-notarize", "--no-launch"], extra: ["SIGNING_IDENTITY": adHocIdentity, "NOTARY_PROFILE": ""])
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertEqual(w.log("notarytool"), "")
        XCTAssertEqual(w.log("stapler"), "")
    }

    func testBinaryThatIsNotUniversalIsRejected() throws {
        let w = try ScriptWorkspace()
        try w.stageBuildProducts()
        let result = try build(w, extra: ["SIGNING_IDENTITY": adHocIdentity, "ALLOW_SINGLE_ARCH": "0"])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("not universal"), result.output)
    }

    func testBuildAsksSwiftForAUniversalReleaseBuild() throws {
        let w = try ScriptWorkspace()
        try w.stageBuildProducts()
        _ = try build(w, extra: ["SIGNING_IDENTITY": adHocIdentity])
        XCTAssertEqual(w.logLines("swift"), ["build -c release --arch arm64 --arch x86_64"], "BUILD_DIR is preset, so the bin path is not asked for")
    }

    private func isMachO(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4), data.count == 4 else { return false }
        let magic = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        return [0xfeedfacf, 0xcffaedfe, 0xcafebabe, 0xbebafeca].contains(magic)
    }
}

final class ReleaseScriptTests: XCTestCase {
    /// A key pair generated for the test run; the private key never leaves the temp directory.
    private func makeKeyFile(in w: ScriptWorkspace) throws -> (path: String, publicKey: String) {
        let key = Curve25519.Signing.PrivateKey()
        let path = w.root.appendingPathComponent("test-sparkle.key")
        try key.rawRepresentation.base64EncodedString().write(to: path, atomically: true, encoding: .utf8)
        return (path.path, key.publicKey.rawRepresentation.base64EncodedString())
    }

    private var realSignUpdate: String { RepoLayout.url(".build/artifacts/sparkle/Sparkle/bin/sign_update").path }

    /// A stand-in for build-app.sh that writes a DMG of known size under the version in the (bumped) Info.plist.
    private func installFakeBuild(_ w: ScriptWorkspace, fail: Bool = false) throws -> String {
        let path = w.shims.appendingPathComponent("fake-build.sh")
        let body = """
        #!/bin/bash
        echo "$@" >> "$LOG_DIR/build.log"
        \(fail ? "echo 'build failed' >&2; exit 1" : "")
        version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$(dirname "$0")/../Resources/Info.plist")
        head -c 70001 /dev/urandom > "$OUTPUT_DIR/LocalPlayer-${version}.dmg"

        """
        try body.write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
        return path.path
    }

    private func release(_ w: ScriptWorkspace, _ arguments: [String] = [], extra: [String: String] = [:]) throws -> ScriptRunner.Result {
        try ScriptRunner.run(w.script("release.sh"), arguments: arguments, environment: w.environment(extra))
    }

    private func readyWorkspace(failBuild: Bool = false, signer: String? = nil) throws -> (ScriptWorkspace, [String: String]) {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: realSignUpdate), "Sparkle sign_update not resolved; run `swift package resolve`")
        let w = try ScriptWorkspace()
        try w.fillPlaceholders()
        let keys = try makeKeyFile(in: w)
        let build = try installFakeBuild(w, fail: failBuild)
        // The HIG review is its own gate (tested below with the real checker); other release tests pass it through.
        let hig = w.shims.appendingPathComponent("hig-ok")
        try "#!/bin/bash\nexit 0\n".write(to: hig, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hig.path)
        return (w, ["BUILD_SCRIPT": build, "SIGN_UPDATE": signer ?? realSignUpdate, "SPARKLE_KEY_FILE": keys.path, "CHECK_HIG": hig.path])
    }

    // MARK: the recorded HIG review gates the release (prd.look.review)

    private var realCheckHIG: String { packageRoot.appendingPathComponent("scripts/check-hig.sh").path }

    private func writeChecklist(_ lines: [String], in w: ScriptWorkspace) throws -> String {
        let url = w.root.appendingPathComponent("hig-checklist.md")
        try (["# HIG checklist"] + lines).joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    func testAnUnmarkedChecklistItemRefusesTheReleaseBeforeAnythingIsBuiltOrPublished() throws {
        let (w, env) = try readyWorkspace()
        let checklist = try writeChecklist(["- [system-controls] pass: TC-32", "- [menu-bar] unmarked"], in: w)
        let before = try w.plistValue("CFBundleShortVersionString")
        let result = try release(w, [], extra: env.merging(["CHECK_HIG": realCheckHIG, "HIG_CHECKLIST": checklist]) { _, n in n })
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("menu-bar"), "names the item: \(result.output)")
        XCTAssertEqual(w.log("build"), "")
        XCTAssertEqual(publishCalls(w), [])
        XCTAssertEqual(try w.plistValue("CFBundleShortVersionString"), before)
    }

    func testAFailWithoutAnExceptionRefusesTheRelease() throws {
        let (w, env) = try readyWorkspace()
        let checklist = try writeChecklist(["- [glass-use] fail"], in: w)
        let result = try release(w, [], extra: env.merging(["CHECK_HIG": realCheckHIG, "HIG_CHECKLIST": checklist]) { _, n in n })
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("glass-use"), result.output)
        XCTAssertEqual(publishCalls(w), [])
    }

    func testAFullyMarkedChecklistLetsTheReleaseProceed() throws {
        let (w, env) = try readyWorkspace()
        let checklist = try writeChecklist(["- [system-controls] pass: TC-32", "- [glass-use] exception: surfaces undecided (open question 1)"], in: w)
        let result = try release(w, [], extra: env.merging(["CHECK_HIG": realCheckHIG, "HIG_CHECKLIST": checklist]) { _, n in n })
        XCTAssertEqual(result.status, 0, result.output)
    }

    func testTheShippedChecklistCurrentlyRefusesTheReleaseBecauseNothingIsSignedOffYet() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: realCheckHIG)
        process.arguments = [packageRoot.appendingPathComponent("docs/hig-checklist.md").path]
        let out = Pipe(); process.standardOutput = out; process.standardError = out
        try process.run(); process.waitUntilExit()
        XCTAssertNotEqual(process.terminationStatus, 0, "every item is unmarked on purpose until a reviewer signs off")
    }

    private let publishVerbs = ["pages deploy", "tag", "push", "release create", "commit"]
    private func publishCalls(_ w: ScriptWorkspace) -> [String] {
        w.logLines("wrangler") + w.logLines("gh") + w.logLines("git").filter { !$0.contains("status --porcelain") }
    }

    // MARK: version selection

    func testNoVersionIncrementsTheLastComponent_TC63() throws {
        let w = try ScriptWorkspace()
        let cases = [("1.0", "1.1"), ("1.2.3", "1.2.4"), ("1", "1.1"), ("2.9", "2.10"), ("1.0.9", "1.0.10")]
        for (current, expected) in cases {
            try w.setPlist("CFBundleShortVersionString", current)
            let result = try release(w, ["--print-version"])
            XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), expected, "from \(current)")
        }
    }

    func testExplicitVersionIsUsedExactly_TC64() throws {
        let w = try ScriptWorkspace()
        for version in ["3.0", "7", "1.2.3", "10.20.30"] {
            let result = try release(w, ["--print-version", version])
            XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), version)
        }
    }

    func testEmptyAndMalformedVersionsAreRejected() throws {
        let w = try ScriptWorkspace()
        for bad in ["", "abc", "1.2.3.4", "1..2", "v1.2", "1.2-beta"] {
            let result = try release(w, ["--print-version", bad])
            XCTAssertNotEqual(result.status, 0, "'\(bad)' accepted")
            XCTAssertTrue(result.output.contains("malformed version"), result.output)
        }
        try w.setPlist("CFBundleShortVersionString", "beta")
        XCTAssertNotEqual(try release(w, ["--print-version"]).status, 0)
    }

    // MARK: failure ordering

    func testRepoPlaceholdersBlockTheReleaseBeforeAnything_TC86() throws {
        let w = try ScriptWorkspace()   // plist still carries the repo's placeholders
        let script = try release(w, [], extra: ["HOSTING_PROJECT": "PLACEHOLDER_HOSTING_PROJECT", "RELEASE_REPO": "PLACEHOLDER_RELEASE_REPO"])
        XCTAssertNotEqual(script.status, 0)
        XCTAssertTrue(script.output.contains("placeholder values remain"), script.output)
        for name in ["HOSTING_PROJECT", "RELEASE_REPO", "SUFeedURL", "SUPublicEDKey"] { XCTAssertTrue(script.output.contains(name), script.output) }
        XCTAssertEqual(w.log("swift") + w.log("git") + w.log("gh") + w.log("wrangler") + w.log("build"), "")
    }

    func testOnlyHostingPlaceholdersRemainingStillBlocks_TC86() throws {
        let (w, env) = try readyWorkspace()
        var result = try release(w, [], extra: env.merging(["HOSTING_PROJECT": "PLACEHOLDER_HOSTING_PROJECT"]) { _, n in n })
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("HOSTING_PROJECT"))
        result = try release(w, [], extra: env.merging(["RELEASE_REPO": "PLACEHOLDER_RELEASE_REPO"]) { _, n in n })
        XCTAssertNotEqual(result.status, 0)
        XCTAssertEqual(publishCalls(w), [])
        XCTAssertEqual(w.log("build"), "")
    }

    func testMinimumOSMismatchAbortsAtTheFirstStepNamingTheFile_TC22() throws {
        let sources: [(String, (ScriptWorkspace) throws -> Void)] = [
            ("FAIL appcast", { w in
                let url = w.root.appendingPathComponent("scripts/appcast-template.xml")
                try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "26.0</sparkle", with: "13.0</sparkle").write(to: url, atomically: true, encoding: .utf8)
            }),
            ("FAIL Info.plist", { w in try w.setPlist("LSMinimumSystemVersion", "15.0") }),
            ("FAIL Package.swift", { w in
                let url = w.root.appendingPathComponent("Package.swift")
                try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: ".macOS(.v26)", with: ".macOS(.v15)").write(to: url, atomically: true, encoding: .utf8)
            }),
        ]
        for (expected, mutate) in sources {
            let (w, env) = try readyWorkspace()
            try mutate(w)
            let before = try w.plistValue("CFBundleShortVersionString")
            let result = try release(w, [], extra: env)
            XCTAssertNotEqual(result.status, 0, expected)
            XCTAssertTrue(result.output.contains(expected), result.output)
            XCTAssertEqual(w.log("build"), "", "aborted before building")
            XCTAssertEqual(publishCalls(w), [], "nothing published")
            XCTAssertEqual(try w.plistValue("CFBundleShortVersionString"), before, "version not bumped")
        }
    }

    func testEmptySignatureAbortsBeforeAnyPublishStep_TC60() throws {
        let (w, env) = try readyWorkspace()
        let emptySigner = w.shims.appendingPathComponent("empty-sign-update")
        try "#!/bin/bash\nexit 0\n".write(to: emptySigner, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: emptySigner.path)
        let before = try w.plistValue("CFBundleShortVersionString")
        let result = try release(w, [], extra: env.merging(["SIGN_UPDATE": emptySigner.path]) { _, n in n })
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("empty EdDSA signature"), result.output)
        XCTAssertEqual(publishCalls(w), [])
        XCTAssertEqual(try w.plistValue("CFBundleShortVersionString"), before, "version bump is undone after a failure")
        XCTAssertFalse(FileManager.default.fileExists(atPath: w.root.appendingPathComponent("appcast-site/appcast.xml").path))
    }

    func testBuildFailureAbortsBeforeAnyPublishStep() throws {
        let (w, env) = try readyWorkspace(failBuild: true)
        let before = try w.plistValue("CFBundleShortVersionString")
        let result = try release(w, [], extra: env)
        XCTAssertNotEqual(result.status, 0)
        XCTAssertEqual(publishCalls(w), [])
        XCTAssertEqual(try w.plistValue("CFBundleShortVersionString"), before)
    }

    func testFailedDeployCreatesNoTagAndNoRelease_TC62() throws {
        let (w, env) = try readyWorkspace()
        let before = try w.plistValue("CFBundleShortVersionString")
        let result = try release(w, [], extra: env.merging(["WRANGLER_FAIL": "1"]) { _, n in n })
        XCTAssertNotEqual(result.status, 0)
        XCTAssertEqual(w.logLines("wrangler").count, 1, "the deploy was attempted")
        XCTAssertEqual(w.log("gh"), "", "no release created")
        let git = w.logLines("git")
        XCTAssertFalse(git.contains { $0.contains(" tag ") || $0.hasPrefix("tag") || $0.contains("push") || $0.contains("commit") }, "\(git)")
        XCTAssertEqual(try w.plistValue("CFBundleShortVersionString"), before)
    }

    // MARK: success path

    func testSuccessfulReleasePublishesInOrderWithAGoodAppcast_TC61_TC65() throws {
        let (w, env) = try readyWorkspace()
        try w.setPlist("CFBundleShortVersionString", "1.0")
        let result = try release(w, [], extra: env)
        XCTAssertEqual(result.status, 0, result.output)

        // Order: deploy, then commit, tag, push, push tags, then the GitHub release.
        let wrangler = w.logLines("wrangler")
        XCTAssertEqual(wrangler.count, 1)
        XCTAssertTrue(wrangler[0].contains("pages deploy"))
        XCTAssertTrue(wrangler[0].contains("--project-name example-hosting-project"))
        let git = w.logLines("git").filter { !$0.contains("status") }
        XCTAssertTrue(git.contains { $0.contains("tag v1.1") })
        XCTAssertTrue(git.contains { $0.hasSuffix("push") })
        XCTAssertTrue(git.contains { $0.hasSuffix("push --tags") })
        XCTAssertTrue(git.contains { $0.contains("commit -m Bump version to 1.1") })
        XCTAssertTrue(w.logLines("gh").first?.hasPrefix("release create v1.1") == true)
        XCTAssertTrue(w.logLines("gh").first?.contains("LocalPlayer-1.1.dmg") == true)
        XCTAssertEqual(try w.plistValue("CFBundleShortVersionString"), "1.1")
        XCTAssertEqual(try w.plistValue("CFBundleVersion"), "1.1")

        // The appcast item.
        let appcastURL = w.root.appendingPathComponent("appcast-site/appcast.xml")
        let appcast = try String(contentsOf: appcastURL, encoding: .utf8)
        XCTAssertTrue(appcast.contains("<sparkle:version>1.1</sparkle:version>"))
        XCTAssertTrue(appcast.contains("<sparkle:shortVersionString>1.1</sparkle:shortVersionString>"))
        XCTAssertTrue(appcast.contains("<sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>"))
        XCTAssertTrue(appcast.contains("url=\"https://github.com/example-owner/example-repo/releases/download/v1.1/LocalPlayer-1.1.dmg\""))
        let dmg = w.outputDir.appendingPathComponent("LocalPlayer-1.1.dmg")
        let size = (try FileManager.default.attributesOfItem(atPath: dmg.path)[.size] as! NSNumber).intValue
        XCTAssertEqual(size, 70001)
        XCTAssertTrue(appcast.contains("length=\"\(size)\""), "length must equal the real DMG byte length")
        let signature = try XCTUnwrap(appcast.range(of: "sparkle:edSignature=\"([^\"]+)\"", options: .regularExpression).map { String(appcast[$0]) })
        XCTAssertFalse(signature.contains("@"), "no template field left unfilled")
        XCTAssertFalse(appcast.contains("@"), appcast)

        // The signature in the appcast verifies against the key the test generated.
        let keyFile = try String(contentsOfFile: env["SPARKLE_KEY_FILE"]!, encoding: .utf8)
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: XCTUnwrap(Data(base64Encoded: keyFile)))
        let value = signature.replacingOccurrences(of: "sparkle:edSignature=\"", with: "").dropLast()
        let signatureData = try XCTUnwrap(Data(base64Encoded: String(value)))
        XCTAssertTrue(privateKey.publicKey.isValidSignature(signatureData, for: try Data(contentsOf: dmg)))

        let lint = try ScriptRunner.run("/usr/bin/xmllint", arguments: ["--noout", appcastURL.path], environment: [:])
        XCTAssertEqual(lint.status, 0, lint.output)
    }

    func testExplicitVersionIsReleased_TC64() throws {
        let (w, env) = try readyWorkspace()
        let result = try release(w, ["4.2"], extra: env)
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(w.logLines("gh").first?.hasPrefix("release create v4.2") == true)
        XCTAssertTrue(try String(contentsOf: w.root.appendingPathComponent("appcast-site/appcast.xml"), encoding: .utf8).contains("<sparkle:version>4.2</sparkle:version>"))
    }

    func testNothingAboutThePlayerIsSentToAnyPublishTool_TC84() throws {
        let (w, env) = try readyWorkspace()
        let result = try release(w, [], extra: env)
        XCTAssertEqual(result.status, 0, result.output)
        let everything = (w.log("wrangler") + w.log("gh") + w.log("git")).lowercased()
        for word in [".mp3", ".flac", ".lplaylist", "playlist"] { XCTAssertFalse(everything.contains(word), word) }
    }
}
