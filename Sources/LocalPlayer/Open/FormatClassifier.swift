import Foundation
import UniformTypeIdentifiers

enum SupportedFormat: String, CaseIterable, Equatable {
    case mp3, wav, m4a

    var displayName: String { rawValue.uppercased() }
}

enum UnsupportedReason: Equatable {
    case unknownType(String)
    case fileNotReadable
}

enum FormatClassification: Equatable {
    case supported(SupportedFormat)
    case unsupported(UnsupportedReason)
}

protocol FormatClassifying {
    func classify(_ url: URL) -> FormatClassification
}

/// Single decision point for which files the player accepts (mp3, wav, m4a).
/// Reads file metadata and, as a last resort, the first bytes. Never throws and never writes.
struct FormatClassifier: FormatClassifying {
    private static let sniffByteCount = 12
    private static let id3Tag = Array("ID3".utf8)
    private static let mpegFrameSyncMask: UInt8 = 0xE0
    private static let mpegFrameSyncByte: UInt8 = 0xFF
    private static let riffTag = Array("RIFF".utf8)
    private static let waveTag = Array("WAVE".utf8)
    private static let ftypTag = Array("ftyp".utf8)
    private static let m4aBrands: [[UInt8]] = [Array("M4A ".utf8), Array("M4B ".utf8)]
    private static let riffFormatOffset = 8
    private static let ftypOffset = 4
    private static let brandOffset = 8
    private static let tagLength = 4

    func classify(_ url: URL) -> FormatClassification {
        var isDirectory: ObjCBool = false
        let path = url.path
        guard !path.isEmpty,
              FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: path) else {
            return .unsupported(.fileNotReadable)
        }

        let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        if let type = contentType, let format = Self.format(for: type) {
            return .supported(format)
        }
        let ext = url.pathExtension.lowercased()
        if let format = Self.format(forExtension: ext) {
            return .supported(format)
        }
        if let format = Self.sniffFormat(at: url) {
            return .supported(format)
        }
        let description = contentType?.localizedDescription ?? (ext.isEmpty ? "unknown" : ext)
        return .unsupported(.unknownType(description))
    }

    private static func format(for type: UTType) -> SupportedFormat? {
        if type.conforms(to: .mp3) { return .mp3 }
        if type.conforms(to: .wav) { return .wav }
        if type.conforms(to: .mpeg4Audio) { return .m4a }
        return nil
    }

    private static func format(forExtension ext: String) -> SupportedFormat? {
        switch ext {
        case "mp3": return .mp3
        case "wav", "wave": return .wav
        case "m4a": return .m4a
        default: return nil
        }
    }

    private static func sniffFormat(at url: URL) -> SupportedFormat? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: sniffByteCount), data.count >= sniffByteCount else { return nil }
        let bytes = [UInt8](data)
        if Array(bytes[0..<id3Tag.count]) == id3Tag { return .mp3 }
        if bytes[0] == mpegFrameSyncByte, bytes[1] & mpegFrameSyncMask == mpegFrameSyncMask { return .mp3 }
        if Array(bytes[0..<tagLength]) == riffTag,
           Array(bytes[riffFormatOffset..<(riffFormatOffset + tagLength)]) == waveTag { return .wav }
        if Array(bytes[ftypOffset..<(ftypOffset + tagLength)]) == ftypTag,
           m4aBrands.contains(Array(bytes[brandOffset..<(brandOffset + tagLength)])) { return .m4a }
        return nil
    }
}
