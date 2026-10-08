import Foundation
import FoundationModels
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Represents a binary attachment associated with an email message.
public struct EmailAttachment: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public var filename: String
    public var mimeType: String
    public var data: Data
    public var fileSizeBytes: Int

    public init(
        id: UUID = UUID(),
        filename: String,
        mimeType: String,
        data: Data,
        fileSizeBytes: Int? = nil
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
        self.fileSizeBytes = fileSizeBytes ?? data.count
    }

    /// Returns `true` if the attachment's MIME type or file extension represents an image supported by multimodal vision models.
    public var isImage: Bool {
        let lowerMime = mimeType.lowercased()
        let lowerFilename = filename.lowercased()
        if lowerMime.contains("png") || lowerMime.contains("jpeg") || lowerMime.contains("jpg") || lowerMime.contains("webp") {
            return true
        }
        if lowerFilename.hasSuffix(".png") || lowerFilename.hasSuffix(".jpg") || lowerFilename.hasSuffix(".jpeg") || lowerFilename.hasSuffix(".webp") {
            return true
        }
        return false
    }

    /// User-facing formatted file size (e.g. "48 KB", "1.2 MB").
    public var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSizeBytes), countStyle: .file)
    }

    /// Maps the attachment's MIME type or filename to a supported image `UTType` (`.png`, `.jpeg`, `.webP`), defaulting to `.png`.
    public var utType: UTType {
        let lowerMime = mimeType.lowercased()
        if lowerMime.contains("jpeg") || lowerMime.contains("jpg") {
            return .jpeg
        } else if lowerMime.contains("webp") {
            return .webP
        } else if lowerMime.contains("png") {
            return .png
        }

        let lowerFilename = filename.lowercased()
        if lowerFilename.hasSuffix(".jpg") || lowerFilename.hasSuffix(".jpeg") {
            return .jpeg
        } else if lowerFilename.hasSuffix(".webp") {
            return .webP
        } else if lowerFilename.hasSuffix(".png") {
            return .png
        }

        if let direct = UTType(mimeType: mimeType),
           direct.conforms(to: .jpeg) || direct.conforms(to: .webP) || direct.conforms(to: .png) {
            return direct
        }

        return .png
    }
}

extension Attachment where Content == ImageAttachmentContent {
    /// Convenience initializer to construct a multimodal image attachment from raw image Data.
    public init?(_ data: Data, type: UTType = .png) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        self.init(cgImage)
    }
}
