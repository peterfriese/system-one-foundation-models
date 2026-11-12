import Foundation
import FoundationModels
import UniformTypeIdentifiers
import CoreGraphics
import ImageIO

/// Utilities for extracting image attachments from Apple Foundation Models transcripts.
/// See `tech-notes/0015-clef-multimodal-token-estimation-and-data-url-encoding.md`.
public enum TranscriptAttachmentExtractor {
    /// Extracts and validates image attachments from a Foundation Models transcript.
    public static func extractImages(from transcript: Transcript) throws -> [SystemOneImage] {
        var images: [SystemOneImage] = []

        for entry in transcript {
            switch entry {
            case .prompt(let prompt):
                for segment in prompt.segments {
                    if let image = try extractImage(from: segment) {
                        images.append(image)
                    }
                }
            case .data(let dataEntry):
                guard let format = mapUTTypeToFormat(dataEntry.contentType) else {
                    throw SystemOneError.modelExecutionError("Unsupported data entry UTType '\(dataEntry.contentType.identifier)' in transcript.")
                }
                let image = SystemOneImage(data: dataEntry.content, format: format)
                images.append(image)
            default:
                break
            }
        }

        try SystemOneImage.validate(images: images)
        return images
    }

    /// Extracts an image from a `Transcript.Segment` if it is an attachment.
    public static func extractImage(from segment: Transcript.Segment) throws -> SystemOneImage? {
        guard case .attachment(let attachmentSegment) = segment else {
            return nil
        }

        switch attachmentSegment.content {
        case .data(let dataAttachment):
            guard let format = mapUTTypeToFormat(dataAttachment.contentType) else {
                throw SystemOneError.modelExecutionError("Unsupported attachment UTType '\(dataAttachment.contentType.identifier)' in transcript.")
            }
            return SystemOneImage(data: dataAttachment.content, format: format, identifier: attachmentSegment.label)

        case .image(let imageAttachment):
            if let url = imageAttachment.url, let image = try? SystemOneImage(fileURL: url, identifier: attachmentSegment.label) {
                return image
            }
            guard let scaledImage = downscaleCGImage(imageAttachment.cgImage, maxDimension: 1024) else {
                throw SystemOneError.modelExecutionError("Failed to downscale image attachment.")
            }
            let jpegData = encodeJPEG(scaledImage, quality: 0.8)
            let pngData = encodePNG(scaledImage)
            if let png = pngData, let jpeg = jpegData {
                if png.count <= jpeg.count {
                    return SystemOneImage(data: png, format: .png, identifier: attachmentSegment.label)
                } else {
                    return SystemOneImage(data: jpeg, format: .jpeg, identifier: attachmentSegment.label)
                }
            } else if let jpeg = jpegData {
                return SystemOneImage(data: jpeg, format: .jpeg, identifier: attachmentSegment.label)
            } else if let png = pngData {
                return SystemOneImage(data: png, format: .png, identifier: attachmentSegment.label)
            }
            throw SystemOneError.modelExecutionError("Failed to convert image attachment to JPEG or PNG data.")

        @unknown default:
            return nil
        }
    }

    /// Maps a `UTType` to supported `SystemOneImage.Format`.
    public static func mapUTTypeToFormat(_ type: UTType) -> SystemOneImage.Format? {
        if type.conforms(to: .png) { return .png }
        if type.conforms(to: .jpeg) { return .jpeg }
        if type.conforms(to: .webP) { return .webp }
        return nil
    }

    /// Scales down a `CGImage` if its maximum dimension exceeds `maxDimension` and compresses as JPEG.
    public static func convertCGImageToJPEG(
        _ cgImage: CGImage,
        maxDimension: Int = 1024,
        quality: Double = 0.8
    ) -> Data? {
        guard let finalImage = downscaleCGImage(cgImage, maxDimension: maxDimension) else {
            return nil
        }
        return encodeJPEG(finalImage, quality: quality)
    }

    /// Scales down a `CGImage` if its maximum dimension exceeds `maxDimension` and encodes as lossless PNG.
    public static func convertCGImageToPNG(
        _ cgImage: CGImage,
        maxDimension: Int = 1024
    ) -> Data? {
        guard let finalImage = downscaleCGImage(cgImage, maxDimension: maxDimension) else {
            return nil
        }
        return encodePNG(finalImage)
    }

    // MARK: - Private Image Helpers

    private static func downscaleCGImage(_ cgImage: CGImage, maxDimension: Int) -> CGImage? {
        let origWidth = cgImage.width
        let origHeight = cgImage.height
        let maxDim = max(origWidth, origHeight)
        guard maxDim > maxDimension else {
            return cgImage
        }

        let scale = Double(maxDimension) / Double(maxDim)
        let targetWidth = max(1, Int((Double(origWidth) * scale).rounded()))
        let targetHeight = max(1, Int((Double(origHeight) * scale).rounded()))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage()
    }

    private static func encodeJPEG(_ cgImage: CGImage, quality: Double) -> Data? {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }

    private static func encodePNG(_ cgImage: CGImage) -> Data? {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }
}
