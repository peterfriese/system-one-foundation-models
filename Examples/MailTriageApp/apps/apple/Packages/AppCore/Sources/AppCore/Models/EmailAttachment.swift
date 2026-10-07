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
}

extension Attachment where Content == ImageAttachmentContent {
    /// Convenience initializer to construct a multimodal image attachment from raw image Data.
    public init(_ data: Data, type: UTType = .png) {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            self.init(cgImage)
        } else {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let ctx = CGContext(
                data: nil,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            self.init(ctx.makeImage()!)
        }
    }
}
