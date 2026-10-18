import XCTest
import AppKit
@testable import LocalPlayer

/// Swift 6 (audit F1): Cocoa calls `performDefaultImplementation` on the main thread but the override is not declared
/// main-actor, so the commands enter the main actor with `runOnMain`. Pinned here because nothing else in the unit tests
/// goes through a real `NSScriptCommand`: a command with no app to answer it must say so the way a script expects, and
/// the same command object must still be usable afterwards.
@MainActor
final class ScriptCommandThreadingTests: XCTestCase {
    override func setUp() { _ = NSApplication.shared }          // `actions()` asks NSApp for its delegate; there is no delegate here

    private func makeCommand() -> LocalPlayerCommand {
        let description = NSScriptCommandDescription(
            suiteName: "Playaway", commandName: "test",
            dictionary: ["CommandClass": "NSScriptCommand", "AppleEventCode": "test", "AppleEventClassCode": "PlAw"])
        return LocalPlayerCommand(commandDescription: description!)
    }

    func testWithNoAppReadyTheCommandAnswersNotReadyAndNeverRunsItsBody() {
        let command = makeCommand()
        var bodyRan = false
        let result = command.runOnMain { _ in bodyRan = true; return "answer" }
        XCTAssertNil(result)
        XCTAssertFalse(bodyRan, "there are no actions to run it with")
        XCTAssertEqual(command.scriptErrorNumber, ScriptError.notReady)
        XCTAssertEqual(command.scriptErrorString, "The app is not ready yet.")
    }

    func testTheSameCommandAnswersAgainAfterARefusal() {
        let command = makeCommand()
        XCTAssertNil(command.runOnMain { _ in 1 })
        command.scriptErrorNumber = 0
        XCTAssertNil(command.runOnMain { _ in 2 })
        XCTAssertEqual(command.scriptErrorNumber, ScriptError.notReady, "the refusal is recorded each time")
    }
}
