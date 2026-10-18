import PlayawayCore
import AppKit

/// The one number the launch target lives in: the app, the harness and the tests all use it.
let launchBudgetMilliseconds = 1000
let launchRunsPerBatch = 10

enum LaunchPhase: String { case launching, windowShown, running }

@MainActor
protocol FirstWindowObserver: AnyObject {
    func firstWindowPresented()
}

@MainActor
protocol LaunchTracing: AnyObject {
    func record(_ phase: LaunchPhase)
}

/// Writes the phase timestamps to a results file when `LOCALPLAYER_LAUNCH_TRACE` names one; does nothing otherwise.
/// Timestamps use the monotonic raw clock so the harness can compare them with its own start time.
@MainActor
final class LaunchTrace: LaunchTracing {
    static let environmentKey = "LOCALPLAYER_LAUNCH_TRACE"
    private let resultsPath: String?
    private(set) var recorded: [(phase: LaunchPhase, nanoseconds: UInt64)] = []
    private let clock: () -> UInt64

    init(resultsPath: String?, clock: @escaping () -> UInt64 = { clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) }) {
        self.resultsPath = resultsPath
        self.clock = clock
    }

    convenience init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.init(resultsPath: environment[Self.environmentKey])
    }

    func record(_ phase: LaunchPhase) {
        let now = clock()
        recorded.append((phase, now))
        guard let resultsPath else { return }
        let line = "{\"phase\":\"\(phase.rawValue)\",\"nanoseconds\":\(now)}\n"
        if let handle = FileHandle(forWritingAtPath: resultsPath) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(toFile: resultsPath, atomically: false, encoding: .utf8)
        }
    }

    /// Parses a results file back to the timestamp of a phase.
    static func timestamp(of phase: LaunchPhase, inFileAt path: String) -> UInt64? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["phase"] as? String == phase.rawValue,
                  let value = object["nanoseconds"] as? NSNumber else { continue }
            return value.uint64Value
        }
        return nil
    }
}

@MainActor
protocol LaunchWindowProviding {
    /// Makes sure a playlist window is on screen (restored, or a new untitled one) and calls back once it is shown.
    func presentFirstWindow(completion: @escaping () -> Void)
}

/// Does only what is needed to put the first playlist window on screen, then tells the observers once.
/// The updater, the audio engine, the network and track-reference resolution all wait for that signal.
@MainActor
final class LaunchCoordinator {
    private let trace: LaunchTracing
    private let observers: [FirstWindowObserver]
    private let windows: LaunchWindowProviding
    private(set) var phase: LaunchPhase = .launching
    private var started = false

    init(trace: LaunchTracing, observers: [FirstWindowObserver], windows: LaunchWindowProviding) {
        self.trace = trace
        self.observers = observers
        self.windows = windows
    }

    func start() {
        guard !started else { return }
        started = true
        trace.record(.launching)
        windows.presentFirstWindow { [weak self] in self?.windowPresented() }
    }

    private func windowPresented() {
        guard phase == .launching else { return }
        phase = .windowShown
        LaunchState.firstWindowPresented = true
        trace.record(.windowShown)
        observers.forEach { $0.firstWindowPresented() }
        phase = .running
        trace.record(.running)
    }
}

/// The real window provider. AppKit restores last session's windows asynchronously, so this waits for the first
/// playlist window to appear instead of guessing. Only if none appeared within a short grace period (nothing to
/// restore) does it open an untitled playlist, so a window is always shown and never doubled.
@MainActor
struct DocumentLaunchWindows: LaunchWindowProviding {
    static let fallbackSeconds: TimeInterval = 0.35

    func presentFirstWindow(completion: @escaping () -> Void) {
        FirstWindowWait(controller: PlaylistDocumentController.current, completion: completion).start(fallbackSeconds: Self.fallbackSeconds)
    }
}

/// One wait for the first playlist window: ends when a playlist window becomes key, or, if none has appeared after the
/// grace period, after opening an untitled playlist. Keeps itself alive until it has finished.
@MainActor
private final class FirstWindowWait {
    private let controller: PlaylistDocumentController
    private let completion: () -> Void
    private var finished = false
    private var observer: NSObjectProtocol?
    private var keepAlive: FirstWindowWait?

    init(controller: PlaylistDocumentController, completion: @escaping () -> Void) {
        self.controller = controller
        self.completion = completion
    }

    private func hasWindow() -> Bool {
        controller.playlistDocuments.contains { document in document.windowControllers.contains { $0.window?.isVisible == true } }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        if let observer { NotificationCenter.default.removeObserver(observer) }
        // The window is ordered front in this turn of the run loop; observers hear about it in the next.
        Task { @MainActor in
            self.completion()
            self.keepAlive = nil
        }
    }

    func start(fallbackSeconds: TimeInterval) {
        keepAlive = self
        if hasWindow() { finish(); return }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            nonisolated(unsafe) let window = note.object                  // delivered on the main queue
            MainActor.assumeIsolated {
                if (window as? NSWindow)?.windowController is PlaylistWindowController { self?.finish() }
            }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(fallbackSeconds))
            guard !self.finished else { return }
            if !self.hasWindow() { _ = try? self.controller.openUntitledDocumentAndDisplay(true) }
            self.finish()
        }
    }
}

/// Track-reference resolution for documents restored at launch waits for the first window.
@MainActor
final class DocumentResolutionObserver: FirstWindowObserver {
    func firstWindowPresented() {
        PlaylistDocumentController.current.playlistDocuments.forEach { $0.firstWindowPresented() }
    }
}
