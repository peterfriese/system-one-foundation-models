import Testing
import Foundation
import CoreGraphics
import ImageIO
import FoundationModels
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

    @Test("TranscriptAttachmentExtractor preserves alpha as PNG and fast-paths opaque camera frames to single-pass JPEG")
    func testAlphaPNGPreservationAndOpaqueJPEGFastPath() async throws {
        let p3Space = try #require(CGColorSpace(name: CGColorSpace.displayP3))

        // 1. RGBA image with actual semi-transparent pixels and noisy color gradients (where JPEG would be smaller,
        //    but PNG must be selected to preserve alpha fidelity)
        let width = 128
        let height = 128
        var rgbaPixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                let alpha: UInt8 = (x < 64) ? 0 : 128
                rgbaPixels[idx] = UInt8((x * 17 + y * 31) & 0xFF) &* alpha / 255
                rgbaPixels[idx + 1] = UInt8((x * 53 + y * 11) & 0xFF) &* alpha / 255
                rgbaPixels[idx + 2] = UInt8((x * 97 + y * 7) & 0xFF) &* alpha / 255
                rgbaPixels[idx + 3] = alpha
            }
        }
        let alphaImage: CGImage = try rgbaPixels.withUnsafeMutableBytes { buf in
            let ctx = try #require(CGContext(
                data: buf.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: p3Space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            return try #require(ctx.makeImage())
        }
        #expect(TranscriptAttachmentExtractor.hasAlphaChannel(alphaImage) == true)

        let alphaCapture = VisionAttachmentCaptureBox()
        let alphaSession = LanguageModelSession(model: VisionAttachmentCaptureModel(box: alphaCapture))
        let alphaPrompt = Prompt {
            "Check icon alpha"
            Attachment(alphaImage)
        }
        _ = try await alphaSession.respond(to: alphaPrompt)
        let extractedAlpha = alphaCapture.extractedImages
        #expect(extractedAlpha.count == 1)
        #expect(extractedAlpha[0].format == .png)
        let pngData = try #require(extractedAlpha[0].rawData)
        let pngSource = try #require(CGImageSourceCreateWithData(pngData as CFData, nil))
        let pngProps = CGImageSourceCopyPropertiesAtIndex(pngSource, 0, nil) as? [CFString: Any]
        let hasAlphaProp = pngProps?[kCGImagePropertyHasAlpha] as? Bool
        #expect(hasAlphaProp == true)

        // 2. Opaque BGRA/RGBX camera frame (noneSkipFirst / noneSkipLast) fast-paths to single-pass JPEG
        let opaqueCtx = try #require(CGContext(
            data: nil,
            width: 1600,
            height: 1200,
            bitsPerComponent: 8,
            bytesPerRow: 1600 * 4,
            space: p3Space,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ))
        opaqueCtx.setFillColor(CGColor(colorSpace: p3Space, components: [0.95, 0.2, 0.2, 1.0])!)
        opaqueCtx.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
        let cameraFrame = try #require(opaqueCtx.makeImage())
        #expect(TranscriptAttachmentExtractor.hasAlphaChannel(cameraFrame) == false)

        let cameraCapture = VisionAttachmentCaptureBox()
        let cameraSession = LanguageModelSession(model: VisionAttachmentCaptureModel(box: cameraCapture))
        let cameraPrompt = Prompt {
            "Check camera frame"
            Attachment(cameraFrame)
        }
        _ = try await cameraSession.respond(to: cameraPrompt)
        let extractedOpaque = cameraCapture.extractedImages
        #expect(extractedOpaque.count == 1)
        #expect(extractedOpaque[0].format == .jpeg)
        let jpegBytes = try #require(extractedOpaque[0].rawData)
        let dims = try #require(SystemOneImage.extractDimensions(data: jpegBytes, format: .jpeg))
        #expect(dims.width == 1024)
        #expect(dims.height == 768)
        let jpegSource = try #require(CGImageSourceCreateWithData(jpegBytes as CFData, nil))
        let decodedJPEG = try #require(CGImageSourceCreateImageAtIndex(jpegSource, 0, nil))
        #expect(decodedJPEG.colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test("TranscriptAttachmentExtractor extractImage(fromFileURL:) preserves small files and downscales oversized files")
    func testFileURLAttachmentDownscaling() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SystemOneImageFileTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let srgb = try #require(CGColorSpace(name: CGColorSpace.sRGB))

        // 1. Small 320x240 PNG file (<= 1024px) returns exact file bytes without re-encoding
        let smallCtx = try #require(CGContext(
            data: nil,
            width: 320,
            height: 240,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: srgb,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        smallCtx.setFillColor(red: 0.1, green: 0.5, blue: 0.8, alpha: 0.5)
        smallCtx.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
        let smallCG = try #require(smallCtx.makeImage())
        let smallPNGData = try #require(TranscriptAttachmentExtractor.convertCGImageToPNG(smallCG, maxDimension: 1024))
        let smallURL = tempDir.appendingPathComponent("small_badge.png")
        try smallPNGData.write(to: smallURL)

        let smallExtracted = try TranscriptAttachmentExtractor.extractImage(fromFileURL: smallURL)
        #expect(smallExtracted.format == .png)
        #expect(smallExtracted.identifier == "small_badge.png")
        #expect(smallExtracted.rawData == smallPNGData)

        // 2. Oversized 2048x1536 opaque JPEG file (> 1024px) is downscaled to 1024x768
        let largeCtx = try #require(CGContext(
            data: nil,
            width: 2048,
            height: 1536,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: srgb,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        largeCtx.setFillColor(red: 0.3, green: 0.6, blue: 0.2, alpha: 1.0)
        largeCtx.fill(CGRect(x: 0, y: 0, width: 2048, height: 1536))
        let largeCG = try #require(largeCtx.makeImage())
        let unscaledJPEGData = try #require(TranscriptAttachmentExtractor.convertCGImageToJPEG(largeCG, maxDimension: 4096, quality: 0.95))
        let largeURL = tempDir.appendingPathComponent("camera_2048.jpg")
        try unscaledJPEGData.write(to: largeURL)

        let downscaledExtracted = try TranscriptAttachmentExtractor.extractImage(fromFileURL: largeURL)
        #expect(downscaledExtracted.format == .jpeg)
        let downscaledData = try #require(downscaledExtracted.rawData)
        let downscaledDims = try #require(SystemOneImage.extractDimensions(data: downscaledData, format: .jpeg))
        #expect(downscaledDims.width == 1024)
        #expect(downscaledDims.height == 768)
    }
}

// MARK: - Vision Attachment Capture Harness

// Thread-safe via NSLock per AGENTS.md Principle 2
private final class VisionAttachmentCaptureBox: @unchecked Sendable, Hashable {
    private let id = UUID()
    private let lock = NSLock()
    private var _extractedImages: [SystemOneImage] = []

    var extractedImages: [SystemOneImage] {
        get { lock.withLock { _extractedImages } }
        set { lock.withLock { _extractedImages = newValue } }
    }

    static func == (lhs: VisionAttachmentCaptureBox, rhs: VisionAttachmentCaptureBox) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct VisionAttachmentCaptureModel: LanguageModel, Sendable {
    typealias Executor = VisionAttachmentCaptureExecutor
    var executorConfiguration: VisionAttachmentCaptureBox

    init(box: VisionAttachmentCaptureBox) {
        self.executorConfiguration = box
    }

    var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities([.vision])
    }

    func supportsDataAttachmentType(_ type: UTType) async throws -> Bool {
        true
    }

    func supportsDataEntryType(_ type: UTType) async throws -> Bool {
        false
    }
}

private final class VisionAttachmentCaptureExecutor: LanguageModelExecutor, Sendable {
    typealias Model = VisionAttachmentCaptureModel
    typealias Configuration = VisionAttachmentCaptureBox

    let configuration: Configuration

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    func prewarm(model: VisionAttachmentCaptureModel, transcript: Transcript) {}

    func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: VisionAttachmentCaptureModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        configuration.extractedImages = try TranscriptAttachmentExtractor.extractImages(from: request.transcript)
        let entryID = UUID().uuidString
        await channel.send(.response(entryID: entryID, action: .appendText("ok", tokenCount: 0)))
    }
}
