import XCTest
@testable import LocalPlayer
@testable import PlayawayCore

/// Test-support helpers for the repository layout, shared by the update tests.
enum RepoLayout {
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static func url(_ relative: String) -> URL { root.appendingPathComponent(relative) }
    static func text(_ relative: String) -> String { (try? String(contentsOf: url(relative), encoding: .utf8)) ?? "" }
}

/// A valid-shaped 44-character base64 key (32 zero bytes). Not a real key.
let wellFormedTestKey = Data(count: 32).base64EncodedString()
let wellFormedTestFeed = "https://updates.example.test/appcast.xml"
let foreignProductKey = "rqIy/mx4aHQfqlexNM0vv6B+tHhHrCJy2sijyrmn450="

private func config(feed: String = wellFormedTestFeed, key: String = wellFormedTestKey, auto: Bool? = true) -> UpdateConfiguration {
    UpdateConfiguration(feedURL: feed, publicEDKey: key, automaticChecksEnabled: auto)
}

@MainActor
final class UpdateConfigurationTests: XCTestCase {
    func testValidConfigurationHasNoIssues_TC28() {
        XCTAssertEqual(wellFormedTestKey.count, 44)
        XCTAssertEqual(validate(config()), [])
    }

    func testFeedURLMissing_TC20() {
        XCTAssertEqual(validate(config(feed: "")), [.feedURLMissing])
        XCTAssertTrue(ConfigIssue.feedURLMissing.description.contains("SUFeedURL"))
        XCTAssertEqual(UpdateConfiguration.from(info: [:]).feedURL, "")
    }

    func testFeedURLMustBeHTTPS_TC21() {
        XCTAssertEqual(validate(config(feed: "http://updates.example.test/appcast.xml")), [.feedURLNotHTTPS])
        XCTAssertEqual(validate(config(feed: "ftp://updates.example.test/appcast.xml")), [.feedURLNotHTTPS])
    }

    func testFeedURLMustParse_TC22() {
        XCTAssertEqual(validate(config(feed: "not a url")), [.feedURLUnparsable])
        XCTAssertEqual(validate(config(feed: "appcast.xml")), [.feedURLUnparsable])
        XCTAssertEqual(validate(config(feed: "https://")), [.feedURLUnparsable])
    }

    func testEachPublicKeyProblemHasItsOwnIssue_TC23() {
        XCTAssertEqual(validate(config(key: "")), [.publicKeyMissing])
        XCTAssertEqual(validate(config(key: "   ")), [.publicKeyMissing])
        XCTAssertEqual(validate(config(key: "not base64 !!")), [.publicKeyNotBase64])
        let tenValidBase64 = "AAAAAAAAAA"
        XCTAssertEqual(tenValidBase64.count, 10)
        XCTAssertTrue(validate(config(key: tenValidBase64)).contains(.publicKeyTooShort))
        XCTAssertEqual(validate(config(key: "AAAAAAAA")), [.publicKeyTooShort])
        // Boundary: 12 base64 characters are long enough.
        XCTAssertEqual(validate(config(key: "AAAAAAAAAAAA")), [])
        for issue in [ConfigIssue.publicKeyMissing, .publicKeyNotBase64, .publicKeyTooShort] {
            XCTAssertTrue(issue.description.contains("SUPublicEDKey"))
        }
    }

    func testPlaceholdersAreRejected_TC24() {
        XCTAssertTrue(validate(config(feed: "https://PLACEHOLDER-FEED-HOST/appcast.xml")).contains(.feedURLPlaceholder))
        XCTAssertTrue(validate(config(key: "PLACEHOLDER-PUBLIC-ED-KEY")).contains(.publicKeyPlaceholder))
        XCTAssertTrue(validate(config(key: "placeholder")).contains(.publicKeyPlaceholder))
    }

    /// The repo carries placeholders until the owner decides the real values; while it does, the check rejects it.
    /// Once real values are set this test still holds: it only forbids a bad key or automatic checks being off.
    func testTheShippedInfoPlistNeverCarriesAForeignKeyOrDisablesAutomaticChecks_TC24() throws {
        let data = try Data(contentsOf: RepoLayout.url("Resources/Info.plist"))
        let info = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let configuration = UpdateConfiguration.from(info: info)
        let issues = validate(configuration)
        XCTAssertFalse(issues.contains(.automaticChecksNotEnabled), "SUEnableAutomaticChecks must be true")
        XCTAssertFalse(issues.contains(.publicKeyIsCutawayKey))
        if containsPlaceholder(configuration.feedURL) || containsPlaceholder(configuration.publicEDKey) {
            XCTAssertFalse(issues.isEmpty, "placeholder values must be rejected by the config check")
        } else {
            XCTAssertEqual(issues, [], "real values are set but invalid")
        }
    }

    func testForeignProductKeyIsRejected_TC25() {
        XCTAssertEqual(validate(config(key: foreignProductKey)), [.publicKeyIsCutawayKey])
    }

    func testAutomaticChecksMissingFalseOrNotBoolean_TC27() {
        XCTAssertEqual(validate(config(auto: nil)), [.automaticChecksNotEnabled])
        XCTAssertEqual(validate(config(auto: false)), [.automaticChecksNotEnabled])
        // A string "YES" in the plist is not a boolean and reads as nil.
        let info: [String: Any] = ["SUFeedURL": wellFormedTestFeed, "SUPublicEDKey": wellFormedTestKey, "SUEnableAutomaticChecks": "YES"]
        XCTAssertNil(UpdateConfiguration.from(info: info).automaticChecksEnabled)
        XCTAssertEqual(validate(UpdateConfiguration.from(info: info)), [.automaticChecksNotEnabled])
        XCTAssertTrue(ConfigIssue.automaticChecksNotEnabled.description.contains("SUEnableAutomaticChecks"))
    }

    func testEveryIssueHasADistinctMessage() {
        let all: [ConfigIssue] = [.feedURLMissing, .feedURLNotHTTPS, .feedURLUnparsable, .feedURLPlaceholder, .publicKeyMissing,
                                  .publicKeyNotBase64, .publicKeyTooShort, .publicKeyPlaceholder, .publicKeyIsCutawayKey,
                                  .automaticChecksNotEnabled]
        XCTAssertEqual(Set(all.map(\.description)).count, all.count)
    }

    // MARK: TC-26 Package.swift dependency

    func testPackageWithoutSparkleFails_TC26() {
        XCTAssertTrue(SparkleSelfTest.packageDeclaresSparkle(RepoLayout.text("Package.swift")))
        let without = RepoLayout.text("Package.swift").replacingOccurrences(of: "sparkle-project/Sparkle", with: "other/Thing")
        XCTAssertFalse(SparkleSelfTest.packageDeclaresSparkle(without))
        let noTarget = RepoLayout.text("Package.swift").replacingOccurrences(of: "\"Sparkle\"", with: "\"Other\"")
        XCTAssertFalse(SparkleSelfTest.packageDeclaresSparkle(noTarget))
    }

    // MARK: TC-45 debug-only override

    func testOverrideHonouredOnlyInDebug_TC45() {
        let environment = ["LOCALPLAYER_TEST_FEED_URL": "http://127.0.0.1:9/appcast.xml"]
        XCTAssertNil(FeedURLOverride.resolve(environment: environment, debugBuild: false))
        XCTAssertNil(FeedURLOverride.resolve(environment: [:], debugBuild: true))
        #if DEBUG
        XCTAssertTrue(FeedURLOverride.isDebugBuild)
        XCTAssertEqual(FeedURLOverride.resolve(environment: environment, debugBuild: true), "http://127.0.0.1:9/appcast.xml")
        #endif
    }

    func testOverrideNameIsCompiledOutOfSourceInRelease_TC45() throws {
        // The variable name may appear only between `#if DEBUG` and `#else`/`#endif`, in one file.
        let lines = RepoLayout.text("Sources/LocalPlayer/Updates/UpdateConfiguration.swift").components(separatedBy: "\n")
        var debugDepth = 0
        var found = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "#if DEBUG" { debugDepth += 1 }
            if trimmed == "#else" || trimmed == "#endif" { debugDepth = max(0, debugDepth - 1) }
            if line.contains("LOCALPLAYER_TEST_FEED_URL") && !trimmed.hasPrefix("//") {
                found += 1
                XCTAssertGreaterThan(debugDepth, 0, "override name is outside #if DEBUG: \(line)")
            }
        }
        XCTAssertEqual(found, 1)
        for path in sourceFiles(under: "Sources") where !path.hasSuffix("UpdateConfiguration.swift") {
            XCTAssertFalse(RepoLayout.text(path).contains("LOCALPLAYER_TEST_FEED_URL"), "\(path) mentions the override")
        }
    }

    func testBuiltBinariesAgreeAboutTheOverride_TC45() throws {
        let debugBinary = RepoLayout.url(".build/debug/LocalPlayer")
        let releaseBinary = RepoLayout.url(".build/release/LocalPlayer")
        guard FileManager.default.fileExists(atPath: debugBinary.path) else { throw XCTSkip("no debug binary built") }
        XCTAssertTrue(binaryContains(debugBinary, "LOCALPLAYER_TEST_FEED_URL"), "positive control: debug binary has the override")
        guard FileManager.default.fileExists(atPath: releaseBinary.path) else {
            throw XCTSkip("no release binary at .build/release/LocalPlayer; run `swift build -c release` to exercise this")
        }
        XCTAssertFalse(binaryContains(releaseBinary, "LOCALPLAYER_TEST_FEED_URL"), "release binary must not contain the override")
    }

    // MARK: TC-85 / TC-86 style checks

    /// Values that belong to another product and must never appear in this repository's files, apart from the
    /// deny-list entries that reject them. The owner's own GitHub organisation and the Cloudflare Pages domain are
    /// shared by every product of the owner and are not another product's values (owner decision 2026-10-17: host
    /// Playaway's updates the way Cutaway's are hosted, on a Pages project of its own).
    private let foreignValues = [foreignProductKey, "cutaway-updates", "getcutaway", "screencap.sh"]
    private let denyListFiles = ["Sources/LocalPlayer/Updates/UpdateConfiguration.swift", "scripts/release.sh"]
    private let selfFiles = ["Tests/LocalPlayerTests/UpdateConfigurationTests.swift"]

    func testNoOtherProductKeyFeedOrHostingNamesInRepoFiles_TC85() {
        let files = sourceFiles(under: "Sources") + sourceFiles(under: "Resources") + sourceFiles(under: "scripts")
            + sourceFiles(under: "Tests/LocalPlayerTests") + ["Package.swift"]
        XCTAssertGreaterThan(files.count, 10)
        for path in files where !selfFiles.contains(path) {
            let text = RepoLayout.text(path)
            for value in foreignValues {
                if value == foreignProductKey && denyListFiles.contains(path) { continue }
                XCTAssertFalse(text.contains(value), "\(path) contains another product's value '\(value)'")
            }
        }
    }

    // MARK: helpers

    private func sourceFiles(under directory: String) -> [String] {
        let base = RepoLayout.url(directory)
        guard let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        let textExtensions: Set<String> = ["swift", "sh", "plist", "xml", "entitlements", "sdef", "json", "md"]
        var result: [String] = []
        for case let url as URL in enumerator where textExtensions.contains(url.pathExtension) {
            if url.path.contains("/.build/") { continue }
            result.append(String(url.path.dropFirst(RepoLayout.root.path.count + 1)))
        }
        return result
    }

    private func binaryContains(_ url: URL, _ needle: String) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
        return data.range(of: Data(needle.utf8)) != nil
    }
}
