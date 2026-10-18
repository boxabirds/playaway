import XCTest
@testable import PlayawayCore

/// Story 40, reference.cloud_path: the portable location read off any device's path, and how it travels in the file.
final class CloudPathTests: XCTestCase {
    static let macDrive = "/Users/julian/Library/Mobile Documents/com~apple~CloudDocs/Mixdowns/Doo-bye/Doo-bye 2060621-1.mp3"
    static let iosDrive = "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Mixdowns/Doo-bye/Doo-bye 2060621-1.mp3"
    static let macContainer = "/Users/julian/Library/Mobile Documents/iCloud~software~away~play/Documents/Trip/a.mp3"
    static let iosContainer = "/private/var/mobile/Library/Mobile Documents/iCloud~software~away~play/Documents/Trip/a.mp3"

    func testAMacPathAndAnIPhonePathInICloudDriveGiveTheSameLocation() {      // TC-01, TC-02
        XCTAssertEqual(CloudPath.derive(fromPath: Self.macDrive), .iCloudDrive("Mixdowns/Doo-bye/Doo-bye 2060621-1.mp3"))
        XCTAssertEqual(CloudPath.derive(fromPath: Self.iosDrive), CloudPath.derive(fromPath: Self.macDrive))
    }

    func testAContainerPathOnEitherDeviceGivesThePlayawayFolderLocation() {   // TC-03
        XCTAssertEqual(CloudPath.derive(fromPath: Self.macContainer), .playawayFolder("Trip/a.mp3"))
        XCTAssertEqual(CloudPath.derive(fromPath: Self.iosContainer), .playawayFolder("Trip/a.mp3"))
    }

    func testALocalPathHasNoPortableLocation() {                                // TC-04
        XCTAssertNil(CloudPath.derive(fromPath: "/Users/julian/Music/a.mp3"))
        XCTAssertNil(CloudPath.derive(fromPath: "/private/var/mobile/Containers/Data/Application/ABC/Documents/a.mp3"))
        XCTAssertNil(CloudPath.derive(fromPath: ""))
    }

    func testTheRootsThemselvesAreNotLocations() {                              // TC-05
        XCTAssertNil(CloudPath.derive(fromPath: "/Users/julian/Library/Mobile Documents/com~apple~CloudDocs/"))
        XCTAssertNil(CloudPath.derive(fromPath: "/Users/julian/Library/Mobile Documents/iCloud~software~away~play/Documents/"))
    }

    func testAFolderNamedLikeTheRootInsideICloudDriveStaysPartOfThePath() {     // TC-06
        let twice = "/Users/x/Library/Mobile Documents/com~apple~CloudDocs/Odd/Mobile Documents/com~apple~CloudDocs/a.mp3"
        XCTAssertEqual(CloudPath.derive(fromPath: twice), .iCloudDrive("Odd/Mobile Documents/com~apple~CloudDocs/a.mp3"))
    }

    func testTheLocationRoundTripsThroughTheFile() throws {                     // TC-07
        let ref = TrackReference(bookmark: Data([1, 2]), lastKnownPath: Self.macDrive, fileName: "Doo-bye 2060621-1.mp3",
                                 cloudPath: .iCloudDrive("Mixdowns/Doo-bye/Doo-bye 2060621-1.mp3"))
        let data = try JSONEncoder().encode(ref)
        XCTAssertEqual(try JSONDecoder().decode(TrackReference.self, from: data), ref)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"root\":\"drive\""), json)
        let container = try JSONEncoder().encode(TrackReference(bookmark: Data(), lastKnownPath: Self.iosContainer, fileName: "a.mp3", cloudPath: .playawayFolder("Trip/a.mp3")))
        XCTAssertTrue(String(decoding: container, as: UTF8.self).contains("\"root\":\"playaway\""))
    }

    func testABuild22ReferenceDecodesAndDerivesItsLocationFromThePath() throws {   // TC-08
        let old = """
        {"bookmark":"AQI=","lastKnownPath":"\(Self.iosDrive)","fileName":"Doo-bye 2060621-1.mp3"}
        """
        let ref = try JSONDecoder().decode(TrackReference.self, from: Data(old.utf8))
        XCTAssertNil(ref.cloudPath)
        XCTAssertEqual(ref.portableLocation, .iCloudDrive("Mixdowns/Doo-bye/Doo-bye 2060621-1.mp3"))
        let local = TrackReference(bookmark: Data(), lastKnownPath: "/Users/x/Music/a.mp3", fileName: "a.mp3")
        XCTAssertNil(local.portableLocation)
        // Written back without a cloud path, so an older build reads it unchanged.
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(local), as: UTF8.self).contains("cloudPath"))
    }

    func testTheTopFolderIsWhatADeviceIsAskedToAllow() {                        // TC-09
        XCTAssertEqual(CloudPath.iCloudDrive("Mixdowns/Doo-bye/a.mp3").topFolder, "Mixdowns")
        XCTAssertEqual(CloudPath.iCloudDrive("Mixdowns/a.mp3").topFolder, "Mixdowns")
        XCTAssertNil(CloudPath.iCloudDrive("a.mp3").topFolder, "a file at the root has no folder to ask for")
        XCTAssertNil(CloudPath.playawayFolder("Trip/a.mp3").topFolder)
        XCTAssertEqual(CloudPath.iCloudDrive("Mixdowns/Doo-bye/a.mp3").folderPath, "Mixdowns/Doo-bye")
        XCTAssertEqual(CloudPath.iCloudDrive("a.mp3").folderPath, "")
    }

    func testMakeFillsTheLocationForAFileInsideALaidOutHome() throws {
        let home = TempDir("home")
        let drive = home.url.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Mixdowns")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let song = drive.appendingPathComponent("a.mp3")
        try Data([1]).write(to: song)
        XCTAssertEqual(TrackReference.make(for: song)?.cloudPath, .iCloudDrive("Mixdowns/a.mp3"))
        let local = home.url.appendingPathComponent("b.mp3")
        try Data([1]).write(to: local)
        XCTAssertNil(TrackReference.make(for: local)?.cloudPath)
    }
}
