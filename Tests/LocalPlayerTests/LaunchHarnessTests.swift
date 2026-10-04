import XCTest
@testable import LocalPlayer

final class LaunchVerdictTests: XCTestCase {
    private let calculator = LaunchVerdictCalculator()

    func testTC30ExactlyBudgetIsWithin() {
        XCTAssertEqual(calculator.verdict(elapsedMilliseconds: launchBudgetMilliseconds), .withinBudget(ms: 1000))
    }

    func testTC31OneOverBudgetIsOver() {
        XCTAssertEqual(calculator.verdict(elapsedMilliseconds: launchBudgetMilliseconds + 1), .overBudget(ms: 1001))
    }

    func testTC32OneUnderBudgetIsWithin() {
        XCTAssertEqual(calculator.verdict(elapsedMilliseconds: launchBudgetMilliseconds - 1), .withinBudget(ms: 999))
    }

    func testTC33ZeroOrNegativeIsInvalidNeverAPass() {
        for elapsed in [0, -1, -1000] {
            let verdict = calculator.verdict(elapsedMilliseconds: elapsed)
            XCTAssertEqual(verdict, .invalid, "\(elapsed)")
            XCTAssertFalse(verdict.isPass)
        }
    }

    func testTC34MissingStopTimestampIsInvalidNeverAPass() {
        XCTAssertEqual(calculator.verdict(elapsedMilliseconds: nil), .invalid)
        XCTAssertNil(LaunchElapsed.milliseconds(startNanoseconds: 5, stopNanoseconds: nil))
        XCTAssertEqual(calculator.verdict(elapsedMilliseconds: LaunchElapsed.milliseconds(startNanoseconds: 5, stopNanoseconds: nil)), .invalid)
    }

    func testTC35TenRunsOneOverBudgetFailsBatch() {
        var verdicts = [LaunchVerdict](repeating: .withinBudget(ms: 500), count: launchRunsPerBatch - 1)
        verdicts.append(.overBudget(ms: launchBudgetMilliseconds + 1))
        let batch = LaunchBatchResult(temperature: .warm, verdicts: verdicts)
        XCTAssertEqual(batch.verdicts.count, launchRunsPerBatch)
        XCTAssertFalse(batch.passes)
        XCTAssertEqual(batch.batchVerdict, .overBudget(ms: 1001))
    }

    func testBatchPassesOnlyWhenEveryRunIsWithin() {
        let all = LaunchBatchResult(temperature: .warm, verdicts: [.withinBudget(ms: 300), .withinBudget(ms: 1000)])
        XCTAssertTrue(all.passes)
        XCTAssertEqual(all.batchVerdict, .withinBudget(ms: 1000))
    }

    func testBatchWithAnInvalidRunFailsAndIsInvalid() {
        let batch = LaunchBatchResult(temperature: .cold, verdicts: [.withinBudget(ms: 300), .invalid])
        XCTAssertFalse(batch.passes)
        XCTAssertEqual(batch.batchVerdict, .invalid)
    }

    func testEmptyBatchIsNotAPass() {
        XCTAssertFalse(LaunchBatchResult(temperature: .warm, verdicts: []).passes)
    }

    func testColdAndWarmBatchesAreReportedSeparately() {
        let cold = LaunchBatchResult(temperature: .cold, verdicts: [.overBudget(ms: 1500)], coldIsCachePurgeProxy: true)
        let warm = LaunchBatchResult(temperature: .warm, verdicts: [.withinBudget(ms: 300)])
        let report = LaunchReport(batches: [cold, warm])
        XCTAssertEqual(report.batches(of: .cold).count, 1)
        XCTAssertEqual(report.batches(of: .warm).count, 1)
        XCTAssertFalse(cold.passes)
        XCTAssertTrue(warm.passes, "a failing cold batch must not change the warm batch verdict")
        XCTAssertTrue(report.batches(of: .cold)[0].coldIsCachePurgeProxy)
    }

    func testElapsedConversionRoundsUpAndKeepsSign() {
        let ms = LaunchElapsed.nanosecondsPerMillisecond
        XCTAssertEqual(LaunchElapsed.milliseconds(startNanoseconds: 100, stopNanoseconds: 100 + UInt64(1000 * ms)), 1000)
        XCTAssertEqual(LaunchElapsed.milliseconds(startNanoseconds: 100, stopNanoseconds: 100 + UInt64(1000 * ms) + 1), 1001)
        XCTAssertEqual(LaunchElapsed.milliseconds(startNanoseconds: 100, stopNanoseconds: 100), 0)
        XCTAssertLessThan(LaunchElapsed.milliseconds(startNanoseconds: 100 + UInt64(5 * ms), stopNanoseconds: 100)!, 1)
    }
}

final class LaunchTraceTests: XCTestCase {
    func testTC41NoPathVariableWritesNothing() {
        let dir = TempDir("trace")
        let before = try! FileManager.default.contentsOfDirectory(atPath: dir.url.path)
        let trace = LaunchTrace(environment: [:])
        trace.record(.launching)
        trace.record(.windowShown)
        XCTAssertEqual(try! FileManager.default.contentsOfDirectory(atPath: dir.url.path), before)
        XCTAssertEqual(trace.recorded.count, 2, "phases are still kept in memory; only the file is skipped")
        let explicitNil = LaunchTrace(resultsPath: nil)
        explicitNil.record(.windowShown)
        XCTAssertTrue(try! FileManager.default.contentsOfDirectory(atPath: dir.url.path).isEmpty)
    }

    func testTC42TraceFileParsesToTheTimestampTheAppRecorded() {
        let dir = TempDir("trace")
        let path = dir.path("trace.jsonl").path
        let trace = LaunchTrace(environment: [LaunchTrace.environmentKey: path])
        trace.record(.launching)
        trace.record(.windowShown)
        let shown = trace.recorded.first { $0.phase == .windowShown }!.nanoseconds
        XCTAssertEqual(LaunchTrace.timestamp(of: .windowShown, inFileAt: path), shown)
        XCTAssertEqual(LaunchTrace.timestamp(of: .launching, inFileAt: path), trace.recorded[0].nanoseconds)
        XCTAssertNil(LaunchTrace.timestamp(of: .running, inFileAt: path))
        XCTAssertNil(LaunchTrace.timestamp(of: .windowShown, inFileAt: dir.path("missing").path))
    }

    func testTC42InjectedClockValuesRoundTripExactly() {
        let dir = TempDir("trace")
        let path = dir.path("t.jsonl").path
        let stamp: UInt64 = 123_456_789_012_345
        let trace = LaunchTrace(resultsPath: path, clock: { stamp })
        trace.record(.windowShown)
        XCTAssertEqual(LaunchTrace.timestamp(of: .windowShown, inFileAt: path), stamp)
    }

    /// The trace uses the same clock family the harness helper reads; a real record must sit between two reads.
    func testRealClockTimestampsAreMonotonicRaw() {
        let before = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
        let trace = LaunchTrace(resultsPath: nil)
        trace.record(.windowShown)
        let after = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
        let stamp = trace.recorded[0].nanoseconds
        XCTAssertTrue(before <= stamp && stamp <= after)
    }
}

/// Runs scripts/launch-bench.sh with a stub launcher (a compiled stub that writes a windowShown trace line),
/// so the script's own logic is tested without a GUI launch. Real-bundle runs are reported separately by hand.
final class LaunchBenchScriptTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    private var script: String { root.appendingPathComponent("scripts/launch-bench.sh").path }

    private func run(_ arguments: [String], environment: [String: String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private func makeFakeBundle(in dir: TempDir) -> String {
        let bundle = dir.makeSubfolder("Fake.app")
        return bundle.path
    }

    /// Compiles a stand-in for `open`: finds `--env KEY=VALUE`, waits a few ms, writes the windowShown line.
    private func makeStubLauncher(in dir: TempDir) throws -> String {
        let source = dir.path("stub.c")
        try """
        #include <stdio.h>
        #include <string.h>
        #include <time.h>
        int main(int argc, char **argv) {
            const char *key = "LOCALPLAYER_LAUNCH_TRACE=";
            for (int i = 1; i < argc; i++) {
                if (strncmp(argv[i], key, strlen(key)) == 0) {
                    struct timespec pause = {0, 5000000};
                    nanosleep(&pause, NULL);
                    FILE *f = fopen(argv[i] + strlen(key), "a");
                    if (!f) return 1;
                    fprintf(f, "{\\"phase\\":\\"windowShown\\",\\"nanoseconds\\":%llu}\\n", clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW));
                    fclose(f);
                }
            }
            return 0;
        }
        """.write(to: source, atomically: true, encoding: .utf8)
        let binary = dir.path("stub-open").path
        let compile = Process()
        compile.executableURL = URL(fileURLWithPath: "/usr/bin/cc")
        compile.arguments = ["-o", binary, source.path]
        try compile.run()
        compile.waitUntilExit()
        try XCTSkipIf(compile.terminationStatus != 0, "cc is not available to build the stub launcher")
        return binary
    }

    func testScriptVerdictMatchesSwiftCalculatorAtTheBoundaries() throws {
        let calculator = LaunchVerdictCalculator()
        for elapsed in [-5, 0, 1, 999, 1000, 1001, 5000] {
            let result = try run(["--verdict", String(elapsed)], environment: [:])
            let expected: String
            switch calculator.verdict(elapsedMilliseconds: elapsed) {
            case .withinBudget: expected = "within"
            case .overBudget: expected = "over"
            case .invalid: expected = "invalid"
            }
            XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), expected, "\(elapsed)")
        }
        XCTAssertEqual(try run(["--verdict", ""], environment: [:]).output.trimmingCharacters(in: .whitespacesAndNewlines), "invalid")
    }

    func testTC54HarnessWritesOnlyItsResultsFileAndLeavesUserFilesUntouched() throws {
        let userDir = TempDir("user")
        let playlist = userDir.path("mine.\(playlistFileExtension)")
        try Data("{}".utf8).write(to: playlist)
        let audio = userDir.copyFixture("track1.mp3")
        let snapshots = [FileSnapshot(playlist), FileSnapshot(audio)]
        let listing = try FileManager.default.contentsOfDirectory(atPath: userDir.url.path).sorted()

        let toolDir = TempDir("tools")
        let stub = try makeStubLauncher(in: toolDir)
        let bundle = makeFakeBundle(in: toolDir)
        let scratchRoot = TempDir("scratch")
        let resultsDir = TempDir("results")
        let results = resultsDir.path("results.txt").path

        let result = try run([bundle, "warm", "3", playlist.path], environment: [
            "LAUNCH_BENCH_OPEN": stub, "LAUNCH_BENCH_RESULTS": results, "TMPDIR": scratchRoot.url.path + "/"])
        XCTAssertEqual(result.status, 0, result.output)

        XCTAssertEqual([FileSnapshot(playlist), FileSnapshot(audio)], snapshots)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: userDir.url.path).sorted(), listing)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: resultsDir.url.path), ["results.txt"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: scratchRoot.url.path), [],
                       "scratch directory must be removed on exit")
        let text = try String(contentsOfFile: results, encoding: .utf8)
        XCTAssertEqual(text.components(separatedBy: "within budget").count - 1, 3, text)
        XCTAssertTrue(text.contains("BATCH [warm]: PASS"), text)
        XCTAssertTrue(text.contains("THIS machine only"))
    }

    func testTC34ScriptMarksTimedOutRunsInvalidAndFailsTheBatch() throws {
        let toolDir = TempDir("tools")
        let bundle = makeFakeBundle(in: toolDir)
        let resultsDir = TempDir("results")
        let result = try run([bundle, "warm", "2"], environment: [
            "LAUNCH_BENCH_OPEN": "/usr/bin/true", "LAUNCH_BENCH_TIMEOUT_SECONDS": "1",
            "LAUNCH_BENCH_RESULTS": resultsDir.path("r.txt").path])
        XCTAssertEqual(result.status, 1, result.output)
        XCTAssertEqual(result.output.components(separatedBy: "INVALID").count - 1, 2, result.output)
        XCTAssertTrue(result.output.contains("BATCH [warm]: FAIL"))
        XCTAssertFalse(result.output.contains("within budget"))
    }

    func testColdWithoutPurgeIsLabelledNotColdOrProxy() throws {
        let toolDir = TempDir("tools")
        let stub = try makeStubLauncher(in: toolDir)
        let bundle = makeFakeBundle(in: toolDir)
        let resultsDir = TempDir("results")
        let result = try run([bundle, "cold", "1"], environment: [
            "LAUNCH_BENCH_OPEN": stub, "LAUNCH_BENCH_RESULTS": resultsDir.path("r.txt").path])
        XCTAssertTrue(result.output.contains("NOT COLD") || result.output.contains("PROXY"), result.output)
        XCTAssertFalse(result.output.contains("BATCH [cold]:"), "a cold batch must never be reported unlabelled")
    }

    func testBadArgumentsAreRejected() throws {
        XCTAssertEqual(try run([], environment: [:]).status, 2)
        XCTAssertEqual(try run(["/nonexistent.app", "warm"], environment: [:]).status, 2)
        let toolDir = TempDir("tools")
        XCTAssertEqual(try run([makeFakeBundle(in: toolDir), "lukewarm"], environment: [:]).status, 2)
    }
}
