import XCTest
@testable import PlayawayCore

/// Runs the shared fixture files. The same files are meant to be run by the Mac and iPhone suites.
@MainActor
final class DownloadFixtureTests: XCTestCase {
    private func load<T: Decodable>(_ name: String, as: T.Type) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    private struct Vectors: Decodable {
        struct V: Decodable { let name: String; let reported: Double?; let downloading: Bool; let previous: Double?; let expect: Double? }
        let percentFullScale: Double; let vectors: [V]
    }

    func testProgressVectors() throws {
        let file = try load("DownloadProgressVectors", as: Vectors.self)
        XCTAssertEqual(file.percentFullScale, reportedPercentFullScale, "fixture and constant must agree")
        for v in file.vectors {
            let got = downloadFraction(reported: v.reported, isDownloading: v.downloading, previous: v.previous)
            if let want = v.expect { XCTAssertEqual(try XCTUnwrap(got, v.name), want, accuracy: 1e-9, v.name) }
            else { XCTAssertNil(got, v.name) }
        }
    }

    private final class Seams: SongDownloading, SongPlaybackStarting {
        var started: [String] = [], cancelled: [String] = [], played: [String] = []
        func startDownload(of s: SongID) { started.append(s.raw) }
        func cancelDownload(of s: SongID) { cancelled.append(s.raw) }
        func startPlayback(of s: SongID) { played.append(s.raw) }
    }

    private struct Scenario: Decodable {
        struct Step: Decodable { let op: String; let song: String; let onDevice: Bool?; let percent: Double? }
        struct Expect: Decodable { let started: [String]; let cancelled: [String]; let played: [String]; let states: [String: String] }
        let name: String; let steps: [Step]; let expect: Expect
    }

    private func describe(_ s: DownloadState) -> String {
        switch s {
        case .onThisDevice: return "onThisDevice"
        case .notOnThisDevice: return "notOnThisDevice"
        case .failed: return "failed"
        case .downloading(let f): return "downloading:\(Int((f * 100).rounded()))"
        }
    }

    func testScenarios() throws {
        for sc in try load("DownloadScenarios", as: [Scenario].self) {
            let seams = Seams(); let c = DownloadOnPlayCoordinator(downloader: seams, player: seams)
            for st in sc.steps {
                let id = SongID(st.song)
                switch st.op {
                case "request": c.request(id, source: .list, isOnDevice: st.onDevice ?? false)
                case "progress": c.handle(.progress(id, reportedPercent: st.percent))
                case "finished": c.handle(.finished(id))
                case "failed": c.handle(.failed(id))
                case "cancel": c.cancel(id)
                case "retry": c.retry(id)
                default: XCTFail("unknown op \(st.op) in \(sc.name)")
                }
            }
            XCTAssertEqual(seams.started, sc.expect.started, sc.name)
            XCTAssertEqual(seams.cancelled, sc.expect.cancelled, sc.name)
            XCTAssertEqual(seams.played, sc.expect.played, sc.name)
            for (song, want) in sc.expect.states { XCTAssertEqual(describe(c.state(of: SongID(song))), want, "\(sc.name): \(song)") }
        }
    }
}
