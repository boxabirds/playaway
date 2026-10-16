import Foundation
import PlayawayCore

/// A model the app fetches once and keeps in its own Application Support folder. Models are not in the app bundle:
/// the person downloads them from the Experiments screen, knowing the size.
package struct ModelDownload: Sendable, Equatable {
    package let name: String
    package let bytes: Int64
    let base: URL
    let files: [String]
    let folder: String

    /// Where downloaded models live.
    package static func modelsDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Models", isDirectory: true)
    }

    package var directory: URL { Self.modelsDirectory().appendingPathComponent(folder, isDirectory: true) }

    package var isInstalled: Bool {
        files.allSatisfy { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
    }

    /// Fetches every file that is missing. `progress` is the share of files done.
    package func install(progress: @Sendable @escaping (Double) -> Void = { _ in }) async throws {
        for (index, file) in files.enumerated() {
            let destination = directory.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: destination.path) { continue }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let (temporary, response) = try await URLSession.shared.download(from: base.appendingPathComponent(file))
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else {
                throw LyricsError.unsupported("The model file \(file) could not be downloaded.")
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
            progress(Double(index + 1) / Double(files.count))
        }
    }

    package func remove() { try? FileManager.default.removeItem(at: directory) }

    /// UVR MDX-Net "Voc_FT" (MIT, Anjok07 and Kimberley Jensen; Core ML conversion by gyoom), the vocals model.
    package static let mdxVocals = ModelDownload(
        name: "Vocal separator (UVR MDX-Net Voc FT)", bytes: 33_494_078,
        base: URL(string: "https://huggingface.co/gyoom/UVR-MDX-CoreML/resolve/main/")!,
        files: ["UVR-MDX-NET-Voc_FT.mlpackage/Manifest.json",
                "UVR-MDX-NET-Voc_FT.mlpackage/Data/com.apple.CoreML/model.mlmodel",
                "UVR-MDX-NET-Voc_FT.mlpackage/Data/com.apple.CoreML/weights/weight.bin"],
        folder: "mdx-voc-ft")

    package var packageURL: URL { directory.appendingPathComponent(files[0]).deletingLastPathComponent() }
}
