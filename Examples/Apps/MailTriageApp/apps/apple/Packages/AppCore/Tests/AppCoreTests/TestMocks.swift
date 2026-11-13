import Foundation
import zlib
@testable import AppCore

/// Deterministic mock triage engine restricted strictly to automated unit tests.
final class MockTriageEngine: TriageEngineProtocol, @unchecked Sendable {
    var cannedResult: TriageResult?
    var shouldThrowError: Error?
    var latencyMs: Double

    init(
        cannedResult: TriageResult? = nil,
        shouldThrowError: Error? = nil,
        latencyMs: Double = 2.0
    ) {
        self.cannedResult = cannedResult
        self.shouldThrowError = shouldThrowError
        self.latencyMs = latencyMs
    }

    func triage(email: Email, backend: TriageBackend, skipProbe: Bool = false) async throws -> TriageResult {
        if let error = shouldThrowError {
            throw error
        }
        if let canned = cannedResult {
            return canned
        }
        let decision = EmailTriageDecision(
            requiresAction: true,
            category: .work,
            urgencyScore: 1,
            suggestedAction: .scheduleTask
        )
        return TriageResult(
            decision: decision,
            confidenceScore: 0.90,
            decisiveness: 0.90,
            routingTier: .auto,
            latencyMs: latencyMs,
            backendUsed: backend
        )
    }

    func triageBatch(
        emails: [Email],
        backend: TriageBackend,
        progress: (@Sendable (Int, Int) -> Void)? = nil,
        onItemCompleted: (@Sendable (Email, TriageResult) -> Void)? = nil
    ) async throws -> BatchTriageReport {
        if let error = shouldThrowError {
            throw error
        }

        var processed = 0
        progress?(0, emails.count)
        for email in emails {
            try Task.checkCancellation()
            let res = try await triage(email: email, backend: backend)
            processed += 1
            progress?(processed, emails.count)
            onItemCompleted?(email, res)
        }

        return BatchTriageReport(
            totalProcessed: emails.count,
            totalDurationSeconds: 0.05,
            averageLatencyMs: latencyMs,
            actionBreakdown: [.scheduleTask: emails.count],
            routingBreakdown: [.auto: emails.count],
            backend: backend
        )
    }
}

/// Mock health probe service restricted strictly to automated unit tests.
final class MockBackendHealthProbeService: BackendHealthProbeServiceProtocol, @unchecked Sendable {
    var statusOverride: [TriageBackend: BackendHealthStatus] = [:]
    var defaultStatus: BackendHealthStatus

    init(defaultStatus: BackendHealthStatus = .healthy(latencyMs: 8.0)) {
        self.defaultStatus = defaultStatus
    }

    func probe(backend: TriageBackend) async -> BackendHealthStatus {
        statusOverride[backend] ?? defaultStatus
    }

    func probeAll() async -> [TriageBackend: BackendHealthStatus] {
        var results: [TriageBackend: BackendHealthStatus] = [:]
        for backend in TriageBackend.allCases {
            results[backend] = statusOverride[backend] ?? defaultStatus
        }
        return results
    }
}

/// Deterministic in-memory keychain restricted strictly to automated unit tests.
final class MockKeychainService: KeychainServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String]

    init(initialStorage: [String: String] = [:]) {
        self.storage = initialStorage
    }

    func string(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func set(_ value: String?, forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if let value = value, !value.isEmpty {
            storage[key] = value
        } else {
            storage.removeValue(forKey: key)
        }
    }

    func delete(forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }
}

/// In-memory mock ground-truth store restricted strictly to automated unit tests.
final class MockBenchmarkTruthStore: BenchmarkTruthStoreProtocol, @unchecked Sendable {
    var payload: BenchmarkTruthPayload?
    var canonicalFileURL: URL
    var shouldThrowError: Error?

    init(
        payload: BenchmarkTruthPayload? = nil,
        canonicalFileURL: URL = FileManager.default.temporaryDirectory.appendingPathComponent("mock-benchmark-truth.json"),
        shouldThrowError: Error? = nil
    ) {
        self.payload = payload
        self.canonicalFileURL = canonicalFileURL
        self.shouldThrowError = shouldThrowError
    }

    func loadTruth() -> BenchmarkTruthPayload? {
        payload
    }

    func saveTruth(_ payload: BenchmarkTruthPayload) throws {
        if let error = shouldThrowError {
            throw error
        }
        self.payload = payload
    }
}

/// Cross-platform PKZIP archive builder for iOS Simulator and macOS tests.
enum TestZipBuilder {
    struct Entry {
        var path: String
        var data: Data
        var useDeflate: Bool = true
    }

    static func writeZip(entries: [Entry], to destinationURL: URL) throws {
        var archive = Data()
        var centralDirectory = Data()

        for entry in entries {
            let localHeaderOffset = UInt32(archive.count)
            let nameBytes = Data(entry.path.utf8)
            let isDirectory = entry.path.hasSuffix("/")
            let uncompressed = isDirectory ? Data() : entry.data

            let crc: UInt32 = uncompressed.withUnsafeBytes { rawBuf in
                let initial = zlib.crc32(0, nil, 0)
                guard let ptr = rawBuf.bindMemory(to: Bytef.self).baseAddress, !rawBuf.isEmpty else {
                    return UInt32(initial)
                }
                return UInt32(zlib.crc32(initial, ptr, uInt(rawBuf.count)))
            }

            let method: UInt16 = (!isDirectory && entry.useDeflate) ? 8 : 0
            let compressed: Data = (method == 8) ? try deflateRaw(uncompressed) : uncompressed

            // Local File Header (0x04034b50)
            archive.appendUInt32LE(0x04034b50)
            archive.appendUInt16LE(20) // version needed
            archive.appendUInt16LE(0)  // flags
            archive.appendUInt16LE(method)
            archive.appendUInt16LE(0)  // mod time
            archive.appendUInt16LE(0)  // mod date
            archive.appendUInt32LE(crc)
            archive.appendUInt32LE(UInt32(compressed.count))
            archive.appendUInt32LE(UInt32(uncompressed.count))
            archive.appendUInt16LE(UInt16(nameBytes.count))
            archive.appendUInt16LE(0)  // extra length
            archive.append(nameBytes)
            archive.append(compressed)

            // Central Directory Header (0x02014b50)
            let externalAttrs: UInt32 = isDirectory ? (0x41ED << 16) : (0x81A4 << 16)
            centralDirectory.appendUInt32LE(0x02014b50)
            centralDirectory.appendUInt16LE(0x0314) // version made by (UNIX)
            centralDirectory.appendUInt16LE(20)     // version needed
            centralDirectory.appendUInt16LE(0)      // flags
            centralDirectory.appendUInt16LE(method)
            centralDirectory.appendUInt16LE(0)      // mod time
            centralDirectory.appendUInt16LE(0)      // mod date
            centralDirectory.appendUInt32LE(crc)
            centralDirectory.appendUInt32LE(UInt32(compressed.count))
            centralDirectory.appendUInt32LE(UInt32(uncompressed.count))
            centralDirectory.appendUInt16LE(UInt16(nameBytes.count))
            centralDirectory.appendUInt16LE(0)      // extra length
            centralDirectory.appendUInt16LE(0)      // comment length
            centralDirectory.appendUInt16LE(0)      // disk number
            centralDirectory.appendUInt16LE(0)      // internal attrs
            centralDirectory.appendUInt32LE(externalAttrs)
            centralDirectory.appendUInt32LE(localHeaderOffset)
            centralDirectory.append(nameBytes)
        }

        let cdOffset = UInt32(archive.count)
        let cdSize = UInt32(centralDirectory.count)
        archive.append(centralDirectory)

        // End of Central Directory (0x06054b50)
        archive.appendUInt32LE(0x06054b50)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(UInt16(entries.count))
        archive.appendUInt16LE(UInt16(entries.count))
        archive.appendUInt32LE(cdSize)
        archive.appendUInt32LE(cdOffset)
        archive.appendUInt16LE(0)

        try archive.write(to: destinationURL, options: .atomic)
    }

    private static func deflateRaw(_ input: Data) throws -> Data {
        var stream = z_stream()
        let status = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            -MAX_WBITS,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard status == Z_OK else {
            throw CoreMLError.extractionFailed(exitCode: status)
        }
        defer { deflateEnd(&stream) }

        var output = Data()
        var chunk = [UInt8](repeating: 0, count: 16_384)

        let finishStatus: Int32 = input.withUnsafeBytes { rawBuf in
            if let base = rawBuf.bindMemory(to: Bytef.self).baseAddress, !rawBuf.isEmpty {
                stream.next_in = UnsafeMutablePointer<Bytef>(mutating: base)
                stream.avail_in = uInt(rawBuf.count)
            } else {
                stream.next_in = nil
                stream.avail_in = 0
            }

            while true {
                let res: Int32 = chunk.withUnsafeMutableBufferPointer { outBuf in
                    stream.next_out = outBuf.baseAddress
                    stream.avail_out = uInt(outBuf.count)
                    return zlib.deflate(&stream, Z_FINISH)
                }
                let produced = chunk.count - Int(stream.avail_out)
                if produced > 0 {
                    output.append(chunk, count: produced)
                }
                if res == Z_STREAM_END {
                    return Z_STREAM_END
                }
                if res != Z_OK {
                    return res
                }
            }
        }

        guard finishStatus == Z_STREAM_END else {
            throw CoreMLError.extractionFailed(exitCode: finishStatus)
        }
        return output
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}
