import XCTest
@testable import PlayawayCore

/// Story 18, the shared container: the Mac and the iPhone must mean the same iCloud folder. The iPhone declares the
/// container (entitlement and the user-visible name "Playaway"); the Mac reads that container's folder under Mobile
/// Documents by the same identifier, so the two can never drift apart without one of these failing.
final class CloudContainerTests: XCTestCase {
    private let root = Fixtures.directory.deletingLastPathComponent().deletingLastPathComponent()

    func testTheMacUsesTheIdentifierTheIPhoneDeclares() throws {
        let entitlements = try String(contentsOf: root.appendingPathComponent("ios/App/Playaway.entitlements"), encoding: .utf8)
        XCTAssertTrue(entitlements.contains("<string>\(CloudFolder.containerIdentifier)</string>"), "the phone's container is the Mac's")
        XCTAssertEqual(CloudFolder.containerFolderName, CloudFolder.containerIdentifier.replacingOccurrences(of: ".", with: "~"),
                       "the folder on disk is the identifier with tildes")
    }

    func testThePhoneShowsTheContainerAsAFolderNamedPlayaway() throws {
        let project = try String(contentsOf: root.appendingPathComponent("ios/project.yml"), encoding: .utf8)
        XCTAssertTrue(project.contains("NSUbiquitousContainerName: Playaway"), "the folder the person sees in iCloud Drive is Playaway")
        XCTAssertTrue(project.contains("NSUbiquitousContainerIsDocumentScopePublic: true"), "public, so Finder and Files show it")
        XCTAssertTrue(project.contains(CloudFolder.containerIdentifier + ":"), "declared for the shared identifier")
    }

    func testTheMacLooksUnderMobileDocumentsAndOnlyWhenTheFolderExists() {
        let home = TempDir("home")
        XCTAssertNil(CloudFolder.documentsOnThisDevice(home: home.url))
        let documents = home.makeSubfolder("Library/Mobile Documents/\(CloudFolder.containerFolderName)/Documents")
        XCTAssertEqual(CloudFolder.documentsOnThisDevice(home: home.url)?.canonicalPath, documents.canonicalPath)
        XCTAssertEqual(PlaylistLibrary.cloudPlaylistLocation(in: documents, name: "Dinner").file.lastPathComponent, "Dinner.\(playlistFileExtension)")
    }
}
