import XCTest
@testable import PlayawayCore

final class TrackMetadataTests: XCTestCase {
    func testFallbackUsesTheFileNameWithoutExtension() {
        XCTAssertEqual(TrackMetadata.fallback(for: URL(fileURLWithPath: "/a/b/Kettle Song.mp3")),
                       TrackMetadata(title: "Kettle Song"))
    }

    func testAFileWithNoMetadataGivesTheFileNameAndNothingElse() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Plain \(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.silentWav().write(to: url)
        let meta = await loadTrackMetadata(for: url)
        XCTAssertEqual(meta.title, url.deletingPathExtension().lastPathComponent)
        XCTAssertNil(meta.artist); XCTAssertNil(meta.album); XCTAssertNil(meta.artworkData)
    }

    func testAMissingFileFallsBackWithoutCrashing() async {
        let meta = await loadTrackMetadata(for: URL(fileURLWithPath: "/nonexistent/Gone.mp3"))
        XCTAssertEqual(meta, TrackMetadata(title: "Gone"))
    }

    static func silentWav() -> Data {
        var d = Data(); let samples = 800
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(36 + samples * 2); d.append("WAVEfmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(1); u32(8000); u32(16000); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(samples * 2); d.append(Data(count: samples * 2))
        return d
    }
}
