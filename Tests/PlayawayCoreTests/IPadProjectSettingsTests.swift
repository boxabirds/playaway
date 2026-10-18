import XCTest

/// Story 38, task 38.1: the iOS project builds for iPhone and iPad, the iPad turns every way and the iPhone stays
/// portrait-only, and the width rig key exists in the root view. Read from the project files, as the other
/// source-level guards are.
final class IPadProjectSettingsTests: XCTestCase {
    private let root = Fixtures.directory.deletingLastPathComponent().deletingLastPathComponent()

    private func text(_ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }

    func testTheAppTargetsIPhoneAndIPad() throws {
        let project = try text("ios/project.yml")
        XCTAssertTrue(project.contains("TARGETED_DEVICE_FAMILY: \"1,2\""), "iPhone and iPad")
        XCTAssertFalse(project.contains("TARGETED_DEVICE_FAMILY: \"1\"\n"), "no iPhone-only setting left")
    }

    func testTheIPadTurnsEveryWayAndTheIPhoneStaysPortrait() throws {
        let project = try text("ios/project.yml")
        XCTAssertTrue(project.contains("UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]\n"), "the iPhone list is unchanged")
        let ipad = project.components(separatedBy: "\n").first { $0.contains("UISupportedInterfaceOrientations~ipad:") } ?? ""
        for orientation in ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"] {
            XCTAssertTrue(ipad.contains(orientation), "\(orientation) on iPad")
        }
    }

    func testTheWidthRigIsADebugOnlyKeyOfTheRootView() throws {
        let rootView = try text("ios/App/RootView.swift")
        XCTAssertTrue(rootView.contains("static let windowWidthKey = \"PlayawayWindowWidth\""))
        XCTAssertTrue(rootView.contains("#if DEBUG"), "the rig is a debug aid")
    }
}
