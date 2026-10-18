import XCTest
@testable import PlayawayCore

final class HIGChecklistTests: XCTestCase {
    private let dir = TempDir("hig")

    private func write(_ text: String, name: String = "hig-checklist.md") throws -> String {
        let url = dir.path(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    func testTC60AllPassValidates() throws {
        let path = try write("# HIG\n- [a] pass\n- [b] pass: tested by X\n")
        XCTAssertEqual(validateChecklist(at: path), [])
        XCTAssertEqual(runHIGChecklistCheck(path: path, output: { _ in }), 0)
    }

    func testTC61FailWithExceptionValidatesAndListsException() throws {
        let path = try write("- [a] pass\n- [b] exception: system sheet cannot be restyled\n")
        XCTAssertEqual(validateChecklist(at: path), [])
        let exceptions = checklistExceptions(at: path)
        XCTAssertEqual(exceptions.count, 1)
        XCTAssertEqual(exceptions.first?.id, "b")
        XCTAssertEqual(exceptions.first?.reason, "system sheet cannot be restyled")
        var printed: [String] = []
        XCTAssertEqual(runHIGChecklistCheck(path: path, output: { printed.append($0) }), 0)
        XCTAssertTrue(printed.contains { $0.contains("system sheet cannot be restyled") })
    }

    func testTC62FailWithoutExceptionFailsNamingItem() throws {
        XCTAssertEqual(validateChecklist(at: try write("- [a] pass\n- [glass-use] fail\n")), [.failWithoutException("glass-use")])
        XCTAssertEqual(validateChecklist(at: try write("- [glass-use] exception:\n")), [.failWithoutException("glass-use")])
    }

    func testTC63UnmarkedItemFailsNamingItem() throws {
        XCTAssertEqual(validateChecklist(at: try write("- [a] pass\n- [menu-bar]\n")), [.unmarked("menu-bar")])
        XCTAssertEqual(validateChecklist(at: try write("- [menu-bar] unmarked\n")), [.unmarked("menu-bar")])
        XCTAssertEqual(validateChecklist(at: try write("- [menu-bar] maybe\n")), [.unmarked("menu-bar")])
    }

    func testTC64EmptyFileFailsWithNoItems() throws {
        XCTAssertEqual(validateChecklist(at: try write("")), [.noItems])
        XCTAssertEqual(validateChecklist(at: try write("# Title only\n\nSome prose.\n")), [.noItems])
    }

    func testTC65MissingFileNamesPath() {
        let path = dir.path("does-not-exist.md").path
        XCTAssertEqual(validateChecklist(at: path), [.fileMissing(path)])
        var printed: [String] = []
        XCTAssertNotEqual(runHIGChecklistCheck(path: path, output: { printed.append($0) }), 0)
        XCTAssertTrue(printed.first?.contains(path) == true)
    }

    func testTC74ReleaseBlockedOnFailWithoutException() throws {
        let path = try write("- [a] pass\n- [b] fail\n")
        var printed: [String] = []
        XCTAssertNotEqual(runHIGChecklistCheck(path: path, output: { printed.append($0) }), 0)
        XCTAssertTrue(printed.contains { $0.contains("b") })
    }

    func testIndentedLinesAndExamplesAreNotItems() {
        let items = parseChecklist("    - [example] pass\n  description\n- [real] PASS\n")
        XCTAssertEqual(items, [ChecklistItem(id: "real", status: .pass)])
    }

    /// The shipped checklist must stay honest: no item may be pre-marked pass without a recorded verification.
    /// Today none is verified, so the gate must fail; when story 008 tests mark items this test is to be updated.
    func testShippedChecklistParsesAndCurrentlyBlocksRelease() throws {
        let path = Fixtures.directory.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/hig-checklist.md").path
        let items = try XCTUnwrap(parseChecklist(at: path))
        XCTAssertGreaterThanOrEqual(items.count, 6)
        let required = ["system-controls", "menu-bar", "light-dark", "accessibility-settings", "glass-use", "window-behaviour"]
        for id in required { XCTAssertTrue(items.contains { $0.id == id }, id) }
        XCTAssertFalse(validateChecklist(at: path).isEmpty)
    }
}
