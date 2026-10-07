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
        let data = try Data(contentsOf: fileURL)
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

        if let dimensions = Self.extractDimensions(data: data, format: format) {
            let megapixels = Double(dimensions.width * dimensions.height) / 1_000_000.0
            if megapixels > Guardrails.maxMegapixels {
                throw SystemOneError.modelExecutionError("Image resolution (\(String(format: "%.1f", megapixels)) MP) exceeds maximum allowed \(Guardrails.maxMegapixels) MP")
            }
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
        switch format {
        case .png:
            // PNG signature (8 bytes) + IHDR chunk header (4 length + 4 type) -> width at offset 16, height at offset 20
            guard data.count >= 24 else { return nil }
            let width = data[16..<20].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
            let height = data[20..<24].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
            return (Int(width), Int(height))

        case .jpeg:
            // Scan for SOF0 (0xFF, 0xC0) or SOF2 (0xFF, 0xC2) markers
            var offset = 2
            while offset < data.count - 8 {
                if data[offset] == 0xFF {
                    let marker = data[offset + 1]
                    if marker == 0xC0 || marker == 0xC1 || marker == 0xC2 {
                        let height = data[(offset + 5)..<(offset + 7)].withUnsafeBytes { $0.loadUnaligned(as: UInt16.self).bigEndian }
                        let width = data[(offset + 7)..<(offset + 9)].withUnsafeBytes { $0.loadUnaligned(as: UInt16.self).bigEndian }
                        return (Int(width), Int(height))
                    } else if marker == 0xD9 || marker == 0xDA {
                        // End of image or start of scan
                        break
                    } else {
                        // Advance by marker segment length
                        let length = data[(offset + 2)..<(offset + 4)].withUnsafeBytes { $0.loadUnaligned(as: UInt16.self).bigEndian }
                        offset += 2 + Int(length)
                    }
                } else {
                    offset += 1
                }
            }
            return nil

        case .webp:
            // RIFF header (4) + file size (4) + WEBP (4) + VP8/VP8L/VP8X header
            guard data.count >= 30 else { return nil }
            let chunkType = String(data: data[12..<16], encoding: .ascii)
            if chunkType == "VP8 " {
                // Keyframe check
                guard data.count >= 26 else { return nil }
                let width = data[26..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt16.self).littleEndian } & 0x3FFF
                let height = data[28..<30].withUnsafeBytes { $0.loadUnaligned(as: UInt16.self).littleEndian } & 0x3FFF
                return (Int(width), Int(height))
            } else if chunkType == "VP8L" {
                // Lossless WebP
                guard data.count >= 25 else { return nil }
                let b1 = UInt32(data[21])
                let b2 = UInt32(data[22])
                let b3 = UInt32(data[23])
                let b4 = UInt32(data[24])
                let width = 1 + Int((b1 | ((b2 & 0x3F) << 8)))
                let height = 1 + Int(((b2 >> 6) | (b3 << 2) | ((b4 & 0xF) << 10)))
                return (width, height)
            } else if chunkType == "VP8X" {
                // Extended WebP
                guard data.count >= 30 else { return nil }
                let w1 = UInt32(data[24])
                let w2 = UInt32(data[25])
                let w3 = UInt32(data[26])
                let h1 = UInt32(data[27])
                let h2 = UInt32(data[28])
                let h3 = UInt32(data[29])
                let width = 1 + Int(w1 | (w2 << 8) | (w3 << 16))
                let height = 1 + Int(h1 | (h2 << 8) | (h3 << 16))
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
