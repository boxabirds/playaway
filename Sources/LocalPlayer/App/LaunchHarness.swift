import Foundation

/// The result of one measured launch. `invalid` is never a pass: it covers a missing stop timestamp
/// (timeout) and elapsed times of zero or less.
enum LaunchVerdict: Equatable {
    case withinBudget(ms: Int)
    case overBudget(ms: Int)
    case invalid

    var isPass: Bool {
        if case .withinBudget = self { return true }
        return false
    }
}

protocol LaunchVerdictCalculating {
    /// `nil` means the stop timestamp was never observed before the timeout.
    func verdict(elapsedMilliseconds: Int?) -> LaunchVerdict
}

/// Compares an elapsed time with the budget. The budget itself is inclusive: exactly the budget is within it.
struct LaunchVerdictCalculator: LaunchVerdictCalculating {
    let budgetMilliseconds: Int

    init(budgetMilliseconds: Int = launchBudgetMilliseconds) {
        self.budgetMilliseconds = budgetMilliseconds
    }

    func verdict(elapsedMilliseconds: Int?) -> LaunchVerdict {
        guard let elapsed = elapsedMilliseconds, elapsed > 0 else { return .invalid }
        return elapsed <= budgetMilliseconds ? .withinBudget(ms: elapsed) : .overBudget(ms: elapsed)
    }
}

/// Converts the harness start and the app's stop timestamp (both CLOCK_MONOTONIC_RAW nanoseconds) to whole
/// milliseconds. A partial millisecond rounds up so a run is never reported faster than it was.
/// Returns nil when no stop timestamp was observed. A stop before the start yields a non-positive value.
enum LaunchElapsed {
    static let nanosecondsPerMillisecond: Int64 = 1_000_000

    static func milliseconds(startNanoseconds: UInt64, stopNanoseconds: UInt64?) -> Int? {
        guard let stop = stopNanoseconds else { return nil }
        let delta = Int64(bitPattern: stop &- startNanoseconds)
        let wholeMilliseconds = delta / nanosecondsPerMillisecond
        let hasRemainder = delta % nanosecondsPerMillisecond > 0
        return Int(wholeMilliseconds) + (hasRemainder ? 1 : 0)
    }
}

enum LaunchTemperature: String, Equatable {
    case cold, warm
}

/// One batch of launches of one temperature class. Cold and warm batches are separate values and are never merged.
struct LaunchBatchResult {
    let temperature: LaunchTemperature
    let verdicts: [LaunchVerdict]
    /// True when a cold batch was produced by purging the file cache (a proxy for a restart), so reports can flag it.
    let coldIsCachePurgeProxy: Bool

    init(temperature: LaunchTemperature, verdicts: [LaunchVerdict], coldIsCachePurgeProxy: Bool = false) {
        self.temperature = temperature
        self.verdicts = verdicts
        self.coldIsCachePurgeProxy = coldIsCachePurgeProxy
    }

    /// The batch fails when any run is over budget or invalid, and when it has no runs at all.
    var passes: Bool { !verdicts.isEmpty && verdicts.allSatisfy(\.isPass) }
    var batchVerdict: LaunchVerdict {
        guard !verdicts.isEmpty, !verdicts.contains(.invalid) else { return .invalid }
        let overBudget = verdicts.compactMap { verdict -> Int? in
            if case .overBudget(let ms) = verdict { return ms }
            return nil
        }
        if let worst = overBudget.max() { return .overBudget(ms: worst) }
        let worstWithin = verdicts.compactMap { verdict -> Int? in
            if case .withinBudget(let ms) = verdict { return ms }
            return nil
        }.max() ?? 0
        return .withinBudget(ms: worstWithin)
    }
}

/// Reports for two batches, kept apart: one line group per temperature class.
struct LaunchReport {
    let batches: [LaunchBatchResult]

    func batches(of temperature: LaunchTemperature) -> [LaunchBatchResult] {
        batches.filter { $0.temperature == temperature }
    }
}
