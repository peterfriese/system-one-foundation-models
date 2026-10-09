import Testing
import Foundation
import CoreGraphics
import UniformTypeIdentifiers
import FoundationModels
import SystemOneCore
import ClefFoundationModels

// MARK: - Test Generable Schemas

@Generable
enum DefectCategory: String, Sendable, CaseIterable {
    case none
    case scratch
    case dent
    case discoloration
}

@Generable
struct DefectInspectionDecision: Sendable {
    @Guide(description: "Is there any visible physical defect on the surface?")
    var hasDefect: Bool

    @Guide(description: "Classification of the primary defect")
    var category: DefectCategory

    @Guide(description: "Severity score from 0 (clean) to 3 (critical)", .range(0...3))
    var severity: Int
}

// MARK: - Mock URLProtocol for ClefLanguageModelTests

final class MockClefLanguageModelProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _responseQueue: [Result<(statusCode: Int, headers: [String: String], body: Data), any Error>] = []

    static func reset() {
        lock.withLock {
            _responseQueue = []
        }
    }

    static func enqueue(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        lock.withLock {
            _responseQueue.append(.success((statusCode, headers, body)))
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let nextItem: Result<(statusCode: Int, headers: [String: String], body: Data), any Error>? = Self.lock.withLock {
            guard !Self._responseQueue.isEmpty else { return nil }
            return Self._responseQueue.removeFirst()
        }

        guard let next = nextItem else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        switch next {
        case .success(let item):
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://api.cloudflare.com")!,
                statusCode: item.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: item.headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: item.body)
            client?.urlProtocolDidFinishLoading(self)

        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Test Suite

@Suite("Clef Language Model & Foundation Models Conformance Tests", .serialized)
struct ClefLanguageModelTests {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockClefLanguageModelProtocol.self]
        return URLSession(configuration: config)
    }

    private let sampleInspectionJSON = """
    {
      "model": "@cf/cloudflare/clef-flash",
      "answers": {
        "hasDefect": {
          "type": "noul",
          "noul": 0.96,
          "confidence": 0.96,
          "probabilities": { "true": 0.96, "false": 0.04 }
        },
        "category": {
          "type": "choice",
          "choice": "scratch",
          "confidence": 0.92,
          "probabilities": { "scratch": 0.92, "dent": 0.05, "none": 0.03 }
        },
        "severity": {
          "type": "score",
          "score": 2.0,
          "confidence": 0.88,
          "probabilities": { "0": 0.02, "1": 0.08, "2": 0.85, "3": 0.05 },
          "legend": { "0": "P0", "1": "P1", "2": "P2", "3": "P3" }
        }
      },
      "usage": { "input_tokens": 320, "output_tokens": 16 }
    }
    """.data(using: .utf8)!

    // MARK: - Model Capabilities & Data Attachments

    @Test("ClefLanguageModel capabilities advertise guidedGeneration and vision")
    func testCapabilities() {
        let model = ClefLanguageModel(endpoint: .local())
        #expect(model.capabilities.contains(.guidedGeneration))
        #expect(model.capabilities.contains(.vision))
    }

    @Test("ClefLanguageModel supports PNG, JPEG, and WebP data attachment types")
    func testSupportedDataAttachmentTypes() async throws {
        let model = ClefLanguageModel(endpoint: .local())

        let supportsPNG = try await model.supportsDataAttachmentType(.png)
        let supportsJPEG = try await model.supportsDataAttachmentType(.jpeg)
        let supportsWebP = try await model.supportsDataAttachmentType(.webP)
        let supportsPDF = try await model.supportsDataAttachmentType(.pdf)
        let supportsText = try await model.supportsDataAttachmentType(.plainText)

        #expect(supportsPNG == true)
        #expect(supportsJPEG == true)
        #expect(supportsWebP == true)
        #expect(supportsPDF == false)
        #expect(supportsText == false)

        let supportsDataEntry = try await model.supportsDataEntryType(.png)
        #expect(supportsDataEntry == false)
    }

    // MARK: - LanguageModelSession Evaluation

    @Test("End-to-end: ClefLanguageModel evaluates @Generable struct via LanguageModelSession")
    func testLanguageModelSessionGenerableEvaluation() async throws {
        MockClefLanguageModelProtocol.reset()
        MockClefLanguageModelProtocol.enqueue(statusCode: 200, body: sampleInspectionJSON)

        let backend = ClefHTTPBackend(
            endpoint: .workersAI(accountID: "cf-acc", model: .clefFlash),
            apiToken: "cf-token",
            session: makeSession()
        )
        let config = ClefLanguageModel.Configuration(backend: backend)
        let model = ClefLanguageModel(configuration: config)
        let session = LanguageModelSession(model: model)

        let prompt = "Inspecting surface of tempered glass component serial #8841"
        let response = try await session.respond(to: prompt, generating: DefectInspectionDecision.self)

        // Verify strongly-typed @Generable content synthesis
        #expect(response.content.hasDefect == true)
        #expect(response.content.category == .scratch)
        #expect(response.content.severity == 2)

        // Verify calibrated probabilities and confidence metadata
        let defectProb = response.probability(for: "hasDefect")
        #expect(defectProb == 0.96)

        let catConf = response.confidence(for: "category")
        #expect(catConf == 0.92)

        let scoreVal = response.scoreValue(for: "severity")
        #expect(scoreVal?.rounded == 2)
        #expect(scoreVal?.confidence == 0.88)
        #expect(scoreVal?.legend[2] == "P2")

        let modelMeta = try? response.metadata["model"]?.value(String.self)
        #expect(modelMeta == "@cf/cloudflare/clef-flash")
    }

    @Test("End-to-end: ClefLanguageModel evaluates @Generable struct with image attachment")
    func testLanguageModelSessionWithAttachment() async throws {
        MockClefLanguageModelProtocol.reset()
        MockClefLanguageModelProtocol.enqueue(statusCode: 200, body: sampleInspectionJSON)

        let backend = ClefHTTPBackend(
            endpoint: .workersAI(accountID: "cf-acc", model: .clefFlash),
            apiToken: "cf-token",
            session: makeSession()
        )
        let config = ClefLanguageModel.Configuration(backend: backend)
        let model = ClefLanguageModel(configuration: config)
        let session = LanguageModelSession(model: model)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 40, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let cgImage = ctx.makeImage()!

        let prompt = Prompt {
            "Inspecting surface of tempered glass component serial #8841"
            Attachment(cgImage)
        }
        let response = try await session.respond(to: prompt, generating: DefectInspectionDecision.self)

        #expect(response.content.hasDefect == true)
        #expect(response.content.category == DefectCategory.scratch)
        #expect(response.content.severity == 2)
    }

    // MARK: - Unstructured Output Guardrail

    @Test("ClefExecutor rejects unstructured free-form text generation requests")
    func testStructuredOutputRequired() async throws {
        let backend = ClefHTTPBackend(
            endpoint: .local(),
            session: makeSession()
        )
        let config = ClefLanguageModel.Configuration(backend: backend)
        let model = ClefLanguageModel(configuration: config)
        let session = LanguageModelSession(model: model)

        do {
            _ = try await session.respond(to: "Write me an essay about optical sensors.")
            Issue.record("Expected structuredOutputRequired to be thrown for unguided generation")
        } catch let error as SystemOneError {
            if case .structuredOutputRequired = error {
                // Succeeded in throwing typed guardrail error
            } else {
                Issue.record("Expected .structuredOutputRequired, got: \(error)")
            }
        } catch {
            Issue.record("Unexpected error thrown: \(error)")
        }
    }

    // MARK: - Transcript State & Attachment Extraction

    @Test("ClefExecutor extracts prompt and instruction text from Transcript")
    func testTranscriptStateExtraction() throws {
        let backend = ClefHTTPBackend(endpoint: .local(), session: makeSession())
        let executor = try ClefExecutor(configuration: .init(backend: backend))

        var transcript = Transcript()
        transcript.append(Transcript.Entry.instructions(Transcript.Instructions(segments: [.text(Transcript.TextSegment(content: "System prompt instructions"))], toolDefinitions: [])))
        transcript.append(Transcript.Entry.prompt(Transcript.Prompt(segments: [.text(Transcript.TextSegment(content: "User input query"))])))

        let extracted = executor.extractState(from: transcript)
        #expect(extracted.contains("System prompt instructions"))
        #expect(extracted.contains("User input query"))
    }

    @Test("TranscriptAttachmentExtractor maps UTTypes to supported SystemOneImage formats")
    func testTranscriptAttachmentExtractorFormatMapping() {
        #expect(TranscriptAttachmentExtractor.mapUTTypeToFormat(.png) == .png)
        #expect(TranscriptAttachmentExtractor.mapUTTypeToFormat(.jpeg) == .jpeg)
        #expect(TranscriptAttachmentExtractor.mapUTTypeToFormat(.webP) == .webp)
        #expect(TranscriptAttachmentExtractor.mapUTTypeToFormat(.gif) == nil)
        #expect(TranscriptAttachmentExtractor.mapUTTypeToFormat(.pdf) == nil)
    }

    @Test("TranscriptAttachmentExtractor convertCGImageToJPEG scales down large images and generates JPEG")
    func testConvertCGImageToJPEGDownscaling() throws {
        // Create 2048 x 1024 image (> 1024 maxDimension)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: 2048,
            height: 1024,
            bitsPerComponent: 8,
            bytesPerRow: 2048 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let largeImage = ctx.makeImage()!

        let jpegData = try #require(TranscriptAttachmentExtractor.convertCGImageToJPEG(largeImage, maxDimension: 1024, quality: 0.8))
        let dims = try #require(SystemOneImage.extractDimensions(data: jpegData, format: .jpeg))

        #expect(dims.width == 1024)
        #expect(dims.height == 512)
    }

    @Test("TranscriptAttachmentExtractor convertCGImageToJPEG preserves image dimensions when <= maxDimension")
    func testConvertCGImageToJPEGPreservesSmallImages() throws {
        // Create 400 x 300 image (<= 1024 maxDimension)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: 400,
            height: 300,
            bitsPerComponent: 8,
            bytesPerRow: 400 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let smallImage = ctx.makeImage()!

        let jpegData = try #require(TranscriptAttachmentExtractor.convertCGImageToJPEG(smallImage, maxDimension: 1024, quality: 0.8))
        let dims = try #require(SystemOneImage.extractDimensions(data: jpegData, format: .jpeg))

        #expect(dims.width == 400)
        #expect(dims.height == 300)
    }

    @Test("ItemCategory conforms to Choosable with optionIdentifier and optionDescription")
    func testItemCategoryChoosableConformance() {
        let category: any Choosable = ItemCategory.beverage
        #expect(category.optionIdentifier == "beverage")
        #expect(category.optionDescription == "Beverage")

        #expect(ItemCategory.allCases.count == 10)
    }
}
