import Foundation

/// A launch is cold when the app had not been opened since the device last started, warm otherwise.
package enum LaunchKind: String, Codable, Equatable {
    case cold
    case warm
}

package func launchKind(previousLaunch: Date?, deviceBoot: Date) -> LaunchKind {
    guard let previousLaunch else { return .cold }
    return previousLaunch < deviceBoot ? .cold : .warm
}

/// How long it took from the process starting to the first usable screen.
package struct LaunchReport: Codable, Equatable {
    package var kind: LaunchKind
    package var seconds: Double

    package init(kind: LaunchKind, seconds: Double) { self.kind = kind; self.seconds = seconds }
}

/// Measures one launch. A first-screen time before the process start (a clock change) reports 0.
package struct LaunchTimer {
    package let processStart: Date
    package let kind: LaunchKind

    package init(processStart: Date, kind: LaunchKind) { self.processStart = processStart; self.kind = kind }

    package func firstScreenShown(at time: Date) -> LaunchReport {
        LaunchReport(kind: kind, seconds: max(0, time.timeIntervalSince(processStart)))
    }
}

/// The most recent launch reports, kept so cold and warm can be compared separately.
package let launchReportsKept = 20
package let lastLaunchDefaultsKey = "lastLaunchDate"
package let launchReportsDefaultsKey = "launchReports"

package struct LaunchReportStore {
    private let defaults: UserDefaults

    package init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    package var lastLaunch: Date? { defaults.object(forKey: lastLaunchDefaultsKey) as? Date }
    package func noteLaunch(at date: Date) { defaults.set(date, forKey: lastLaunchDefaultsKey) }

    package func reports() -> [LaunchReport] {
        guard let data = defaults.data(forKey: launchReportsDefaultsKey),
              let reports = try? JSONDecoder().decode([LaunchReport].self, from: data) else { return [] }
        return reports
    }

    package func add(_ report: LaunchReport) {
        let kept = Array((reports() + [report]).suffix(launchReportsKept))
        if let data = try? JSONEncoder().encode(kept) { defaults.set(data, forKey: launchReportsDefaultsKey) }
    }

    /// The average of the kept reports of one kind, nil when there are none.
    package func average(_ kind: LaunchKind) -> Double? {
        let seconds = reports().filter { $0.kind == kind }.map(\.seconds)
        return seconds.isEmpty ? nil : seconds.reduce(0, +) / Double(seconds.count)
    }
}

/// Facts about the running process and the device, read from the system.
package enum LaunchFacts {
    package static func processStart() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }

    package static func deviceBoot() -> Date? {
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(boot.tv_sec) + TimeInterval(boot.tv_usec) / 1_000_000)
    }
}
