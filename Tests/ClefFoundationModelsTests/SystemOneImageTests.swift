import Testing
import Foundation
import UniformTypeIdentifiers
import SystemOneCore
import ClefFoundationModels

@Suite("Clef Multimodal SystemOneImage Tests")
struct SystemOneImageTests {

    // MARK: - Sample Image Fixtures

    private static func makePNGData(width: UInt32 = 800, height: UInt32 = 600) -> Data {
        var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) // PNG magic
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x0D]) // IHDR length (13)
        data.append(contentsOf: [0x49, 0x48, 0x44, 0x52]) // "IHDR"
        withUnsafeBytes(of: width.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: height.bigEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: [0x08, 0x06, 0x00, 0x00, 0x00]) // 8-bit RGBA, compression, filter, interlace
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // dummy CRC
        return data
    }

    private static func makeJPEGData(width: UInt16 = 640, height: UInt16 = 480) -> Data {
        var data = Data([0xFF, 0xD8]) // SOI
        data.append(contentsOf: [0xFF, 0xC0]) // SOF0
        data.append(contentsOf: [0x00, 0x11]) // Length = 17
        data.append(0x08) // Precision = 8
        withUnsafeBytes(of: height.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: width.bigEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: [0x03, 0x01, 0x11, 0x00, 0x02, 0x11, 0x00, 0x03, 0x11, 0x00]) // 3 components
        data.append(contentsOf: [0xFF, 0xD9]) // EOI
        return data
    }

    private static func makeWebPData(width: UInt32 = 1024, height: UInt32 = 768) -> Data {
        var data = Data("RIFF".utf8)
        let totalSize: UInt32 = 38
        withUnsafeBytes(of: totalSize.littleEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: "WEBP".utf8)
        data.append(contentsOf: "VP8X".utf8)
        let chunkLength: UInt32 = 10
        withUnsafeBytes(of: chunkLength.littleEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Flags
        let wMinus1 = width - 1
        let hMinus1 = height - 1
        data.append(UInt8(wMinus1 & 0xFF))
        data.append(UInt8((wMinus1 >> 8) & 0xFF))
        data.append(UInt8((wMinus1 >> 16) & 0xFF))
        data.append(UInt8(hMinus1 & 0xFF))
        data.append(UInt8((hMinus1 >> 8) & 0xFF))
        data.append(UInt8((hMinus1 >> 16) & 0xFF))
        return data
    }

    // MARK: - Initialization Tests

    @Test("Initializes from raw Data with PNG, JPEG, and WebP MIME types")
    func testInitializationFromRawDataWithMimeTypes() throws {
        let pngData = Self.makePNGData()
        let pngImage = try SystemOneImage(data: pngData, mimeType: "image/png", identifier: "inspection.png")
        #expect(pngImage.format == .png)
        #expect(pngImage.identifier == "inspection.png")
        #expect(pngImage.dataURL.hasPrefix("data:image/png;base64,"))
        #expect(pngImage.rawData == pngData)

        let jpegData = Self.makeJPEGData()
        let jpegImage = try SystemOneImage(data: jpegData, mimeType: "image/jpeg", identifier: "photo.jpg")
        #expect(jpegImage.format == .jpeg)
        #expect(jpegImage.identifier == "photo.jpg")
        #expect(jpegImage.dataURL.hasPrefix("data:image/jpeg;base64,"))
        #expect(jpegImage.rawData == jpegData)

        let webpData = Self.makeWebPData()
        let webpImage = try SystemOneImage(data: webpData, mimeType: "image/webp", identifier: "defect.webp")
        #expect(webpImage.format == .webp)
        #expect(webpImage.identifier == "defect.webp")
        #expect(webpImage.dataURL.hasPrefix("data:image/webp;base64,"))
        #expect(webpImage.rawData == webpData)
    }

    @Test("Initializes from raw Data with UTType conforming to PNG, JPEG, WebP")
    func testInitializationFromUTType() throws {
        let pngData = Self.makePNGData()
        let png = try SystemOneImage(data: pngData, utType: .png, identifier: "a.png")
        #expect(png.format == .png)

        let jpegData = Self.makeJPEGData()
        let jpeg = try SystemOneImage(data: jpegData, utType: .jpeg, identifier: "b.jpg")
        #expect(jpeg.format == .jpeg)

        let webpData = Self.makeWebPData()
        let webp = try SystemOneImage(data: webpData, utType: .webP, identifier: "c.webp")
        #expect(webp.format == .webp)

        // Unsupported UTType throws modelExecutionError
        #expect(throws: SystemOneError.self) {
            try SystemOneImage(data: Data([1, 2, 3]), utType: .pdf)
        }
    }

    @Test("Rejects unsupported MIME types with descriptive error")
    func testRejectsUnsupportedMimeType() {
        let dummy = Data([0x00, 0x01])
        #expect(throws: SystemOneError.self) {
            try SystemOneImage(data: dummy, mimeType: "image/gif")
        }
        #expect(throws: SystemOneError.self) {
            try SystemOneImage(data: dummy, mimeType: "application/pdf")
        }
    }

    // MARK: - Base64 & Data URL Parsing Tests

    @Test("Base64 Data URL serialization and parsing roundtrip")
    func testBase64DataURLSerializationAndParsing() {
        let originalBytes = Data([0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE])
        let image = SystemOneImage(data: originalBytes, format: .jpeg, identifier: "chip.jpg")

        #expect(image.dataURL.hasPrefix("data:image/jpeg;base64,"))
        #expect(image.base64DataString == originalBytes.base64EncodedString())
        #expect(image.rawData == originalBytes)

        // Init from pure Base64 string
        let directBase64 = SystemOneImage(base64Encoded: originalBytes.base64EncodedString(), format: .jpeg)
        #expect(directBase64.rawData == originalBytes)
        #expect(directBase64.dataURL == image.dataURL)

        // Init from data URL string
        let fromDataURL = SystemOneImage(base64Encoded: image.dataURL, format: .jpeg)
        #expect(fromDataURL.rawData == originalBytes)
        #expect(fromDataURL.dataURL == image.dataURL)
    }

    @Test("Dimension parsing extracts accurate width and height from PNG, JPEG, and WebP headers")
    func testDimensionExtraction() {
        let png = Self.makePNGData(width: 1920, height: 1080)
        let pngDims = SystemOneImage.extractDimensions(data: png, format: .png)
        #expect(pngDims?.width == 1920)
        #expect(pngDims?.height == 1080)

        let jpeg = Self.makeJPEGData(width: 1280, height: 720)
        let jpegDims = SystemOneImage.extractDimensions(data: jpeg, format: .jpeg)
        #expect(jpegDims?.width == 1280)
        #expect(jpegDims?.height == 720)

        let webp = Self.makeWebPData(width: 800, height: 600)
        let webpDims = SystemOneImage.extractDimensions(data: webp, format: .webp)
        #expect(webpDims?.width == 800)
        #expect(webpDims?.height == 600)
    }

    // MARK: - Validation Guardrails Tests

    @Test("Image validation passes for images within 16 Megapixel limit")
    func testValidImageValidation() throws {
        let validPNG = Self.makePNGData(width: 4000, height: 3000) // 12 MP <= 16 MP
        let image = try SystemOneImage(data: validPNG, mimeType: "image/png")
        try image.validate()
    }

    @Test("Image validation fails when resolution exceeds 16 Megapixel limit")
    func testOversizedMegapixelValidationFails() throws {
        let oversizedPNG = Self.makePNGData(width: 5000, height: 4000) // 20 MP > 16 MP
        let image = try SystemOneImage(data: oversizedPNG, mimeType: "image/png")

        #expect(throws: SystemOneError.self) {
            try image.validate()
        }
    }

    @Test("Guardrails enforce maximum of 4 image attachments")
    func testMaxImageCountGuardrail() {
        let data = Self.makePNGData(width: 100, height: 100)
        let validSet = (1...4).map { SystemOneImage(data: data, format: .png, identifier: "img_\($0)") }
        #expect(throws: Never.self) {
            try SystemOneImage.validate(images: validSet)
        }

        let tooMany = (1...5).map { SystemOneImage(data: data, format: .png, identifier: "img_\($0)") }
        #expect(throws: SystemOneError.self) {
            try SystemOneImage.validate(images: tooMany)
        }
    }

    @Test("Guardrails enforce maximum 13 MiB total payload size limit")
    func testPayloadSizeGuardrail() {
        // Exceed 13 MiB limit (13 * 1024 * 1024 bytes)
        let oversizedBase64 = String(repeating: "A", count: 14 * 1024 * 1024)
        let oversizedImage = SystemOneImage(base64Encoded: oversizedBase64, format: .jpeg)

        #expect(throws: SystemOneError.self) {
            try SystemOneImage.validate(images: [oversizedImage])
        }
    }

    // MARK: - Codable Flexibility Tests

    @Test("Encodes directly as single string RFC 2397 Data URL format")
    func testEncodeAsDataURLString() throws {
        let raw = Data([0x01, 0x02, 0x03, 0x04])
        let image = SystemOneImage(data: raw, format: .jpeg, identifier: "cam_feed")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let encoded = try encoder.encode(image)
        let jsonString = try #require(String(data: encoded, encoding: .utf8))

        // Must encode strictly as a JSON string matching dataURL, NOT a JSON object
        #expect(jsonString == "\"\(image.dataURL)\"")
        #expect(!jsonString.hasPrefix("{"))

        let decodedString = try JSONDecoder().decode(String.self, from: encoded)
        #expect(decodedString == image.dataURL)

        // Roundtrip decoding produces matching dataURL and rawData
        let decoded = try JSONDecoder().decode(SystemOneImage.self, from: encoded)
        #expect(decoded.format == .jpeg)
        #expect(decoded.dataURL == image.dataURL)
        #expect(decoded.rawData == raw)
    }

    @Test("Decodes from single string RFC 2397 Data URL format")
    func testDecodeFromStringDataURL() throws {
        let raw = Data([0x01, 0x02, 0x03, 0x04])
        let dataURL = "data:image/png;base64,\(raw.base64EncodedString())"
        let json = "\"\(dataURL)\""

        let decoded = try JSONDecoder().decode(SystemOneImage.self, from: Data(json.utf8))
        #expect(decoded.format == .png)
        #expect(decoded.rawData == raw)
        #expect(decoded.dataURL == dataURL)
    }

    @Test("Decodes from structured dictionary object with format and data_url")
    func testDecodeFromStructuredJSON() throws {
        let raw = Data([0xAA, 0xBB, 0xCC])
        let json = """
        {
            "format": "image/webp",
            "data_url": "data:image/webp;base64,\(raw.base64EncodedString())",
            "identifier": "sensor_01"
        }
        """

        let decoded = try JSONDecoder().decode(SystemOneImage.self, from: Data(json.utf8))
        #expect(decoded.format == .webp)
        #expect(decoded.identifier == "sensor_01")
        #expect(decoded.rawData == raw)
    }
}
