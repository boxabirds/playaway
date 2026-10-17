import Foundation
import Accelerate
import CoreML
import PlayawayCore

/// Vocal separation with the UVR MDX-Net Voc FT model on Core ML. The model is only the network: this class does the
/// chunking, the STFT in and out, and the overlap-add. Reads and writes files; never plays anything.
package final class MDXNetSeparator: VocalSeparating, @unchecked Sendable {
    static let nFFT = 6144
    static let hop = 1024
    static let dimF = 3072
    static let dimT = 256
    static let chunkSamples = (dimT - 1) * hop        // 261,120 samples: 256 frames once centre padding is added
    static let overlapFraction = 10                     // chunks overlap by a tenth, crossfaded linearly

    private let download: ModelDownload
    private let computeUnits: MLComputeUnits
    private var model: MLModel?
    private let stft = ShortTimeFourier(n: MDXNetSeparator.nFFT, hop: MDXNetSeparator.hop, bins: MDXNetSeparator.dimF)

    package init(download: ModelDownload = .mdxVocals, computeUnits: MLComputeUnits = .all) {
        self.download = download
        self.computeUnits = computeUnits
    }

    package var isAvailable: Bool { download.isInstalled }

    private func loadedModel() throws -> MLModel {
        if let model { return model }
        guard download.isInstalled else { throw LyricsError.unsupported("The vocal separator model is not downloaded.") }
        let compiled = try MLModel.compileModel(at: download.packageURL)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        let model = try MLModel(contentsOf: compiled, configuration: configuration)
        self.model = model
        return model
    }

    package func separateVocals(from url: URL, into directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let model = try loadedModel()
        let mix = try AudioSamples.read(url)
        let vocals = try separate(mix, with: model, progress: progress)
        let out = directory.appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-vocals.wav")
        try AudioSamples.writeWav(vocals, to: out)
        progress(1)
        return out
    }

    /// The whole song, chunk by chunk with a linear crossfade over the overlap.
    func separate(_ mix: AudioSamples.Stereo, with model: MLModel, progress: @escaping @Sendable (Double) -> Void = { _ in }) throws -> AudioSamples.Stereo {
        let chunk = Self.chunkSamples
        let overlap = chunk / Self.overlapFraction
        let length = mix.left.count
        var outL = [Float](repeating: 0, count: length), outR = outL, weight = outL
        var start = 0
        while start < length {
            progress(Double(start) / Double(length))
            let valid = min(chunk, length - start)
            var l = Array(mix.left[start..<start + valid]), r = Array(mix.right[start..<start + valid])
            if valid < chunk { l += [Float](repeating: 0, count: chunk - valid); r += [Float](repeating: 0, count: chunk - valid) }
            let v = try separateChunk(l, r, with: model)
            for i in 0..<valid {
                let fadeIn = start > 0 && i < overlap ? Float(i) / Float(overlap) : 1
                let fadeOut = i >= chunk - overlap ? Float(chunk - i) / Float(overlap) : 1
                let w = min(fadeIn, fadeOut)
                outL[start + i] += v.left[i] * w
                outR[start + i] += v.right[i] * w
                weight[start + i] += w
            }
            start += chunk - overlap
        }
        for i in 0..<length where weight[i] > 0 { outL[i] /= weight[i]; outR[i] /= weight[i] }
        return AudioSamples.Stereo(left: outL, right: outR, rate: mix.rate)
    }

    /// One chunk of exactly `chunkSamples` per channel: STFT, the network, inverse STFT.
    /// The model speaks half floats; Accelerate converts whole planes at once, on Apple silicon and Intel alike (the
    /// `Float16` type itself does not exist on Intel Macs).
    private static func writeHalves(_ floats: [Float], into array: MLMultiArray) {
        floats.withUnsafeBufferPointer { source in
            var from = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: source.baseAddress!), height: 1,
                                     width: vImagePixelCount(floats.count), rowBytes: floats.count * MemoryLayout<Float>.size)
            var to = vImage_Buffer(data: array.dataPointer, height: 1, width: vImagePixelCount(floats.count),
                                   rowBytes: floats.count * MemoryLayout<UInt16>.size)
            vImageConvert_PlanarFtoPlanar16F(&from, &to, 0)
        }
    }

    private static func readHalves(from array: MLMultiArray) -> [Float] {
        var floats = [Float](repeating: 0, count: array.count)
        floats.withUnsafeMutableBufferPointer { destination in
            var from = vImage_Buffer(data: array.dataPointer, height: 1, width: vImagePixelCount(array.count),
                                     rowBytes: array.count * MemoryLayout<UInt16>.size)
            var to = vImage_Buffer(data: destination.baseAddress!, height: 1, width: vImagePixelCount(array.count),
                                   rowBytes: array.count * MemoryLayout<Float>.size)
            vImageConvert_Planar16FtoPlanarF(&from, &to, 0)
        }
        return floats
    }

    func separateChunk(_ l: [Float], _ r: [Float], with model: MLModel) throws -> (left: [Float], right: [Float]) {
        let dimF = Self.dimF, dimT = Self.dimT
        let sl = stft.transform(l), sr = stft.transform(r)
        let input = try MLMultiArray(shape: [1, 4, NSNumber(value: dimF), NSNumber(value: dimT)], dataType: .float16)
        var planes = [Float](repeating: 0, count: input.count)
        for (plane, spec) in [sl.re, sl.im, sr.re, sr.im].enumerated() {
            for bin in 0..<dimF { for frame in 0..<dimT { planes[((plane * dimF) + bin) * dimT + frame] = spec[frame][bin] } }
        }
        Self.writeHalves(planes, into: input)
        let inputName = model.modelDescription.inputDescriptionsByName.keys.first ?? "input"
        let outputName = model.modelDescription.outputDescriptionsByName.keys.first ?? "output"
        let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: [inputName: input]))
        guard let stems = out.featureValue(for: outputName)?.multiArrayValue else {
            throw LyricsError.unsupported("The separator model gave no output.")
        }
        let q = Self.readHalves(from: stems)
        var re = [[[Float]]](repeating: [[Float]](repeating: [Float](repeating: 0, count: dimF), count: dimT), count: 2)
        var im = re
        for channel in 0..<2 {
            for bin in 0..<dimF {
                for frame in 0..<dimT {
                    re[channel][frame][bin] = q[((channel * 2 * dimF) + bin) * dimT + frame]
                    im[channel][frame][bin] = q[((channel * 2 + 1) * dimF + bin) * dimT + frame]
                }
            }
        }
        return (stft.inverseTransform(re: re[0], im: im[0], length: l.count),
                stft.inverseTransform(re: re[1], im: im[1], length: r.count))
    }
}
