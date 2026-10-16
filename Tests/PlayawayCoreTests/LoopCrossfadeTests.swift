import XCTest
@testable import PlayawayCore

final class LoopCrossfadeTests: XCTestCase {
    private func sine(frames: Int, hz: Double, rate: Double = 44_100) -> [Float] {
        (0..<frames).map { Float(sin(2 * .pi * hz * Double($0) / rate)) }
    }

    /// The biggest jump between neighbouring frames of a plain sine, as the yardstick for "no click".
    private func largestStep(of samples: [Float]) -> Float {
        zip(samples, samples.dropFirst()).map { abs($1 - $0) }.max() ?? 0
    }

    func testAPlainCutAtTheLoopPointIsAClick() {
        let source = sine(frames: 44_100 + loopCrossfadeFrames, hz: 1_003.3)
        let plain = Array(source[0..<44_100])
        let seam = abs(plain[0] - plain[plain.count - 1])
        XCTAssertGreaterThan(seam, 4 * largestStep(of: plain.prefix(200).map { $0 }), "the unblended loop has a jump at its seam")
    }

    func testTheBlendedLoopHasNoJumpAtItsSeam() {
        let source = sine(frames: 44_100 + loopCrossfadeFrames, hz: 1_003.3)
        let loop = seamlessLoop(source, loopFrames: 44_100, fadeFrames: loopCrossfadeFrames)
        XCTAssertEqual(loop.count, 44_100)
        let normalStep = largestStep(of: loop.suffix(2_000).map { $0 })
        let seam = abs(loop[0] - loop[loop.count - 1])
        XCTAssertLessThanOrEqual(seam, 1.5 * normalStep, "the end of the loop runs on into its start like any two neighbouring frames")
    }

    func testTheBlendDoesNotChangeTheMiddleOfTheSnippet() {
        let source = sine(frames: 1_000 + loopCrossfadeFrames, hz: 440)
        let loop = seamlessLoop(source, loopFrames: 1_000, fadeFrames: loopCrossfadeFrames)
        XCTAssertEqual(Array(loop[loopCrossfadeFrames...]), Array(source[loopCrossfadeFrames..<1_000]))
    }

    func testTheBlendNeverExceedsTheSignalAndKeepsItsLoudness() {
        let source = [Float](repeating: 0.5, count: 500 + loopCrossfadeFrames)       // a steady level
        let loop = seamlessLoop(source, loopFrames: 500, fadeFrames: loopCrossfadeFrames)
        for value in loop.prefix(loopCrossfadeFrames) {
            XCTAssertGreaterThanOrEqual(value, 0.5 - 0.0001, "the blend of two identical signals is never quieter")
            XCTAssertLessThanOrEqual(value, 0.5 * Float(2).squareRoot() + 0.0001, "and at most 3 dB louder (equal power)")
        }
    }

    func testASnippetShorterThanTheFadeStillLoops() {
        let loop = seamlessLoop([0.1, 0.2, 0.3], loopFrames: 3, fadeFrames: 50)
        XCTAssertEqual(loop, [0.1, 0.2, 0.3], "no extra frames to blend: the loop is the snippet")
    }
}
