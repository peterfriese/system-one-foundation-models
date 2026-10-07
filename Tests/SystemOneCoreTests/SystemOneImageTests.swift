import Testing
import Foundation
import UniformTypeIdentifiers
import SystemOneCore

@Suite("SystemOneImage & Multimodal Core Tests")
struct SystemOneImageTests {

    @Test("SystemOneImage initializes from Data with mimeType and encodes RFC 2397 Data URL")
    func testImageInitializationFromData() throws {
        let dummyData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) // PNG header
        let image = try SystemOneImage(data: dummyData, mimeType: "image/png", identifier: "test.png")

        #expect(image.format == .png)
        #expect(image.identifier == "test.png")
        #expect(image.dataURL.hasPrefix("data:image/png;base64,"))
        #expect(image.rawData == dummyData)
    }

    @Test("SystemOneImage initializes from UTType correctly")
    func testImageInitializationFromUTType() throws {
        let dummyData = Data([0xFF, 0xD8, 0xFF, 0xE0]) // JPEG header
        let image = try SystemOneImage(data: dummyData, utType: .jpeg, identifier: "photo.jpg")

        #expect(image.format == .jpeg)
        #expect(image.identifier == "photo.jpg")
        #expect(image.dataURL.hasPrefix("data:image/jpeg;base64,"))
    }

    @Test("SystemOneImage roundtrip encoding with Codable encodes directly as Data URL string")
    func testImageCodableRoundtrip() throws {
        let dummyData = Data("hello world".utf8)
        let image = SystemOneImage(data: dummyData, format: .webp)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(image)

        let jsonString = try #require(String(data: data, encoding: .utf8))
        #expect(jsonString == "\"\(image.dataURL)\"")

        let decodedString = try JSONDecoder().decode(String.self, from: data)
        #expect(decodedString == image.dataURL)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SystemOneImage.self, from: data)

        #expect(decoded == image)
        #expect(decoded.format == .webp)
        #expect(decoded.dataURL == image.dataURL)
        #expect(decoded.rawData == dummyData)
    }

    @Test("SystemOneImage guardrail enforces maximum 4 images")
    func testImageCountGuardrail() {
        let dummyData = Data([0x01, 0x02, 0x03])
        let images = (1...5).map { idx in
            SystemOneImage(data: dummyData, format: .jpeg, identifier: "img_\(idx).jpg")
        }

        #expect(throws: SystemOneError.self) {
            try SystemOneImage.validate(images: images)
        }
    }

    @Test("SystemOneRequest encoding excludes images when nil or empty for backward compatibility")
    func testRequestEncodingBackwardCompatibility() throws {
        let requestWithoutImages = SystemOneRequest(
            state: "Text state",
            model: "systemone-default",
            questions: [:]
        )

        let encoder = JSONEncoder()
        let dataWithoutImages = try encoder.encode(requestWithoutImages)
        let jsonWithoutImages = try #require(String(data: dataWithoutImages, encoding: .utf8))
        #expect(!jsonWithoutImages.contains("\"images\""))

        let image = SystemOneImage(data: Data([1, 2, 3]), format: .jpeg)
        let requestWithImages = SystemOneRequest(
            state: "Multimodal state",
            model: "@cf/cloudflare/clef-flash",
            questions: [:],
            images: [image]
        )
        let dataWithImages = try encoder.encode(requestWithImages)
        let jsonWithImages = try #require(String(data: dataWithImages, encoding: .utf8))
        #expect(jsonWithImages.contains("\"images\""))
    }
}
