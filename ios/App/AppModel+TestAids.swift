#if DEBUG
import Foundation
import PlayawayCore
import CryptoKit

// Test aids for the UI tests: seeded playlists, fake drives, a slow folder search. None of it ships in a release build.
extension AppModel {
    /// Test aid: a playlist of two short generated tones, so UI tests can play real files.
    /// A WAV of the given length. Silent: the tests never listen, and a simulator plays through the Mac's speakers
    /// while someone is working.
    static func tone(_ seconds: Int, hz: Double) -> Data {
        let rate = 8000, samples = rate * seconds
        var d = Data()
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(36 + samples * 2); d.append("WAVEfmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(samples * 2)
        let amplitude = 0.0
        for i in 0..<samples { var v = Int16(sin(2 * .pi * hz * Double(i) / Double(rate)) * amplitude).littleEndian; d.append(Data(bytes: &v, count: 2)) }
        return d
    }

    /// A playlist as a Mac writes it into the Playaway folder: its own folder, the songs beside it, and every
    /// reference an alias and a path made on the Mac, which this phone can follow by neither.
    func seedForeignPlaylist(in cloudRoot: URL) {
        let name = "From Mac"
        let folder = cloudRoot.appendingPathComponent(name)
        let file = folder.appendingPathComponent(name).appendingPathExtension(playlistFileExtension)
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let macRoot = "/Users/someone/Library/Mobile Documents/\(CloudFolder.containerFolderName)/Documents/\(name)"
        var tracks: [Track] = []
        for (song, hz) in [("Mac One", 330.0), ("Mac Two", 390.0)] {
            let songFile = "\(song).wav"
            try? Self.tone(60, hz: hz).write(to: folder.appendingPathComponent(songFile))
            tracks.append(Track(id: UUID(), reference: TrackReference(bookmark: Data(), lastKnownPath: "\(macRoot)/\(songFile)", fileName: songFile)))
        }
        _ = PlaylistStore().save(Playlist(tracks: tracks), to: file)
        // The bytes as seeded, for the file-unchanged check made from outside the simulator (story 37 TC-21).
        if let data = try? Data(contentsOf: file) {
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            try? digest.write(to: folder.appendingPathComponent("\(name).seed.sha256"), atomically: true, encoding: .utf8)
        }
    }

    /// Test aid (story 40): what the owner's library looks like. The song is in iCloud Drive/Mixdowns (the fake drive
    /// stands in), the playlist is in the Playaway folder, and its reference is in build-22 form: a bookmark that resolves
    /// nowhere, the iPhone's absolute path, the file name, no cloud path. The migration derives the location.
    func seedDrivePlaylist(in cloudRoot: URL, drive: URL) {
        let name = "Mixdowns Picks"
        let folder = cloudRoot.appendingPathComponent(name)
        let file = folder.appendingPathComponent(name).appendingPathExtension(playlistFileExtension)
        let songs = [("Mixdowns", "Demo Drive.wav", 350.0), ("Mixdowns/Live", "Demo Live.wav", 410.0)]
        for (dirName, songFile, hz) in songs {
            let dir = drive.appendingPathComponent(dirName, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: dir.appendingPathComponent(songFile).path) { try? Self.tone(60, hz: hz).write(to: dir.appendingPathComponent(songFile)) }
        }
        // A folder with songs that are not in the playlist, and the folder of a song added later, for the wrong-folder and add cases.
        try? FileManager.default.createDirectory(at: drive.appendingPathComponent("Empty", isDirectory: true), withIntermediateDirectories: true)
        try? Self.tone(60, hz: 300).write(to: drive.appendingPathComponent("Empty/Unrelated.wav"))
        try? FileManager.default.createDirectory(at: drive.appendingPathComponent("Other", isDirectory: true), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: drive.appendingPathComponent("Other/Demo Added.wav").path) {
            try? Self.tone(60, hz: 450).write(to: drive.appendingPathComponent("Other/Demo Added.wav"))
        }
        seedMovedDrivePlaylist(in: cloudRoot, drive: drive)
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let prefix = "/private/var/mobile/Library/Mobile Documents/\(CloudFolder.driveFolderName)/"
        let tracks = songs.map { dirName, songFile, _ in
            Track(id: UUID(), reference: TrackReference(bookmark: Data(), lastKnownPath: "\(prefix)\(dirName)/\(songFile)", fileName: songFile))
        }
        _ = PlaylistStore().save(Playlist(tracks: tracks), to: file)
    }

    /// Test aid: a song that moved inside the folder since the playlist was made (saved in Mixdowns/Old, now in Mixdowns/New),
    /// so restoring has to search the folder, which is what takes time on a big iCloud folder.
    func seedMovedDrivePlaylist(in cloudRoot: URL, drive: URL) {
        let name = "Mixdowns Moved"
        let folder = cloudRoot.appendingPathComponent(name)
        let file = folder.appendingPathComponent(name).appendingPathExtension(playlistFileExtension)
        let now = drive.appendingPathComponent("Mixdowns/New", isDirectory: true)
        try? FileManager.default.createDirectory(at: now, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: now.appendingPathComponent("Demo Moved.wav").path) { try? Self.tone(60, hz: 280).write(to: now.appendingPathComponent("Demo Moved.wav")) }
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let saved = "/private/var/mobile/Library/Mobile Documents/\(CloudFolder.driveFolderName)/Mixdowns/Old/Demo Moved.wav"
        let track = Track(id: UUID(), reference: TrackReference(bookmark: Data(), lastKnownPath: saved, fileName: "Demo Moved.wav"))
        _ = PlaylistStore().save(Playlist(tracks: [track]), to: file)
    }

    /// Test aid (story 41): a song added from a folder this device was not allowed to read, as the file chooser would
    /// add it. `-PlayawayFakeDrive` shows a button for it in a playlist.
    func addFakeDriveSong(to session: PlaylistSession) {
        guard let drive = fakeDriveRoot, var reference = TrackReference.make(for: drive.appendingPathComponent("Other/Demo Added.wav")) else { return }
        reference.cloudPath = .iCloudDrive("Other/Demo Added.wav")      // the fake drive's path is not iCloud's, so say where it is in iCloud Drive
        let track = Track(id: UUID(), reference: reference)
        var playlist = session.playlist
        playlist.tracks.append(track)
        session.apply(playlist)
        considerNudge(after: [track])
    }

    /// Test aid (story 42): two songs a Mac added from its own Music folder (a dead bookmark, a Mac path, no place in
    /// iCloud) and one that is here, so rows can be compared.
    func seedElsewherePlaylist(in cloudRoot: URL) {
        let name = "From Mac Music"
        let folder = cloudRoot.appendingPathComponent(name)
        let file = folder.appendingPathComponent(name).appendingPathExtension(playlistFileExtension)
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let here = folder.appendingPathComponent("Elsewhere Here.wav")
        try? Self.tone(60, hz: 500).write(to: here)
        var tracks = ["Elsewhere One", "Elsewhere Two"].map {
            Track(id: UUID(), reference: TrackReference(bookmark: Data(), lastKnownPath: "/Users/someone/Music/\($0).mp3", fileName: "\($0).mp3"))
        }
        tracks.append(Track(id: UUID(), reference: TrackReference(bookmark: Data(), lastKnownPath: here.canonicalPath, fileName: "Elsewhere Here.wav")))
        _ = PlaylistStore().save(Playlist(tracks: tracks), to: file)
    }

    /// Test aid (story 40, TC-35): the phone that made the playlist. One song resolves by its own path on this device
    /// (its file is in the fake drive at the stored path), one was renamed since and is gone. The device can read the
    /// folder, so no permission is asked; the gone song is reported as gone when tapped.
    func seedMixedDrivePlaylist(in cloudRoot: URL, drive: URL) {
        let name = "Mixdowns Mixed"
        let folder = cloudRoot.appendingPathComponent(name)
        let file = folder.appendingPathComponent(name).appendingPathExtension(playlistFileExtension)
        let mixdowns = drive.appendingPathComponent("Mixdowns", isDirectory: true)
        try? FileManager.default.createDirectory(at: mixdowns, withIntermediateDirectories: true)
        let here = mixdowns.appendingPathComponent("Demo Here.wav")
        if !FileManager.default.fileExists(atPath: here.path) { try? Self.tone(60, hz: 370).write(to: here) }
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let gonePath = "/private/var/mobile/Library/Mobile Documents/\(CloudFolder.driveFolderName)/Mixdowns/Demo Renamed.wav"
        let tracks = [Track(id: UUID(), reference: TrackReference(bookmark: Data(), lastKnownPath: here.canonicalPath, fileName: "Demo Here.wav",
                                                                   cloudPath: .iCloudDrive("Mixdowns/Demo Here.wav"))),
                      Track(id: UUID(), reference: TrackReference(bookmark: Data(), lastKnownPath: gonePath, fileName: "Demo Renamed.wav"))]
        _ = PlaylistStore().save(Playlist(tracks: tracks), to: file)
    }

    /// What the other device does: a coordinated write of the open playlist's file with a new song beside it, dated a
    /// moment later, from off the main thread, as iCloud's arrival would be.
    func rewriteOpenPlaylistAsAnotherDevice() {
        guard let url = path.last else { return }
        let folder = url.deletingLastPathComponent()
        let song = folder.appendingPathComponent("Added Elsewhere.wav")
        try? Self.tone(30, hz: 300).write(to: song)
        DispatchQueue.global().async {
            let store = PlaylistStore()
            guard case .loaded(var playlist) = store.load(from: url), let reference = TrackReference.make(for: song) else { return }
            playlist.tracks.append(Track(id: UUID(), reference: reference))
            _ = store.save(playlist, to: url)
            try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: url.path)
        }
    }

    func seedDemoPlaylist(in folder: URL, keepExisting: Bool) {

        var urls: [URL] = []
        for (name, hz) in [("Demo One", 440.0), ("Demo Two", 520.0), ("Demo Three", 600.0), ("Demo Four", 680.0), ("Demo Five", 760.0)] {
            let url = folder.appendingPathComponent("\(name).wav")
            if !FileManager.default.fileExists(atPath: url.path) { try? Self.tone(60, hz: hz).write(to: url) }
            urls.append(url)
        }
        // Start every seeded launch from the same playlist, whatever earlier tests changed, unless a test is checking
        // what a second launch remembers.
        if keepExisting, FileManager.default.fileExists(atPath: folder.appendingPathComponent("Demo.\(playlistFileExtension)").path) || (cloudLibrary?.entries().contains { $0.name == "Demo" } ?? false) { return }
        if let leftovers = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for file in leftovers where file.pathExtension == playlistFileExtension { try? FileManager.default.removeItem(at: file) }
        }
        guard let playlistURL = try? library.create(named: "Demo") else { return }
        // A list longer than the screen, so tests can scroll to the last song.
        let repeats = ProcessInfo.processInfo.arguments.contains("-PlayawayLongList") ? 6 : 1
        var songs = Array(repeating: urls, count: repeats).flatMap { $0 }
        // Test aid: a song whose file is gone, as when an old playlist's songs were moved or deleted since it was made.
        let goneSong = folder.appendingPathComponent("Gone Song.wav")
        if ProcessInfo.processInfo.arguments.contains("-PlayawaySeedGoneSong") {
            try? Self.tone(5, hz: 300).write(to: goneSong)
            songs.append(goneSong)
        }
        let result = adding(songs, to: Playlist(), classifier: FormatClassifier())
        _ = library.save(result.playlist, to: playlistURL)
        try? FileManager.default.removeItem(at: goneSong)
    }

    /// Test aid: show a stand-in chooser inside the real sheet, which closes the sheet before it answers, as the system's does.
    static var fakesTheChooserSheet: Bool { ProcessInfo.processInfo.arguments.contains("-PlayawayFakeSheetPicker") }
    /// What the stand-in chooser answers with: the folder being asked for, in the fake drive.
    func fakeChooserAnswer() -> URL? {
        guard let fakeDriveRoot, let session = restoreSession, let folder = recoveryPlan(for: session)?.folders.first else { return nil }
        return fakeDriveRoot.appendingPathComponent(folder.drivePath, isDirectory: true)
    }
    /// Test aid: what the system chooser would return. `-PlayawayFakePick <path under the fake drive | cancel>`;
    /// by default the folder being asked for.
    static func fakePick(in drive: URL, default folder: String) -> URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let at = arguments.firstIndex(of: "-PlayawayFakePick"), at + 1 < arguments.count else {
            return drive.appendingPathComponent(folder, isDirectory: true)
        }
        let choice = arguments[at + 1]
        return choice == "cancel" ? nil : drive.appendingPathComponent(choice, isDirectory: true)
    }

    /// Test aid: `-PlayawayRestoreDelay <seconds>` makes the search of a folder take that long, so the progress card can be seen.
    static var restoreDelay: TimeInterval? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let at = arguments.firstIndex(of: "-PlayawayRestoreDelay"), at + 1 < arguments.count else { return nil }
        return TimeInterval(arguments[at + 1])
    }
}

/// Test aid: a folder search that takes a set time, in small steps, so the progress card can be seen and cancelled.
struct SlowFolderListing: FolderListing {
    let delay: TimeInterval
    func entries(under folder: URL, progress: (Int) -> Void, isCancelled: () -> Bool) -> [TreeEntry] {
        let step = 0.1
        var looked = 0
        var waited = 0.0
        while waited < delay, !isCancelled() { Thread.sleep(forTimeInterval: step); waited += step; looked += 50; progress(looked) }
        return SystemFolderListing().entries(under: folder, progress: progress, isCancelled: isCancelled)
    }
}
#endif
