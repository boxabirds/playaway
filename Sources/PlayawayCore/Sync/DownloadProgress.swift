import Foundation

/// The platform's reported percent runs 0...reportedPercentFullScale. UNVERIFIED: Apple's reference says 100, some forum
/// posts say 1 (spike 31.1 did not observe a percent). Change this one constant when the spike settles it.
package let reportedPercentFullScale = 100.0

/// Maps a platform-reported percent to a 0...1 fraction. No progress for a missing or non-numeric value, or when the
/// platform does not report the song as downloading; clamped to 0...1; never below `previous` within one download.
package func downloadFraction(reported: Double?, isDownloading: Bool, previous: Double?) -> Double? {
    guard isDownloading, let reported, reported.isFinite else { return nil }
    let fraction = min(max(reported / reportedPercentFullScale, 0), 1)
    return max(fraction, previous ?? 0)
}
