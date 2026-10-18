import XCTest
@testable import PlayawayCore

/// Story 42, origin.classify: what kind of unfound a song is.
final class UnfoundKindTests: XCTestCase {
    let ios = DeviceShape(platform: .iOS, ownContainerID: "OWN-1111")
    let mac = DeviceShape(platform: .mac)
    func ref(_ path: String, cloud: CloudPath? = nil) -> TrackReference { TrackReference(bookmark: Data(), lastKnownPath: path, fileName: "a.mp3", cloudPath: cloud) }

    func testAMacPathOnAnIOSDeviceIsElsewhere() {                                   // TC-01
        XCTAssertEqual(classifyUnfound(ref("/Users/x/Music/a.mp3"), accessNeeded: nil, device: ios), .elsewhere)
    }
    func testAnIOSPathOnTheMacIsElsewhere() {                                       // TC-02
        XCTAssertEqual(classifyUnfound(ref("/private/var/mobile/Containers/Data/Application/AAA/Documents/a.mp3"), accessNeeded: nil, device: mac), .elsewhere)
    }
    func testAMissingFileInThisInstallsOwnContainerIsGone() {                       // TC-03
        XCTAssertEqual(classifyUnfound(ref("/private/var/mobile/Containers/Data/Application/OWN-1111/Documents/a.mp3"), accessNeeded: nil, device: ios), .gone)
    }
    func testAnotherInstallsContainerIsElsewhere() {                                // TC-04
        XCTAssertEqual(classifyUnfound(ref("/private/var/mobile/Containers/Data/Application/THEIRS-2222/Documents/a.mp3"), accessNeeded: nil, device: ios), .elsewhere)
    }
    func testASongNeedingAFolderPermissionIsNeverElsewhere() {                      // TC-05
        let drivePath = "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Mixdowns/a.mp3"
        XCTAssertEqual(classifyUnfound(ref(drivePath), accessNeeded: "Mixdowns", device: ios), .needsAccess)
        XCTAssertEqual(classifyUnfound(ref("/Users/x/Music/a.mp3", cloud: .iCloudDrive("Mixdowns/a.mp3")), accessNeeded: "Mixdowns", device: ios), .needsAccess)
    }
    func testAMissingFileUnderThisMacsHomeIsGone() {                                // TC-06
        XCTAssertEqual(classifyUnfound(ref("/Users/x/Music/a.mp3"), accessNeeded: nil, device: mac), .gone)
    }
    func testAnEmptyStoredPathIsGone() {                                            // TC-07
        XCTAssertEqual(classifyUnfound(ref(""), accessNeeded: nil, device: ios), .gone)
        XCTAssertEqual(classifyUnfound(ref(""), accessNeeded: nil, device: mac), .gone)
    }
    func testASharedFileProviderPathCannotBeToldFromADeletedFileSoItIsGone() {      // TC-08 (the stated limit)
        XCTAssertEqual(classifyUnfound(ref("/private/var/mobile/Library/Application Support/File Provider Storage/x/a.mp3"), accessNeeded: nil, device: ios), .gone)
    }
    func testAnUnmountedVolumeOnTheMacIsGone() {                                    // TC-09
        XCTAssertEqual(classifyUnfound(ref("/Volumes/Music/a.mp3"), accessNeeded: nil, device: mac), .gone)
    }
    func testAPathInThisInstallsOwnHomeIsNeverElsewhereEvenIfItLooksLikeAMacs() {   // the simulator's own paths
        let sim = DeviceShape(platform: .iOS, ownContainerID: "OWN", ownHome: "/Users/julian/Library/Developer/CoreSimulator/Devices/D/data/Containers/Data/Application/OWN")
        XCTAssertEqual(classifyUnfound(ref("/Users/julian/Library/Developer/CoreSimulator/Devices/D/data/Containers/Data/Application/OWN/Documents/Gone.wav"), accessNeeded: nil, device: sim), .gone)
        XCTAssertEqual(classifyUnfound(ref("/Users/julian/Music/a.mp3"), accessNeeded: nil, device: sim), .elsewhere)
    }

    func testTheCurrentDeviceKnowsItsOwnShape() {
        #if os(macOS)
        XCTAssertEqual(DeviceShape.current.platform, .mac)
        XCTAssertFalse(DeviceShape.current.addedElsewhere(path: NSHomeDirectory() + "/Music/a.mp3"))
        #endif
    }
}
