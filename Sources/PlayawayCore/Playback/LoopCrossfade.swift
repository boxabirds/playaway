import Foundation

/// How many frames the end of a looped snippet is blended into its start, so the loop point cannot click: about a
/// millisecond at 44.1 kHz.
package let loopCrossfadeFrames = 50

/// Turns `loopFrames + fadeFrames` frames of one channel into a seamless loop of `loopFrames` frames. The extra
/// `fadeFrames` that follow the snippet are blended into its start with an equal-power curve, so the sound running off the
/// end of the loop is continued, sample for sample, by the start of the next pass.
package func seamlessLoop(_ source: [Float], loopFrames: Int, fadeFrames: Int) -> [Float] {
    precondition(loopFrames > 0 && fadeFrames >= 0 && source.count >= loopFrames, "a loop needs its frames")
    var loop = Array(source[0..<loopFrames])
    let fade = min(fadeFrames, source.count - loopFrames, loopFrames)
    guard fade > 0 else { return loop }
    for index in 0..<fade {
        let t = (Float(index) + 0.5) / Float(fade)
        loop[index] = source[index] * sin(t * .pi / 2) + source[loopFrames + index] * cos(t * .pi / 2)
    }
    return loop
}
