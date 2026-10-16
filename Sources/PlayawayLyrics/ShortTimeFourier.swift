import Foundation
import Accelerate

/// The STFT and its inverse exactly as the UVR MDX-Net models were trained with: periodic Hann window, centred with
/// reflect padding, unnormalised, the Nyquist bin dropped. Wrong parameters do not fail; they give muddy stems, so the
/// forward scale is checked against an analytic sine in the tests.
final class ShortTimeFourier {
    let n: Int
    let hop: Int
    let bins: Int
    let window: [Float]
    private let forward: vDSP_DFT_Setup
    private let inverse: vDSP_DFT_Setup

    init(n: Int, hop: Int, bins: Int) {
        self.n = n
        self.hop = hop
        self.bins = bins
        window = (0..<n).map { 0.5 - 0.5 * cos(2 * Float.pi * Float($0) / Float(n)) }
        forward = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(n), .FORWARD)!
        inverse = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(n), .INVERSE)!
    }

    deinit {
        vDSP_DFT_DestroySetup(forward)
        vDSP_DFT_DestroySetup(inverse)
    }

    /// How many frames a signal of `length` samples gives (centre padding adds one).
    func frames(for length: Int) -> Int { 1 + length / hop }

    private func padded(_ x: [Float]) -> [Float] {
        let p = n / 2
        let left = (1...p).reversed().map { x[min($0, x.count - 1)] }
        let right = (1...p).map { x[max(x.count - 1 - $0, 0)] }
        return left + x + right
    }

    /// Spectrogram as `re[frame][bin]`, `im[frame][bin]`, the plain DFT of each windowed frame.
    func transform(_ signal: [Float]) -> (re: [[Float]], im: [[Float]]) {
        let x = padded(signal)
        let frameCount = 1 + (x.count - n) / hop
        var re = [[Float]](repeating: [Float](repeating: 0, count: bins), count: frameCount)
        var im = re
        var frame = [Float](repeating: 0, count: n)
        var evens = [Float](repeating: 0, count: n / 2), odds = evens
        var outRe = [Float](repeating: 0, count: n / 2), outIm = outRe
        for t in 0..<frameCount {
            let start = t * hop
            x.withUnsafeBufferPointer { p in vDSP_vmul(p.baseAddress! + start, 1, window, 1, &frame, 1, vDSP_Length(n)) }
            for i in 0..<(n / 2) { evens[i] = frame[2 * i]; odds[i] = frame[2 * i + 1] }
            vDSP_DFT_Execute(forward, evens, odds, &outRe, &outIm)
            // The real DFT returns twice the mathematical value, with the Nyquist bin packed into outIm[0].
            for k in 0..<bins { re[t][k] = outRe[k] * 0.5; im[t][k] = (k == 0 ? 0 : outIm[k]) * 0.5 }
        }
        return (re, im)
    }

    /// Weighted overlap-add inverse (window-squared normalisation, as torch.istft), trimmed to `length` samples.
    func inverseTransform(re: [[Float]], im: [[Float]], length: Int) -> [Float] {
        let frameCount = re.count
        let total = n + (frameCount - 1) * hop
        var y = [Float](repeating: 0, count: total)
        var norm = [Float](repeating: 0, count: total)
        var inRe = [Float](repeating: 0, count: n / 2), inIm = inRe
        var evens = [Float](repeating: 0, count: n / 2), odds = evens
        var windowSquared = [Float](repeating: 0, count: n)
        vDSP_vsq(window, 1, &windowSquared, 1, vDSP_Length(n))
        let scale = 1 / Float(2 * n)                     // the real inverse DFT returns 2N times the signal
        for t in 0..<frameCount {
            for k in 0..<bins { inRe[k] = re[t][k] * 2; inIm[k] = im[t][k] * 2 }
            inIm[0] = 0
            vDSP_DFT_Execute(inverse, inRe, inIm, &evens, &odds)
            let start = t * hop
            for i in 0..<(n / 2) {
                y[start + 2 * i] += evens[i] * scale * window[2 * i]
                y[start + 2 * i + 1] += odds[i] * scale * window[2 * i + 1]
            }
            for i in 0..<n { norm[start + i] += windowSquared[i] }
        }
        let p = n / 2
        return (0..<length).map { i in
            let j = p + i
            return j < total && norm[j] > 1e-8 ? y[j] / norm[j] : 0
        }
    }
}
