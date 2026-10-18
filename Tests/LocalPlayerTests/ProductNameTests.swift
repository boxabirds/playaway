import XCTest
@testable import LocalPlayer
@testable import PlayawayCore

/// The product is Playaway. Nothing a person can read may still say LocalPlayer: the bundle's names and the
/// document type names in Info.plist, the scripting dictionary Script Editor shows, the UI manifest, and every string
/// literal in the app sources that is not a stable identifier (the playlist file type `com.localplayer.playlist`
/// shipped with the iPhone app and stays; the pasteboard type and the trace subsystem are never shown).
final class ProductNameTests: XCTestCase {
    static let productName = "Playaway"
    static let oldName = "LocalPlayer"
    static let macBundleID = "software.away.play.mac"
    /// Identifiers that keep the old word on purpose; a string literal containing one of these is not user-visible.
    static let keptIdentifiers = ["com.localplayer.playlist", "com.localplayer.trace"]

    func testTheBundleIsNamedAndIdentifiedAsPlayaway() throws {
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: RepoLayout.url("Resources/Info.plist")), format: nil) as! [String: Any]
        XCTAssertEqual(plist["CFBundleName"] as? String, Self.productName)
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, Self.productName)
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, Self.productName, "the process name in Activity Monitor and System Events")
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, Self.macBundleID)
        XCTAssertEqual(plist["OSAScriptingDefinition"] as? String, "\(Self.productName).sdef")
        let typeNames = (plist["CFBundleDocumentTypes"] as! [[String: Any]]).compactMap { $0["CFBundleTypeName"] as? String }
            + (plist["UTExportedTypeDeclarations"] as! [[String: Any]]).compactMap { $0["UTTypeDescription"] as? String }
        XCTAssertTrue(typeNames.contains("\(Self.productName) Playlist"), "the Kind column in Finder: \(typeNames)")
        XCTAssertFalse(typeNames.joined().contains(Self.oldName), typeNames.joined(separator: ", "))
    }

    func testTheResourcesAPersonReadsNeverSayLocalPlayer() {
        for resource in ["Resources/Info.plist", "Resources/\(Self.productName).sdef", "Resources/ui-manifest.json"] {
            let text = RepoLayout.text(resource)
            XCTAssertFalse(text.isEmpty, "\(resource) missing")
            let offending = text.components(separatedBy: .newlines).filter { $0.contains(Self.oldName) }
                .filter { line in !Self.keptIdentifiers.contains { line.contains($0) } }
            XCTAssertEqual(offending, [], resource)
        }
        XCTAssertTrue(RepoLayout.text("Resources/\(Self.productName).sdef").contains("<suite name=\"\(Self.productName) Suite\""), "Script Editor's dictionary title")
        XCTAssertEqual(AppMenu.appName, Self.productName, "the application menu, About, Hide and Quit")
    }

    func testNoStringLiteralInTheAppSourcesSaysLocalPlayer() throws {
        let literal = try NSRegularExpression(pattern: "\"[^\"\\n]*\(Self.oldName)[^\"\\n]*\"")
        var offending: [String] = []
        for folder in ["Sources/LocalPlayer", "Sources/PlayawayCore", "ios/App"] {
            let files = FileManager.default.enumerator(at: RepoLayout.url(folder), includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
            XCTAssertFalse(files.isEmpty, folder)
            for file in files {
                let text = try String(contentsOf: file, encoding: .utf8)
                for match in literal.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    let found = String(text[Range(match.range, in: text)!])
                    if Self.keptIdentifiers.contains(where: { found.contains($0) }) { continue }
                    offending.append("\(file.lastPathComponent): \(found)")
                }
            }
        }
        XCTAssertEqual(offending, [], "strings a person could read")
    }
}
