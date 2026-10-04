import AppKit

/// The app's document controller. It supplies the playlist document type from code, so documents work the same
/// in the built app and in tests, and answers "is this playlist open, and is it playing?".
final class PlaylistDocumentController: NSDocumentController {
    static var current: PlaylistDocumentController {
        // The first controller created becomes the shared one; the app creates this one before AppKit asks.
        NSDocumentController.shared as! PlaylistDocumentController
    }

    override var defaultType: String? { playlistTypeIdentifier }
    override var documentClassNames: [String] { ["PlaylistDocument"] }

    override func documentClass(forType typeName: String) -> AnyClass? {
        typeName == playlistTypeIdentifier ? PlaylistDocument.self : nil
    }

    override func typeForContents(of url: URL) throws -> String {
        guard url.pathExtension.lowercased() == playlistFileExtension else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError)
        }
        return playlistTypeIdentifier
    }

    override func displayName(forType typeName: String) -> String? {
        typeName == playlistTypeIdentifier ? "LocalPlayer Playlist" : nil
    }

    private static let coreEventClass: AEEventClass = 0x6165_7674      // 'aevt'
    private static let openDocumentsEventID: AEEventID = 0x6F64_6F63   // 'odoc'

    /// Called after a playlist was opened the way Finder opens one (a double-click, a drop on the icon, `open`):
    /// the router starts it. File > Open and Open Recent open a playlist without starting it.
    var finderOpenHandler: ((PlaylistDocument?, URL, Error?) -> Void)?
    private var treatNextOpenAsFinder = false

    /// True while AppKit is handling an "open documents" Apple event, which is how Finder asks.
    private var isHandlingOpenDocumentsEvent: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventClass == Self.coreEventClass && event.eventID == Self.openDocumentsEventID
    }

    /// Opens a playlist with Finder semantics: shown in its own window and started unless already playing.
    func openLikeFinder(_ url: URL) {
        treatNextOpenAsFinder = true
        openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    override func openDocument(withContentsOf url: URL, display displayDocument: Bool,
                               completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void) {
        let likeFinder = treatNextOpenAsFinder || isHandlingOpenDocumentsEvent
        treatNextOpenAsFinder = false
        super.openDocument(withContentsOf: url, display: displayDocument) { [weak self] document, alreadyOpen, error in
            completionHandler(document, alreadyOpen, error)
            if likeFinder { self?.finderOpenHandler?(document as? PlaylistDocument, url, error) }
        }
    }

    var playlistDocuments: [PlaylistDocument] { documents.compactMap { $0 as? PlaylistDocument } }

    func isOpen(_ url: URL) -> Bool { document(for: url) != nil }

    func player(for url: URL) -> PlaylistPlayer? {
        (document(for: url) as? PlaylistDocument)?.player
    }

    /// The playlist whose window is frontmost, else the first open one.
    func frontPlaylistDocument() -> PlaylistDocument? {
        if let current = currentDocument as? PlaylistDocument { return current }
        for window in NSApp.orderedWindows {
            if let document = window.windowController?.document as? PlaylistDocument { return document }
        }
        return playlistDocuments.first
    }

    /// A playlist by the name shown in its window title, as scripts address them.
    func playlistDocument(named name: String) -> PlaylistDocument? {
        playlistDocuments.first { $0.displayName == name }
    }
}
