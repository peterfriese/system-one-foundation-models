import Foundation
import FoundationModels
import UniformTypeIdentifiers
import CoreGraphics
import ImageIO

/// Utilities for extracting image attachments from Apple Foundation Models transcripts.
/// See `tech-notes/0015-clef-multimodal-token-estimation-and-data-url-encoding.md`.
public enum TranscriptAttachmentExtractor {
    /// Extracts and validates image attachments from the active turn of a Foundation Models transcript.
    public static func extractImages(from transcript: Transcript) throws -> [SystemOneImage] {
        var images: [SystemOneImage] = []
        let entries = Array(transcript)
        let activeStartIndex: Int
        if let lastResponseIndex = entries.lastIndex(where: {
            if case .response = $0 { return true }
            return false
        }) {
            activeStartIndex = entries.index(after: lastResponseIndex)
        } else {
            activeStartIndex = entries.startIndex
        }

        for entry in entries[activeStartIndex...] {
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
            if let url = imageAttachment.url,
               url.isFileURL,
               let image = try? extractImage(fromFileURL: url, identifier: attachmentSegment.label, maxDimension: 1024) {
                return image
            }
            let sourceImage = imageAttachment.cgImage
            let preservesAlpha = hasAlphaChannel(sourceImage)
            guard let scaledImage = downscaleCGImage(sourceImage, maxDimension: 1024) else {
                throw SystemOneError.modelExecutionError("Failed to downscale image attachment.")
            }
            if preservesAlpha {
                guard let pngData = encodePNG(scaledImage) else {
                    throw SystemOneError.modelExecutionError("Failed to convert alpha image attachment to PNG data.")
                }
                return SystemOneImage(data: pngData, format: .png, identifier: attachmentSegment.label)
            } else {
                guard let jpegData = encodeJPEG(scaledImage, quality: 0.8) else {
                    throw SystemOneError.modelExecutionError("Failed to convert opaque image attachment to JPEG data.")
                }
                return SystemOneImage(data: jpegData, format: .jpeg, identifier: attachmentSegment.label)
            }

        @unknown default:
            return nil
        }
    }

    /// Returns `true` when `cgImage` declares an active alpha channel that must be preserved losslessly.
    ///
    /// Standard iOS/macOS camera frames (`CVPixelBuffer` `32BGRA` -> `.noneSkipFirst`) and decoded
    /// JPEG/HEIC photos (`.noneSkipLast` / `.none`) return `false`, fast-pathing to single-pass JPEG.
    public static func hasAlphaChannel(_ cgImage: CGImage) -> Bool {
        switch cgImage.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            return true
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        @unknown default:
            return true
        }
    }

    /// Extracts an image from a local file URL, returning raw file bytes without bitmap decoding when
    /// already in a supported format (`PNG`, `JPEG`, `WebP`) within `maxDimension`, and downscaling via
    /// `ImageIO` thumbnailing when dimensions exceed `maxDimension`.
    public static func extractImage(
        fromFileURL url: URL,
        identifier: String? = nil,
        maxDimension: Int = 1024
    ) throws -> SystemOneImage {
        guard url.isFileURL else {
            throw SystemOneError.modelExecutionError("Image URL must be a local file URL.")
        }
        return try withAutoreleasePool {
            let resolvedIdentifier = identifier ?? url.lastPathComponent
            let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
                throw SystemOneError.modelExecutionError("Unable to open image source at file URL '\(url.lastPathComponent)'.")
            }

            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let pixelWidth = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
            let pixelHeight = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue

            let sourceFormat: SystemOneImage.Format? = {
                if let typeIdentifier = CGImageSourceGetType(source) as String?,
                   let utType = UTType(typeIdentifier),
                   let mapped = mapUTTypeToFormat(utType) {
                    return mapped
                }
                if let extType = UTType(filenameExtension: url.pathExtension) {
                    return mapUTTypeToFormat(extType)
                }
                return nil
            }()

            if let format = sourceFormat,
               let width = pixelWidth,
               let height = pixelHeight,
               width > 0,
               height > 0,
               max(width, height) <= maxDimension {
                let data = try Data(contentsOf: url)
                return SystemOneImage(data: data, format: format, identifier: resolvedIdentifier)
            }

            let thumbOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension
            ]
            let scaledImage: CGImage? = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
                ?? CGImageSourceCreateImageAtIndex(source, 0, nil).flatMap { downscaleCGImage($0, maxDimension: maxDimension) }

            guard let finalImage = scaledImage else {
                throw SystemOneError.modelExecutionError("Failed to decode or downscale image file '\(url.lastPathComponent)'.")
            }

            let propHasAlpha = (properties?[kCGImagePropertyHasAlpha] as? Bool) ?? false
            let preservesAlpha = propHasAlpha || hasAlphaChannel(finalImage)

            if preservesAlpha {
                guard let pngData = encodePNG(finalImage) else {
                    throw SystemOneError.modelExecutionError("Failed to encode downscaled file image as PNG.")
                }
                return SystemOneImage(data: pngData, format: .png, identifier: resolvedIdentifier)
            } else {
                guard let jpegData = encodeJPEG(finalImage, quality: 0.8) else {
                    throw SystemOneError.modelExecutionError("Failed to encode downscaled file image as JPEG.")
                }
                return SystemOneImage(data: jpegData, format: .jpeg, identifier: resolvedIdentifier)
            }
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

    private static func withAutoreleasePool<T>(_ body: () throws -> T) rethrows -> T {
        #if canImport(ObjectiveC)
        return try autoreleasepool(invoking: body)
        #else
        return try body()
        #endif
    }

    private static func downscaleCGImage(_ cgImage: CGImage, maxDimension: Int) -> CGImage? {
        withAutoreleasePool {
            let origWidth = cgImage.width
            let origHeight = cgImage.height
            let maxDim = max(origWidth, origHeight)
            guard maxDim > maxDimension else {
                return cgImage
            }

            let scale = Double(maxDimension) / Double(maxDim)
            let targetWidth = max(1, Int((Double(origWidth) * scale).rounded()))
            let targetHeight = max(1, Int((Double(origHeight) * scale).rounded()))

            let fallbackSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            let preferredSpace: CGColorSpace
            if let sourceSpace = cgImage.colorSpace, sourceSpace.model == .rgb {
                preferredSpace = sourceSpace
            } else {
                preferredSpace = fallbackSpace
            }

            let bitmapInfo = hasAlphaChannel(cgImage)
                ? CGImageAlphaInfo.premultipliedLast.rawValue
                : CGImageAlphaInfo.noneSkipLast.rawValue

            let context = CGContext(
                data: nil,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: preferredSpace,
                bitmapInfo: bitmapInfo
            ) ?? CGContext(
                data: nil,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: fallbackSpace,
                bitmapInfo: bitmapInfo
            )

            guard let context else {
                return nil
            }
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
            return context.makeImage()
        }
    }

    private static func encodeJPEG(_ cgImage: CGImage, quality: Double) -> Data? {
        withAutoreleasePool {
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
    }

    private static func encodePNG(_ cgImage: CGImage) -> Data? {
        withAutoreleasePool {
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
}
