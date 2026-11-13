import Foundation
import FactoryKit

/// Protocol defining storage and persistence operations for canonical benchmark truth data.
public protocol BenchmarkTruthStoreProtocol: Sendable {
    /// Canonical file system location for benchmark-truth.json.
    var canonicalFileURL: URL { get }

    /// Loads the latest benchmark ground-truth payload from disk or bundled resource.
    func loadTruth() -> BenchmarkTruthPayload?

    /// Atomically persists a benchmark ground-truth payload to the canonical file location.
    func saveTruth(_ payload: BenchmarkTruthPayload) throws
}

/// Production ground-truth store persisting canonical laboratory benchmark measurements to Application Support.
public final class BenchmarkTruthStore: BenchmarkTruthStoreProtocol, @unchecked Sendable {
    private let customURL: URL?
    private let fileManager: FileManager
    private let checkBundledResource: Bool

    public init(customURL: URL? = nil, fileManager: FileManager = .default, checkBundledResource: Bool = true) {
        self.customURL = customURL
        self.fileManager = fileManager
        self.checkBundledResource = checkBundledResource
    }

    /// Canonical path: Application Support/MailTriage/benchmark-truth.json.
    public var canonicalFileURL: URL {
        if let customURL {
            return customURL
        }
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MailTriage")
        return dir.appendingPathComponent("benchmark-truth.json")
    }

    public func loadTruth() -> BenchmarkTruthPayload? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // 1. Check canonical file in Application Support
        if fileManager.fileExists(atPath: canonicalFileURL.path),
           let data = try? Data(contentsOf: canonicalFileURL),
           let truth = try? decoder.decode(BenchmarkTruthPayload.self, from: data) {
            return truth
        }

        guard checkBundledResource else {
            return nil
        }

        // 2. Fall back to bundled module resource if packaged with AppCore
        #if SWIFT_PACKAGE
        if let moduleURL = Bundle.module.url(forResource: "benchmark-truth", withExtension: "json"),
           let data = try? Data(contentsOf: moduleURL),
           let truth = try? decoder.decode(BenchmarkTruthPayload.self, from: data) {
            return truth
        }
        #endif

        // 3. Fall back to main app bundle
        if let mainURL = Bundle.main.url(forResource: "benchmark-truth", withExtension: "json"),
           let data = try? Data(contentsOf: mainURL),
           let truth = try? decoder.decode(BenchmarkTruthPayload.self, from: data) {
            return truth
        }

        return nil
    }

    public func saveTruth(_ payload: BenchmarkTruthPayload) throws {
        let destinationURL = canonicalFileURL
        let parentDir = destinationURL.deletingLastPathComponent()

        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(payload)
        try data.write(to: destinationURL, options: .atomic)
    }
}
