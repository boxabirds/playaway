import Foundation
import PlayawayCore

/// How often a download in progress is checked, and how long it may go without the system reporting that it is
/// downloading before it is treated as failed.
private let pollInterval: TimeInterval = 0.5
private let stallTimeout: TimeInterval = 30

/// The iPhone side of download-on-play: reads where a song's file is and starts, watches and stops downloads from
/// iCloud. The percentage the system reports has never been observed on a device, so progress is reported without
/// one and the pie stays indeterminate. The system offers no way to cancel a download that has started, so
/// cancelling only stops watching it.
@MainActor
final class CloudSongs: SongDownloading {
    /// Where events for the shared coordinator go.
    var onEvent: ((DownloadEvent) -> Void)?
    /// False when no iCloud account is signed in: cloud icons are then not shown at all.
    let isAvailable: Bool

    private var urls: [SongID: URL] = [:]
    private var timers: [SongID: Timer] = [:]
    private var lastActivity: [SongID: Date] = [:]
    /// Test aid: songs the app pretends are in iCloud and not on the device, with how their download should go.
    private var scripted: [SongID: ScriptedDownload] = [:]

    enum ScriptedDownload { case succeeds(after: TimeInterval), fails(after: TimeInterval) }

    init() {
        isAvailable = FileManager.default.ubiquityIdentityToken != nil
    }

    #if DEBUG
    /// A fake cloud for UI tests: the named files count as not on this device until a scripted download finishes.
    init(scripted names: [String: ScriptedDownload]) {
        isAvailable = true
        for (name, script) in names { scripted[SongID(name)] = script }
    }
    #endif

    func id(for url: URL) -> SongID {
        let song = SongID(url.path)
        urls[song] = url
        return song
    }

    /// Test aid: in a fake cloud, files under this folder count as iCloud Drive files.
    var fakeRoot: URL?

    /// The system's answer for whether a file is an iCloud Drive file, nil when it could not be asked.
    nonisolated static func isUbiquitous(_ url: URL, fakeRoot: URL?) -> Bool? {
        // In the fake cloud, a song whose name starts with "Demo Five" is an iCloud Drive file outside the Playaway folder.
        if let fakeRoot { return isStrictlyInside(url, folder: fakeRoot) || url.lastPathComponent.hasPrefix("Demo Five") }
        return try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem
    }

    func presence(of url: URL) -> SongPresence {
        if let script = scriptedEntry(for: url) { return script.finished ? .inCloudOnDevice : .inCloudNotOnDevice }
        if let fakeRoot {
            return songPresence(isUbiquitous: Self.isUbiquitous(url, fakeRoot: fakeRoot) ?? false, downloadingStatus: nil)
        }
        // An offloaded file is not at its path; the system's placeholder beside it says it is in iCloud and not here.
        if !FileManager.default.fileExists(atPath: url.path), iCloudPlaceholderExists(for: url) { return .inCloudNotOnDevice }
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        return songPresence(isUbiquitous: values?.isUbiquitousItem ?? false,
                            downloadingStatus: values?.ubiquitousItemDownloadingStatus?.rawValue)
    }

    // MARK: SongDownloading

    func startDownload(of song: SongID) {
        guard let url = urls[song] else { onEvent?(.failed(song)); return }
        lastActivity[song] = Date()
        if scriptedEntry(for: url) != nil { startScripted(song, url: url); return }
        do { try FileManager.default.startDownloadingUbiquitousItem(at: url) }
        catch { onEvent?(.failed(song)); return }
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll(song) }
        }
        RunLoop.main.add(timer, forMode: .common)    // `startDownloadingUbiquitousItem` needs a running run loop
        timers[song]?.invalidate()
        timers[song] = timer
    }

    func cancelDownload(of song: SongID) {
        timers[song]?.invalidate(); timers[song] = nil
        lastActivity[song] = nil
    }

    // MARK: Watching

    private func poll(_ song: SongID) {
        guard let url = urls[song] else { return }
        let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey,
                                                       .ubiquitousItemDownloadingErrorKey])
        let status = values?.ubiquitousItemDownloadingStatus?.rawValue
        if status == ubiquitousStatusCurrent || status == ubiquitousStatusDownloaded {
            finish(song); onEvent?(.finished(song)); return
        }
        if values?.ubiquitousItemDownloadingError != nil { finish(song); onEvent?(.failed(song)); return }
        if values?.ubiquitousItemIsDownloading == true { lastActivity[song] = Date() }
        else if let last = lastActivity[song], Date().timeIntervalSince(last) > stallTimeout {
            finish(song); onEvent?(.failed(song)); return
        }
        onEvent?(.progress(song, reportedPercent: nil))
    }

    private func finish(_ song: SongID) {
        timers[song]?.invalidate(); timers[song] = nil
        lastActivity[song] = nil
    }

    // MARK: Scripted downloads (tests)

    private var scriptedFinished: Set<SongID> = []
    private func scriptedEntry(for url: URL) -> (script: ScriptedDownload, finished: Bool)? {
        for (key, script) in scripted where url.lastPathComponent.hasPrefix(key.raw) {
            return (script, scriptedFinished.contains(SongID(url.path)))
        }
        return nil
    }

    private func startScripted(_ song: SongID, url: URL) {
        guard let entry = scriptedEntry(for: url) else { return }
        let delay: TimeInterval
        let succeeds: Bool
        switch entry.script { case .succeeds(let d): delay = d; succeeds = true; case .fails(let d): delay = d; succeeds = false }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.timers[song] != nil else { return }
                self.timers[song] = nil
                if succeeds { self.scriptedFinished.insert(song); self.onEvent?(.finished(song)) }
                else { self.onEvent?(.failed(song)) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        timers[song]?.invalidate()
        timers[song] = timer
    }
}
