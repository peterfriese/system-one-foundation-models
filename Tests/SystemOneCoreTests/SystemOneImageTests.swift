import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import FoundationModels
import SystemOneCore

@Suite("SystemOneImage & Multimodal Core Tests")
struct SystemOneImageTests {

    // MARK: - Sample Image Fixtures

    private static func makePNGData(width: UInt32 = 800, height: UInt32 = 600) -> Data {
        var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x0D])
        data.append(contentsOf: [0x49, 0x48, 0x44, 0x52])
        withUnsafeBytes(of: width.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: height.bigEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: [0x08, 0x06, 0x00, 0x00, 0x00])
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        return data
    }

    private static func makeJPEGData(width: UInt16 = 640, height: UInt16 = 480, marker: UInt8 = 0xC0, fillBytes: Int = 0) -> Data {
        var data = Data([0xFF, 0xD8])
        if fillBytes > 0 {
            data.append(contentsOf: Array(repeating: UInt8(0xFF), count: fillBytes))
        }
        data.append(contentsOf: [0xFF, marker])
        data.append(contentsOf: [0x00, 0x11])
        data.append(0x08)
        withUnsafeBytes(of: height.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: width.bigEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: [0x03, 0x01, 0x11, 0x00, 0x02, 0x11, 0x00, 0x03, 0x11, 0x00])
        data.append(contentsOf: [0xFF, 0xD9])
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
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
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

    private static func makeMinimalVP8LData(width: UInt32 = 16, height: UInt32 = 12) -> Data {
        var data = Data("RIFF".utf8)
        let totalSize: UInt32 = 17
        withUnsafeBytes(of: totalSize.littleEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: "WEBP".utf8)
        data.append(contentsOf: "VP8L".utf8)
        let chunkLength: UInt32 = 5
        withUnsafeBytes(of: chunkLength.littleEndian) { data.append(contentsOf: $0) }
        data.append(0x2F) // VP8L signature byte at offset 20
        let w = width - 1
        let h = height - 1
        let packed: UInt32 = (w & 0x3FFF) | ((h & 0x3FFF) << 14)
        data.append(UInt8(packed & 0xFF))
        data.append(UInt8((packed >> 8) & 0xFF))
        data.append(UInt8((packed >> 16) & 0xFF))
        data.append(UInt8((packed >> 24) & 0xFF))
        return data // Exactly 25 bytes (< 30 bytes!)
    }

    // MARK: - Initialization & Validation Tests

    @Test("Initializes from raw Data with PNG, JPEG, and WebP MIME types and UTTypes")
    func testInitializationFromRawDataAndUTTypes() throws {
        let pngData = Self.makePNGData()
        let pngImage = try SystemOneImage(data: pngData, mimeType: "image/png", identifier: "inspection.png")
        #expect(pngImage.format == .png)
        #expect(pngImage.identifier == "inspection.png")
        #expect(pngImage.dataURL.hasPrefix("data:image/png;base64,"))
        #expect(pngImage.rawData == pngData)

        let jpegData = Self.makeJPEGData()
        let jpegImage = try SystemOneImage(data: jpegData, utType: .jpeg, identifier: "photo.jpg")
        #expect(jpegImage.format == .jpeg)

        let webpData = Self.makeWebPData()
        let webpImage = try SystemOneImage(data: webpData, utType: .webP, identifier: "defect.webp")
        #expect(webpImage.format == .webp)

        #expect(throws: SystemOneError.self) {
            try SystemOneImage(data: Data([1, 2, 3]), utType: .pdf)
        }
        #expect(throws: SystemOneError.self) {
            try SystemOneImage(data: Data([1, 2, 3]), mimeType: "image/gif")
        }
    }

    @Test("SystemOneImage(fileURL:) rejects non-file URLs without network egress")
    func testRejectsRemoteFileURL() {
        let remoteURL = URL(string: "https://example.com/secret.png")!
        #expect(throws: SystemOneError.self) {
            try SystemOneImage(fileURL: remoteURL)
        }
    }

    @Test("extractDimensions safely handles non-zero startIndex Data slices, JPEG fill bytes, SOF3+, and 25-byte VP8L")
    func testDimensionExtractionHardening() {
        // 1. Non-zero startIndex Data slice (previously crashed with index out of bounds)
        var padded = Data([0xAA, 0xBB, 0xCC, 0xDD])
        padded.append(Self.makePNGData(width: 1920, height: 1080))
        let pngSlice = padded[4...]
        #expect(pngSlice.startIndex == 4)
        let sliceDims = SystemOneImage.extractDimensions(data: pngSlice, format: .png)
        #expect(sliceDims?.width == 1920)
        #expect(sliceDims?.height == 1080)

        // 2. Reject spoofed non-PNG header even if >= 24 bytes
        let fakePNG = Data(repeating: 0x42, count: 32)
        #expect(SystemOneImage.extractDimensions(data: fakePNG, format: .png) == nil)

        // 3. JPEG with 0xFF fill bytes and SOF3 (0xC3) lossless marker
        let jpegSOF3 = Self.makeJPEGData(width: 1280, height: 720, marker: 0xC3, fillBytes: 3)
        let jpegDims = SystemOneImage.extractDimensions(data: jpegSOF3, format: .jpeg)
        #expect(jpegDims?.width == 1280)
        #expect(jpegDims?.height == 720)

        // 4. Minimal 25-byte Lossless WebP (VP8L < 30 bytes)
        let vp8l = Self.makeMinimalVP8LData(width: 24, height: 18)
        #expect(vp8l.count == 25)
        let vp8lDims = SystemOneImage.extractDimensions(data: vp8l, format: .webp)
        #expect(vp8lDims?.width == 24)
        #expect(vp8lDims?.height == 18)
    }

    @Test("Guardrails enforce 16MP resolution, max 4 images, and 13 MiB payload size")
    func testValidationGuardrails() throws {
        let validPNG = Self.makePNGData(width: 4000, height: 3000)
        try SystemOneImage(data: validPNG, format: .png).validate()

        let oversizedPNG = Self.makePNGData(width: 5000, height: 4000)
        #expect(throws: SystemOneError.self) {
            try SystemOneImage(data: oversizedPNG, format: .png).validate()
        }

        let smallPNG = Self.makePNGData(width: 64, height: 64)
        let fiveImages = (1...5).map { SystemOneImage(data: smallPNG, format: .png, identifier: "img_\($0)") }
        #expect(throws: SystemOneError.self) {
            try SystemOneImage.validate(images: fiveImages)
        }

        let oversizedBase64 = String(repeating: "A", count: 14 * 1024 * 1024)
        let hugePayload = SystemOneImage(base64Encoded: oversizedBase64, format: .jpeg)
        #expect(throws: SystemOneError.self) {
            try SystemOneImage.validate(images: [hugePayload])
        }
    }

    @Test("Codable supports both RFC 2397 Data URL strings and structured dictionary objects")
    func testCodableRepresentations() throws {
        let raw = Data([0x01, 0x02, 0x03, 0x04])
        let image = SystemOneImage(data: raw, format: .jpeg, identifier: "cam_feed")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let encoded = try encoder.encode(image)
        let jsonString = try #require(String(data: encoded, encoding: .utf8))
        #expect(jsonString == "\"\(image.dataURL)\"")

        let decodedFromString = try JSONDecoder().decode(SystemOneImage.self, from: encoded)
        #expect(decodedFromString.dataURL == image.dataURL)
        #expect(decodedFromString.format == image.format)
        #expect(decodedFromString.identifier == nil)

        let dictJSON = """
        {
            "format": "image/webp",
            "data_url": "data:image/webp;base64,\(raw.base64EncodedString())",
            "identifier": "sensor_01"
        }
        """
        let decodedFromDict = try JSONDecoder().decode(SystemOneImage.self, from: Data(dictJSON.utf8))
        #expect(decodedFromDict.format == .webp)
        #expect(decodedFromDict.identifier == "sensor_01")
        #expect(decodedFromDict.rawData == raw)
    }

    @Test("TranscriptAttachmentExtractor scopes extraction to the active turn and downscales >1024px file URLs")
    func testActiveTurnExtractionAndLocalFileDownscaling() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Write a real 2000x1000 opaque PNG to disk (> 1024px maxDimension)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: 2000,
            height: 1000,
            bitsPerComponent: 8,
            bytesPerRow: 2000 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        let largeCGImage = ctx.makeImage()!
        let largeFileURL = tempDir.appendingPathComponent("large_input.png")
        let dest = CGImageDestinationCreateWithURL(largeFileURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, largeCGImage, nil)
        #expect(CGImageDestinationFinalize(dest))

        // Build multi-turn transcript: 4 images in turn 1 -> response -> 1 large file URL image in turn 2
        let smallCtx = CGContext(
            data: nil,
            width: 16,
            height: 16,
            bitsPerComponent: 8,
            bytesPerRow: 64,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let smallCGImage = smallCtx.makeImage()!

        let turn1Prompt = Prompt {
            "Turn 1"
            Attachment(smallCGImage)
            Attachment(smallCGImage)
            Attachment(smallCGImage)
            Attachment(smallCGImage)
        }
        let turn2Prompt = Prompt {
            "Turn 2 active inspection"
            Attachment(imageURL: largeFileURL)
        }

        // Verify via a vision-enabled SystemOneLanguageModel session across two turns!
        actor TurnRecorder {
            var imageCounts: [Int] = []
            var lastImage: SystemOneImage?
            func record(_ images: [SystemOneImage]?) {
                imageCounts.append(images?.count ?? 0)
                lastImage = images?.first
            }
        }
        let recorder = TurnRecorder()
        let backend = MockSystemOneBackend { req in
            await recorder.record(req.images)
            return SystemOneResponse(
                model: "vision-test",
                answers: ["decision": SystemOneAnswer(type: "noul", noul: 0.9, confidence: 0.9)]
            )
        }
        let session = LanguageModelSession(model: SystemOneLanguageModel(backend: backend, supportsVision: true))

        _ = try await session.probability(of: "Check turn 1", prompt: turn1Prompt)
        _ = try await session.probability(of: "Check turn 2", prompt: turn2Prompt)

        // Turn 1 sent 4 images; Turn 2 must ONLY send the 1 active-turn image (not 5!)
        let recordedCounts = await recorder.imageCounts
        #expect(recordedCounts == [4, 1])

        // And the 2000x1000 local file attachment in Turn 2 was downscaled to 1024x512 JPEG!
        let downscaled = try #require(await recorder.lastImage)
        #expect(downscaled.format == .jpeg)
        let raw = try #require(downscaled.rawData)
        let dims = try #require(SystemOneImage.extractDimensions(data: raw, format: .jpeg))
        #expect(dims.width == 1024)
        #expect(dims.height == 512)
    }

    @Test("SystemOneRequest encoding excludes images when nil or empty for backward compatibility")
    func testRequestEncodingBackwardCompatibility() throws {
        let requestWithoutImages = SystemOneRequest(state: "Text state", model: "systemone-default", questions: [:])
        let dataWithoutImages = try JSONEncoder().encode(requestWithoutImages)
        let jsonWithoutImages = try #require(String(data: dataWithoutImages, encoding: .utf8))
        #expect(!jsonWithoutImages.contains("\"images\""))

        let image = SystemOneImage(data: Data([1, 2, 3]), format: .jpeg)
        let requestWithImages = SystemOneRequest(
            state: "Multimodal state",
            model: "@cf/cloudflare/clef-flash",
            questions: [:],
            images: [image]
        )
        let dataWithImages = try JSONEncoder().encode(requestWithImages)
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
