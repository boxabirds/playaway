import XCTest

/// Runs scripts/check-min-os.sh against temp copies of the three sources (updates.version.consistency).
final class MinOSConsistencyTests: XCTestCase {
    private var directory: URL!
    private var appcast: URL { directory.appendingPathComponent("appcast-template.xml") }
    private var plist: URL { directory.appendingPathComponent("Info.plist") }
    private var package: URL { directory.appendingPathComponent("Package.swift") }

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("minos-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write(appcast: "26.0", plist: "26.0", package: ".macOS(.v26)")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: directory) }

    private func write(appcast: String?, plist: String?, package: String?) throws {
        if let appcast {
            try "<rss><channel><item>\n<sparkle:minimumSystemVersion>\(appcast)</sparkle:minimumSystemVersion>\n</item></channel></rss>"
                .write(to: self.appcast, atomically: true, encoding: .utf8)
        }
        if let plist {
            let body = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>LSMinimumSystemVersion</key><string>\(plist)</string></dict></plist>"
            try body.write(to: self.plist, atomically: true, encoding: .utf8)
        }
        if let package {
            try "let package = Package(name: \"X\", platforms: [\(package)])".write(to: self.package, atomically: true, encoding: .utf8)
        }
    }

    private func check() throws -> ScriptRunner.Result {
        try ScriptRunner.run(RepoLayout.url("scripts/check-min-os.sh").path, arguments: [], environment: [
            "APPCAST_TEMPLATE": appcast.path, "INFO_PLIST": plist.path, "PACKAGE_SWIFT": package.path])
    }

    func testAllThreeAgree_TC40() throws {
        let result = try check()
        XCTAssertEqual(result.status, 0, result.output)
    }

    func testAppcastDisagrees_TC41() throws {
        try write(appcast: "13.0", plist: nil, package: nil)
        let result = try check()
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("FAIL appcast"), result.output)
        XCTAssertFalse(result.output.contains("FAIL Info.plist"))
        XCTAssertFalse(result.output.contains("FAIL Package.swift"))
    }

    func testInfoPlistDisagrees_TC42() throws {
        try write(appcast: nil, plist: "15.0", package: nil)
        let result = try check()
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("FAIL Info.plist"), result.output)
        XCTAssertFalse(result.output.contains("FAIL appcast"))
        XCTAssertFalse(result.output.contains("FAIL Package.swift"))
    }

    func testPackagePlatformDisagrees_TC43() throws {
        try write(appcast: nil, plist: nil, package: ".macOS(.v15)")
        let result = try check()
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("FAIL Package.swift"), result.output)
        XCTAssertFalse(result.output.contains("FAIL appcast"))
        XCTAssertFalse(result.output.contains("FAIL Info.plist"))
    }

    func testEveryDisagreeingSourceIsNamed() throws {
        try write(appcast: "13.0", plist: "15.0", package: ".macOS(.v14)")
        let result = try check()
        XCTAssertNotEqual(result.status, 0)
        for name in ["appcast", "Info.plist", "Package.swift"] { XCTAssertTrue(result.output.contains("FAIL \(name)"), result.output) }
    }

    func testTwentySixAndTwentySixPointZeroAreEqual_TC44() throws {
        try write(appcast: "26", plist: "26.0", package: ".macOS(\"26.0\")")
        XCTAssertEqual(try check().status, 0)
        try write(appcast: "26.0", plist: "26", package: ".macOS(.v26)")
        XCTAssertEqual(try check().status, 0)
        try write(appcast: "26.0.0", plist: "26", package: ".macOS(\"26\")")
        XCTAssertEqual(try check().status, 0)
        // 26.1 is not 26.0.
        try write(appcast: "26.1", plist: nil, package: nil)
        XCTAssertNotEqual(try check().status, 0)
    }

    func testMissingOrUnreadableSourceFailsNamingIt() throws {
        try FileManager.default.removeItem(at: appcast)
        var result = try check()
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("FAIL appcast"), result.output)
        try write(appcast: "26.0", plist: nil, package: nil)
        try "<plist><dict/></plist>".write(to: plist, atomically: true, encoding: .utf8)
        result = try check()
        XCTAssertTrue(result.output.contains("FAIL Info.plist"), result.output)
        try write(appcast: nil, plist: "26.0", package: nil)
        try "let package = Package(name: \"X\")".write(to: package, atomically: true, encoding: .utf8)
        result = try check()
        XCTAssertTrue(result.output.contains("FAIL Package.swift"), result.output)
    }

    func testTheRepositoryItselfIsConsistent() throws {
        let result = try ScriptRunner.run(RepoLayout.url("scripts/check-min-os.sh").path, arguments: [], environment: [:])
        XCTAssertEqual(result.status, 0, result.output)
    }

    /// TC-46: one validator script and one validator test; it reads the floor the native-look story declares.
    func testExactlyOneMinimumOSValidatorExists_TC46() throws {
        var scripts: [String] = []
        var tests: [String] = []
        var needles = 0
        let enumerator = FileManager.default.enumerator(at: RepoLayout.root, includingPropertiesForKeys: nil)!
        for case let url as URL in enumerator {
            let relative = String(url.path.dropFirst(RepoLayout.root.path.count + 1))
            if relative.hasPrefix(".build") || relative.hasPrefix("spec") || relative.hasPrefix("docs") || relative.hasPrefix(".git") {
                // Only prune directories: skipDescendants() on a file would skip its remaining siblings too.
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { enumerator.skipDescendants() }
                continue
            }
            guard ["sh", "swift"].contains(url.pathExtension), let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let readsFloor = text.contains("LSMinimumSystemVersion") && text.contains("minimumSystemVersion")
                && (text.contains("Package.swift") || text.contains("PACKAGE_SWIFT"))
            guard readsFloor else { continue }
            needles += 1
            if url.pathExtension == "sh" { scripts.append(relative) }
            else if relative.hasPrefix("Tests/") { tests.append(relative) }
        }
        XCTAssertEqual(scripts, ["scripts/check-min-os.sh"])
        XCTAssertEqual(tests.filter { $0.contains("MinOS") }, ["Tests/LocalPlayerTests/MinOSConsistencyTests.swift"])
        let script = RepoLayout.text("scripts/check-min-os.sh")
        XCTAssertTrue(script.contains("LSMinimumSystemVersion"))
        XCTAssertTrue(script.contains("Package.swift"))
        // The release script calls the validator and does not reimplement it.
        XCTAssertTrue(RepoLayout.text("scripts/release.sh").contains("CHECK_MIN_OS"))
        XCTAssertFalse(RepoLayout.text("scripts/release.sh").contains("LSMinimumSystemVersion"))
        XCTAssertFalse(RepoLayout.text("scripts/build-app.sh").contains("LSMinimumSystemVersion"))
    }
}
