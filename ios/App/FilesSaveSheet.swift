import UIKit
import PlayawayCore

/// The system Files save sheet, behind the core's `SaveSheet` seam. It is given a finished playlist file and
/// returns where the person put it, nil when they cancelled.
@MainActor
final class FilesSaveSheet: NSObject, SaveSheet, UIDocumentPickerDelegate {
    private var continuation: CheckedContinuation<URL?, Error>?

    nonisolated func save(fileAt temporary: URL, suggestedName: String) async throws -> URL? {
        try await present(temporary)
    }

    private func present(_ temporary: URL) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            guard let presenter = Self.topViewController() else {
                continuation.resume(throwing: CocoaError(.userCancelled)); return
            }
            self.continuation = continuation
            let picker = UIDocumentPickerViewController(forExporting: [temporary], asCopy: true)
            picker.delegate = self
            presenter.present(picker, animated: true)
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        continuation?.resume(returning: urls.first); continuation = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        continuation?.resume(returning: nil); continuation = nil
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
