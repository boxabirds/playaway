import Foundation

/// Keeps only the words sung inside a known vocal stretch (plus a tolerance at each edge), so that words an engine
/// invents over an instrumental passage are never shown.
package func gated(_ words: [TimedWord], toVocalRanges ranges: [ClosedRange<Double>], tolerance: Double = 0.3) -> [TimedWord] {
    guard !ranges.isEmpty else { return words }
    return words.filter { word in
        let middle = (word.start + word.end) / 2
        return ranges.contains { ($0.lowerBound - tolerance)...($0.upperBound + tolerance) ~= middle }
    }
}

/// Settings for the energy-based detector used on a separated vocal stem.
package struct EnergyGateSettings: Equatable, Sendable {
    /// How long each energy measurement is.
    package var window: Double = 0.05
    /// A window counts as singing when its level is within this many decibels of the loudest window.
    package var thresholdBelowPeakDB: Double = 30
    /// Silences shorter than this inside singing are kept as singing.
    package var minimumGap: Double = 0.4
    /// Singing shorter than this is ignored.
    package var minimumRange: Double = 0.2

    package init() {}
    package static let `default` = EnergyGateSettings()
}

/// The stretches of a mono signal that are loud enough to be singing, measured against the loudest moment of the
/// signal itself so the result does not depend on the recording level. Meant for a separated vocal stem; on a full
/// mix the music is loud everywhere and the result is one long range.
package func vocalRanges(energyOf samples: [Float], sampleRate: Double, settings: EnergyGateSettings = .default) -> [ClosedRange<Double>] {
    let windowSamples = max(1, Int(settings.window * sampleRate))
    guard !samples.isEmpty else { return [] }
    var levels: [Double] = []
    var index = 0
    while index < samples.count {
        let end = min(index + windowSamples, samples.count)
        var sum = 0.0
        for i in index..<end { sum += Double(samples[i]) * Double(samples[i]) }
        levels.append((sum / Double(end - index)).squareRoot())
        index = end
    }
    guard let peak = levels.max(), peak > 0 else { return [] }
    let threshold = peak * pow(10, -settings.thresholdBelowPeakDB / 20)
    var ranges: [ClosedRange<Double>] = []
    var startOfRun: Int?
    for (i, level) in levels.enumerated() {
        if level >= threshold {
            if startOfRun == nil { startOfRun = i }
        } else if let start = startOfRun {
            ranges.append(Double(start) * settings.window...Double(i) * settings.window)
            startOfRun = nil
        }
    }
    if let start = startOfRun { ranges.append(Double(start) * settings.window...Double(levels.count) * settings.window) }
    return merged(ranges, closerThan: settings.minimumGap).filter { $0.upperBound - $0.lowerBound >= settings.minimumRange }
}

/// Joins ranges whose gap is shorter than `gap`.
package func merged(_ ranges: [ClosedRange<Double>], closerThan gap: Double) -> [ClosedRange<Double>] {
    var out: [ClosedRange<Double>] = []
    for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
        if let last = out.last, range.lowerBound - last.upperBound < gap {
            out[out.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
        } else {
            out.append(range)
        }
    }
    return out
}
