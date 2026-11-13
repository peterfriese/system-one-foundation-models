import Foundation
import UniformTypeIdentifiers

/// Represents a strongly-typed image attachment for multimodal System One models like Cloudflare Clef.
/// See `tech-notes/0015-clef-multimodal-token-estimation-and-data-url-encoding.md`.
public struct SystemOneImage: Codable, Sendable, Equatable {
    /// Supported image format specification.
    public enum Format: String, Codable, Sendable, Equatable, CaseIterable {
        case png = "image/png"
        case jpeg = "image/jpeg"
        case webp = "image/webp"

        public var utType: UTType {
            switch self {
            case .png: return .png
            case .jpeg: return .jpeg
            case .webp: return .webP
            }
        }
    }

    /// Guardrail constants for Clef multimodal inference.
    public enum Guardrails {
        public static let maxImageCount: Int = 4
        public static let maxMegapixels: Double = 16.0
        public static let maxPayloadBytes: Int = 13 * 1024 * 1024 // 13 MiB
    }

    public let format: Format
    public let dataURL: String
    public let identifier: String?

    public init(format: Format, dataURL: String, identifier: String? = nil) {
        self.format = format
        self.dataURL = dataURL
        self.identifier = identifier
    }

    public init(data: Data, format: Format, identifier: String? = nil) {
        self.format = format
        let base64String = data.base64EncodedString()
        self.dataURL = "data:\(format.rawValue);base64,\(base64String)"
        self.identifier = identifier
    }

    public init(data: Data, mimeType: String, identifier: String? = nil) throws {
        guard let format = Format(rawValue: mimeType.lowercased()) else {
            throw SystemOneError.modelExecutionError("Unsupported image MIME type: \(mimeType). Supported formats: \(Format.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        self.init(data: data, format: format, identifier: identifier)
    }

    public init(data: Data, utType: UTType, identifier: String? = nil) throws {
        if utType.conforms(to: .png) {
            self.init(data: data, format: .png, identifier: identifier)
        } else if utType.conforms(to: .jpeg) {
            self.init(data: data, format: .jpeg, identifier: identifier)
        } else if utType.conforms(to: .webP) {
            self.init(data: data, format: .webp, identifier: identifier)
        } else {
            throw SystemOneError.modelExecutionError("Unsupported image UTType: \(utType.identifier). Supported formats: PNG, JPEG, WebP")
        }
    }

    public init(fileURL: URL, identifier: String? = nil) throws {
        guard fileURL.isFileURL else {
            throw SystemOneError.modelExecutionError("Image URL must be a local file:// URL, got '\(fileURL.scheme ?? "unknown")'.")
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw SystemOneError.modelExecutionError("Failed to read image file at '\(fileURL.path)': \(error.localizedDescription)")
        }
        let utType = UTType(filenameExtension: fileURL.pathExtension) ?? .data
        try self.init(data: data, utType: utType, identifier: identifier ?? fileURL.lastPathComponent)
    }

    public init(base64Encoded: String, format: Format, identifier: String? = nil) {
        let cleanBase64: String
        if base64Encoded.hasPrefix("data:") {
            if let commaIndex = base64Encoded.firstIndex(of: ",") {
                cleanBase64 = String(base64Encoded[base64Encoded.index(after: commaIndex)...])
            } else {
                cleanBase64 = base64Encoded
            }
        } else {
            cleanBase64 = base64Encoded
        }
        self.format = format
        self.dataURL = "data:\(format.rawValue);base64,\(cleanBase64)"
        self.identifier = identifier
    }

    /// Returns the raw Base64 string payload without the `data:...;base64,` prefix.
    public var base64DataString: String {
        if let commaIndex = dataURL.firstIndex(of: ",") {
            return String(dataURL[dataURL.index(after: commaIndex)...])
        }
        return dataURL
    }

    /// Decodes the underlying raw image `Data`.
    public var rawData: Data? {
        Data(base64Encoded: base64DataString)
    }

    // MARK: - Validation & Guardrails

    /// Validates an individual image against resolution limits (16MP) and payload constraints.
    public func validate() throws {
        guard let data = rawData else {
            throw SystemOneError.modelExecutionError("Invalid or corrupted base64 image data")
        }

        guard let dimensions = Self.extractDimensions(data: data, format: format) else {
            throw SystemOneError.modelExecutionError("Unable to verify image dimensions for format \(format.rawValue)")
        }

        let megapixels = (Double(dimensions.width) * Double(dimensions.height)) / 1_000_000.0
        if megapixels > Guardrails.maxMegapixels {
            throw SystemOneError.modelExecutionError("Image resolution (\(String(format: "%.1f", megapixels)) MP) exceeds maximum allowed \(Guardrails.maxMegapixels) MP")
        }
    }

    /// Validates an array of images against count, resolution, and total payload size guardrails.
    public static func validate(images: [SystemOneImage]) throws {
        if images.count > Guardrails.maxImageCount {
            throw SystemOneError.modelExecutionError("Image count (\(images.count)) exceeds maximum allowed of \(Guardrails.maxImageCount)")
        }

        var totalBytes = 0
        for image in images {
            try image.validate()
            totalBytes += image.dataURL.utf8.count
        }

        if totalBytes > Guardrails.maxPayloadBytes {
            throw SystemOneError.modelExecutionError("Total image payload size (\(totalBytes) bytes) exceeds maximum allowed of \(Guardrails.maxPayloadBytes) bytes (13 MiB)")
        }
    }

    /// Lightweight header-only dimension parser to avoid full bitmap decompression in memory.
    public static func extractDimensions(data: Data, format: Format) -> (width: Int, height: Int)? {
        let bytes = [UInt8](data)

        switch format {
        case .png:
            // PNG signature (8 bytes) + IHDR chunk header (4 length + 4 type) -> width at offset 16, height at offset 20
            let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
            let ihdrType: [UInt8] = [0x49, 0x48, 0x44, 0x52]
            guard bytes.count >= 24,
                  Array(bytes[0..<8]) == pngSignature,
                  Array(bytes[12..<16]) == ihdrType else {
                return nil
            }
            let width = (UInt32(bytes[16]) << 24) | (UInt32(bytes[17]) << 16) | (UInt32(bytes[18]) << 8) | UInt32(bytes[19])
            let height = (UInt32(bytes[20]) << 24) | (UInt32(bytes[21]) << 16) | (UInt32(bytes[22]) << 8) | UInt32(bytes[23])
            guard width > 0, height > 0 else { return nil }
            return (Int(width), Int(height))

        case .jpeg:
            // Verify JPEG SOI marker (0xFF 0xD8)
            guard bytes.count >= 11, bytes[0] == 0xFF, bytes[1] == 0xD8 else {
                return nil
            }
            var offset = 2
            while offset < bytes.count {
                while offset < bytes.count && bytes[offset] != 0xFF {
                    offset += 1
                }
                while offset < bytes.count && bytes[offset] == 0xFF {
                    offset += 1
                }
                guard offset < bytes.count else { break }
                let marker = bytes[offset]
                offset += 1

                // Stuffed byte (0x00), TEM (0x01), or RST0...RST7 (0xD0...0xD7), SOI (0xD8) have no length payload
                if marker == 0x00 || marker == 0x01 || (0xD0...0xD8).contains(marker) {
                    continue
                }
                // EOI (0xD9) or SOS (0xDA) ends header scanning
                if marker == 0xD9 || marker == 0xDA {
                    break
                }

                guard offset + 2 <= bytes.count else { return nil }
                let segLength = Int((UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1]))
                guard segLength >= 2, offset + segLength <= bytes.count else {
                    return nil
                }

                // SOF markers: 0xC0...0xCF excluding DHT (0xC4), JPG (0xC8), DAC (0xCC)
                let isSOF = (0xC0...0xCF).contains(marker) && marker != 0xC4 && marker != 0xC8 && marker != 0xCC
                if isSOF {
                    guard segLength >= 7, offset + 7 <= bytes.count else { return nil }
                    let height = Int((UInt16(bytes[offset + 3]) << 8) | UInt16(bytes[offset + 4]))
                    let width = Int((UInt16(bytes[offset + 5]) << 8) | UInt16(bytes[offset + 6]))
                    guard width > 0, height > 0 else { return nil }
                    return (width, height)
                }

                offset += segLength
            }
            return nil

        case .webp:
            // RIFF (4) + file size (4) + WEBP (4) + chunk fourcc (4) = 16 minimum header bytes
            let riffMagic: [UInt8] = [0x52, 0x49, 0x46, 0x46]
            let webpMagic: [UInt8] = [0x57, 0x45, 0x42, 0x50]
            guard bytes.count >= 16,
                  Array(bytes[0..<4]) == riffMagic,
                  Array(bytes[8..<12]) == webpMagic else {
                return nil
            }
            let chunkType = String(bytes: bytes[12..<16], encoding: .ascii)
            if chunkType == "VP8 " {
                // Lossy WebP keyframe check (0x9D 0x01 0x2A at offset 23..25)
                guard bytes.count >= 30 else { return nil }
                let width = Int((UInt16(bytes[26]) | (UInt16(bytes[27]) << 8)) & 0x3FFF)
                let height = Int((UInt16(bytes[28]) | (UInt16(bytes[29]) << 8)) & 0x3FFF)
                guard width > 0, height > 0 else { return nil }
                return (width, height)
            } else if chunkType == "VP8L" {
                // Lossless WebP (25 bytes minimum: 12 RIFF/WEBP + 8 chunk header + 1 signature 0x2F + 4 packed dim bytes)
                guard bytes.count >= 25 else { return nil }
                let b1 = UInt32(bytes[21])
                let b2 = UInt32(bytes[22])
                let b3 = UInt32(bytes[23])
                let b4 = UInt32(bytes[24])
                let width = 1 + Int(b1 | ((b2 & 0x3F) << 8))
                let height = 1 + Int((b2 >> 6) | (b3 << 2) | ((b4 & 0x0F) << 10))
                guard width > 0, height > 0 else { return nil }
                return (width, height)
            } else if chunkType == "VP8X" {
                // Extended WebP
                guard bytes.count >= 30 else { return nil }
                let w1 = UInt32(bytes[24])
                let w2 = UInt32(bytes[25])
                let w3 = UInt32(bytes[26])
                let h1 = UInt32(bytes[27])
                let h2 = UInt32(bytes[28])
                let h3 = UInt32(bytes[29])
                let width = 1 + Int(w1 | (w2 << 8) | (w3 << 16))
                let height = 1 + Int(h1 | (h2 << 8) | (h3 << 16))
                guard width > 0, height > 0 else { return nil }
                return (width, height)
            }
            return nil
        }
    }

    // MARK: - Codable Flexible Representation

    private enum CodingKeys: String, CodingKey {
        case format
        case contentType = "content_type"
        case dataURL = "data_url"
        case base64
        case identifier
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(dataURL)
    }

    public init(from decoder: Decoder) throws {
        // Supports decoding either as single string (RFC 2397 Data URL) or keyed container
        if let singleValueContainer = try? decoder.singleValueContainer(),
           let urlString = try? singleValueContainer.decode(String.self) {
            let parts = urlString.split(separator: ";")
            guard urlString.hasPrefix("data:"), parts.count >= 2 else {
                throw DecodingError.dataCorruptedError(in: singleValueContainer, debugDescription: "Invalid RFC 2397 Data URL: \(urlString)")
            }
            let mime = String(parts[0].dropFirst(5))
            guard let format = Format(rawValue: mime) else {
                throw DecodingError.dataCorruptedError(in: singleValueContainer, debugDescription: "Unsupported MIME format in data URL: \(mime)")
            }
            self.format = format
            self.dataURL = urlString
            self.identifier = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let formatString = try container.decodeIfPresent(String.self, forKey: .format)
            ?? container.decodeIfPresent(String.self, forKey: .contentType)
            ?? "image/jpeg"

        guard let format = Format(rawValue: formatString) else {
            throw DecodingError.dataCorruptedError(forKey: .format, in: container, debugDescription: "Unsupported format: \(formatString)")
        }
        self.format = format

        if let dataURL = try container.decodeIfPresent(String.self, forKey: .dataURL) {
            self.dataURL = dataURL
        } else if let base64 = try container.decodeIfPresent(String.self, forKey: .base64) {
            self.dataURL = "data:\(format.rawValue);base64,\(base64)"
        } else {
            throw DecodingError.dataCorruptedError(forKey: .dataURL, in: container, debugDescription: "Missing data_url or base64 field")
        }

        self.identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
    }
}
