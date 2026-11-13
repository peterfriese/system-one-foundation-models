import Foundation
import Testing
@testable import AppCore
import FactoryKit

extension SerializedContainerTests {

@Suite("Benchmark Ground-Truth & Store Tests", .serialized)
struct BenchmarkTruthTests {
    @Test("BenchmarkHardwareInfo extracts current system hardware metadata")
    func testHardwareInfoCurrent() {
        let hardware = BenchmarkHardwareInfo.current
        #expect(!hardware.deviceModel.isEmpty)
        #expect(!hardware.chipName.isEmpty)
        #expect(!hardware.osVersion.isEmpty)
    }

    @Test("BenchmarkBackendResult formats throughput and percentiles correctly")
    func testBackendResultFormatting() {
        let result = BenchmarkBackendResult(
            backendName: "On-Device Core ML",
            endpointOrModel: "LayaDecisionModel.mlmodelc",
            sampleCount: 25,
            totalDurationSeconds: 0.22,
            throughputPerSecond: 113.636,
            meanLatencyMs: 8.8,
            p50LatencyMs: 8.5,
            p95LatencyMs: 12.1,
            totalTokens: 0,
            sampleDecisions: []
        )

        #expect(result.formattedThroughput == "113.6 msg/s")
        #expect(result.formattedTotalDuration == "0.22 s")
        #expect(result.formattedMeanLatency == "8.8 ms")
        #expect(result.formattedP50Latency == "8.5 ms")
        #expect(result.formattedP95Latency == "12.1 ms")

        let slowResult = BenchmarkBackendResult(
            backendName: "Apple Intelligence",
            endpointOrModel: "SystemLanguageModel",
            sampleCount: 10,
            totalDurationSeconds: 15.0,
            throughputPerSecond: 0.67,
            meanLatencyMs: 1500.0,
            p50LatencyMs: 1450.0,
            p95LatencyMs: 2100.0,
            totalTokens: 4500
        )
        #expect(slowResult.formattedTotalDuration == "15.00 s")
        #expect(slowResult.formattedMeanLatency == "1.50 s")
        #expect(slowResult.formattedP50Latency == "1.45 s")
        #expect(slowResult.formattedP95Latency == "2.10 s")

        let minuteResult = BenchmarkBackendResult(
            backendName: "Batch Test",
            endpointOrModel: "Test",
            sampleCount: 500,
            totalDurationSeconds: 125.4,
            throughputPerSecond: 3.98,
            meanLatencyMs: 250.8,
            p50LatencyMs: 240.0,
            p95LatencyMs: 310.0,
            totalTokens: 0
        )
        #expect(minuteResult.formattedTotalDuration == "2m 5.4s")
    }

    @Test("BenchmarkTruthPayload encodes and decodes symmetrically with JSON")
    func testPayloadSerialization() throws {
        let hardware = BenchmarkHardwareInfo(
            deviceModel: "Apple Silicon Mac",
            chipName: "Apple Silicon Reference Hardware",
            osVersion: "macOS 15.0"
        )

        let decision = BenchmarkSampleDecision(
            emailId: UUID(),
            latencyMs: 8.4,
            category: .work,
            requiresAction: true,
            urgencyScore: 1,
            suggestedAction: .scheduleTask,
            confidence: 0.95
        )

        let coreMLResult = BenchmarkBackendResult(
            backendName: "On-Device Core ML",
            endpointOrModel: "LayaDecisionModel.mlmodelc",
            sampleCount: 1,
            totalDurationSeconds: 0.009,
            throughputPerSecond: 111.1,
            meanLatencyMs: 8.4,
            p50LatencyMs: 8.4,
            p95LatencyMs: 8.4,
            totalTokens: 0,
            sampleDecisions: [decision]
        )

        let generativeResult = BenchmarkBackendResult(
            backendName: "Apple Intelligence",
            endpointOrModel: "SystemLanguageModel",
            sampleCount: 1,
            totalDurationSeconds: 0.95,
            throughputPerSecond: 1.05,
            meanLatencyMs: 950.0,
            p50LatencyMs: 950.0,
            p95LatencyMs: 950.0,
            totalTokens: 450,
            sampleDecisions: []
        )

        let payload = BenchmarkTruthPayload(
            version: "1.0",
            generatedAt: Date(),
            hardwareInfo: hardware,
            sampleCount: 1,
            results: [
                .onDeviceCoreML: coreMLResult,
                .generativeBaseline: generativeResult
            ],
            isSyntheticReference: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BenchmarkTruthPayload.self, from: data)

        #expect(decoded.version == "1.0")
        #expect(decoded.sampleCount == 1)
        #expect(decoded.hardwareInfo == hardware)
        #expect(decoded.isSyntheticReference == true)
        #expect(decoded.results[.onDeviceCoreML]?.backendName == "On-Device Core ML")
        #expect(decoded.results[.generativeBaseline]?.totalTokens == 450)

        // Verify speedup factor calculation
        let speedup = decoded.speedupFactor(for: .onDeviceCoreML)
        #expect(speedup != nil)
        #expect(speedup! > 100.0) // 950.0 / 8.4 = ~113.1x
    }

    @Test("BenchmarkTruthStore saves and loads payload to custom file location")
    func testBenchmarkTruthStoreFilePersistence() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-benchmark-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let store = BenchmarkTruthStore(customURL: tempURL, checkBundledResource: false)
        #expect(store.canonicalFileURL == tempURL)

        // Initially nothing loaded
        #expect(store.loadTruth() == nil)

        let hardware = BenchmarkHardwareInfo(deviceModel: "MacTest", chipName: "M-Chip", osVersion: "macOS 15")
        let payload = BenchmarkTruthPayload(
            version: "1.0",
            generatedAt: Date(),
            hardwareInfo: hardware,
            sampleCount: 25,
            results: [:]
        )

        try store.saveTruth(payload)

        #expect(FileManager.default.fileExists(atPath: tempURL.path))
        let loaded = store.loadTruth()
        #expect(loaded != nil)
        #expect(loaded?.hardwareInfo.deviceModel == "MacTest")
        #expect(loaded?.sampleCount == 25)
    }

    @Test("BenchmarkTruthStore falls back to bundled resource if canonical file absent")
    func testBundledResourceFallback() {
        // Point store to a non-existent file
        let nonExistent = FileManager.default.temporaryDirectory.appendingPathComponent("non-existent-\(UUID().uuidString).json")
        let store = BenchmarkTruthStore(customURL: nonExistent)

        // If bundled resource benchmark-truth.json exists in AppCore, it loads it
        let truth = store.loadTruth()
        if let truth {
            #expect(truth.version == "1.0")
            #expect(truth.sampleCount >= 10)
            #expect(truth.results[.onDeviceCoreML] != nil)
            #expect(truth.isSyntheticReference == false)
        }
    }

    @Test("MockBenchmarkTruthStore operates in memory and handles error injection")
    func testMockBenchmarkTruthStore() throws {
        let mock = MockBenchmarkTruthStore()
        #expect(mock.loadTruth() == nil)

        let hardware = BenchmarkHardwareInfo(deviceModel: "MockMac", chipName: "Apple MMock", osVersion: "macOS Mock")
        let payload = BenchmarkTruthPayload(
            version: "1.0",
            generatedAt: Date(),
            hardwareInfo: hardware,
            sampleCount: 50,
            results: [:]
        )

        try mock.saveTruth(payload)
        #expect(mock.loadTruth()?.hardwareInfo.chipName == "Apple MMock")

        struct TestError: Error, Equatable {}
        mock.shouldThrowError = TestError()
        #expect(throws: TestError.self) {
            try mock.saveTruth(payload)
        }
    }

    @Test("MailStore loads canonical benchmark truth and can refresh")
    @MainActor
    func testMailStoreBenchmarkTruthIntegration() {
        let mockStore = MockBenchmarkTruthStore()
        let hardware = BenchmarkHardwareInfo(deviceModel: "TestMac", chipName: "M-Test", osVersion: "macOS Test")
        let payload = BenchmarkTruthPayload(
            version: "1.0",
            generatedAt: Date(),
            hardwareInfo: hardware,
            sampleCount: 15,
            results: [:]
        )
        mockStore.payload = payload

        Container.shared.benchmarkTruthStore.register { mockStore }
        defer { Container.shared.benchmarkTruthStore.reset() }

        let mailStore = MailStore()
        #expect(mailStore.canonicalBenchmarkTruth?.hardwareInfo.deviceModel == "TestMac")
        #expect(mailStore.canonicalBenchmarkTruth?.sampleCount == 15)

        // Mutate mock and refresh
        mockStore.payload?.sampleCount = 30
        mailStore.refreshBenchmarkTruth()
        #expect(mailStore.canonicalBenchmarkTruth?.sampleCount == 30)
    }
}

} // extension SerializedContainerTests
