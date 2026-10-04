import AppKit

/// Launch flags that run a check inside the built app and exit, instead of showing windows.
enum CommandLineMode {
    case dumpWindowElements(kind: String, state: String, audio: [String])
    case sparkleConfig
    case sparkleIntegration(feed: String?)
    case validateHIGChecklist(path: String)
    case checkScriptParity(sdef: String)

    static let dumpFlag = "--dump-window-elements"
    static let sparkleConfigFlag = "--test-sparkle-config"
    static let sparkleIntegrationFlag = "--test-sparkle-integration"
    static let higChecklistFlag = "--validate-hig-checklist"
    static let parityFlag = "--check-script-parity"

    static func parse(_ arguments: [String]) -> CommandLineMode? {
        if let index = arguments.firstIndex(of: parityFlag), arguments.count > index + 1 { return .checkScriptParity(sdef: arguments[index + 1]) }
        if arguments.contains(sparkleConfigFlag) { return .sparkleConfig }
        if let index = arguments.firstIndex(of: sparkleIntegrationFlag) {
            return .sparkleIntegration(feed: arguments.count > index + 1 ? arguments[index + 1] : nil)
        }
        if let index = arguments.firstIndex(of: higChecklistFlag), arguments.count > index + 1 {
            return .validateHIGChecklist(path: arguments[index + 1])
        }
        guard let index = arguments.firstIndex(of: dumpFlag), arguments.count > index + 2 else { return nil }
        // Any further arguments are fixture audio files for the temporary playlist.
        return .dumpWindowElements(kind: arguments[index + 1], state: arguments[index + 2],
                                   audio: Array(arguments.dropFirst(index + 3)))
    }

    static func run(_ mode: CommandLineMode, application: NSApplication, services: AppServices) -> Int32 {
        switch mode {
        case .checkScriptParity(let sdef): return runParityGateCheck(sdefPath: sdef)
        case .sparkleConfig: return runSparkleConfigTest()
        case .sparkleIntegration(let feed): return runSparkleIntegrationTest(feed: feed)
        case .validateHIGChecklist(let path): return runHIGChecklistCheck(path: path)
        case .dumpWindowElements(let kind, let state, let audio):
            do {
                let check = try UICheckMode(fixtureAudio: audio.map { URL(fileURLWithPath: $0) })
                let elements = try check.dump(kind: kind, state: state)
                print(UICheckMode.jsonString(elements))
                return 0
            } catch {
                FileHandle.standardError.write(Data("dump-window-elements failed: \(error)\n".utf8))
                return 1
            }
        }
    }
}
