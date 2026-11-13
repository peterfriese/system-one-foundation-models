import Foundation
import FoundationModels
import UniformTypeIdentifiers
@_exported import SystemOneCore

/// An Apple Foundation Models provider for on-device Laya decision models running locally via Core ML.
public struct LayaOnDeviceLanguageModel: LanguageModel, Sendable {
    public struct Configuration: Hashable, Sendable {
        public var backend: AnySystemOneBackend
        public var modelID: String

        public init(backend: any SystemOneBackend, modelID: String = "laya-ondevice") {
            self.backend = (backend as? AnySystemOneBackend) ?? AnySystemOneBackend(backend)
            self.modelID = modelID
        }

        public init(engine: LayaCoreMLEngine, modelID: String = "laya-ondevice") {
            let onDeviceBackend = LayaOnDeviceBackend(engine: engine)
            self.backend = AnySystemOneBackend(onDeviceBackend)
            self.modelID = modelID
        }
    }

    public typealias Executor = LayaOnDeviceExecutor

    public var executorConfiguration: Configuration

    public var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities([.guidedGeneration])
    }

    /// Initializes an on-device Laya model by resolving `modelURL` (or `LAYA_MODEL_PATH` / bundled `LayaDecisionModel.mlmodelc`)
    /// and an optional or adjacent `tokenizer.json`.
    public init(
        modelURL: URL? = nil,
        tokenizer: (any LayaTokenizer)? = nil,
        modelID: String = "laya-ondevice"
    ) throws {
        let resolvedModelURL = try Self.resolveModelURL(explicit: modelURL)
        let resolvedTokenizer = try Self.resolveTokenizer(explicit: tokenizer, adjacentTo: resolvedModelURL)
        let engine = try LayaCoreMLEngine(modelURL: resolvedModelURL, tokenizer: resolvedTokenizer)
        self.init(engine: engine, modelID: modelID)
    }

    public init(engine: LayaCoreMLEngine, modelID: String = "laya-ondevice") {
        let backend = AnySystemOneBackend(LayaOnDeviceBackend(engine: engine))
        self.executorConfiguration = Configuration(backend: backend, modelID: modelID)
    }

    public init(backend: any SystemOneBackend, modelID: String = "laya-ondevice") {
        self.executorConfiguration = Configuration(backend: backend, modelID: modelID)
    }

    public init(configuration: Configuration) {
        self.executorConfiguration = configuration
    }

    public func supportsDataAttachmentType(_ type: UTType) async throws -> Bool {
        false
    }

    public func supportsDataEntryType(_ type: UTType) async throws -> Bool {
        false
    }

    private static func resolveModelURL(explicit: URL?) throws -> URL {
        let fm = FileManager.default
        if let explicit {
            guard explicit.isFileURL else {
                throw SystemOneError.modelExecutionError("Model URL must be a local file:// URL, got '\(explicit.scheme ?? "unknown")'.")
            }
            guard fm.fileExists(atPath: explicit.path) else {
                throw SystemOneError.modelExecutionError(
                    "Core ML model not found at '\(explicit.path)'. Export LAYA_MODEL_PATH=/path/to/LayaDecisionModel.mlmodelc or run Tools/CoreMLConverter/convert_laya_to_coreml.py."
                )
            }
            return explicit
        }

        let env = ProcessInfo.processInfo.environment
        if let rawPath = env["LAYA_MODEL_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawPath.isEmpty {
            let expanded = (rawPath as NSString).expandingTildeInPath
            let candidate = URL(fileURLWithPath: expanded)
            guard fm.fileExists(atPath: candidate.path) else {
                throw SystemOneError.modelExecutionError(
                    "LAYA_MODEL_PATH points to non-existent file '\(candidate.path)'. Verify the path to your compiled .mlmodelc or .mlpackage."
                )
            }
            return candidate
        }

        if let bundledCompiled = Bundle.main.url(forResource: "LayaDecisionModel", withExtension: "mlmodelc") {
            return bundledCompiled
        }
        if let bundledPackage = Bundle.main.url(forResource: "LayaDecisionModel", withExtension: "mlpackage") {
            return bundledPackage
        }

        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        for name in ["LayaDecisionModel.mlmodelc", "LayaDecisionModel.mlpackage"] {
            let candidate = cwd.appendingPathComponent(name)
            if fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        throw SystemOneError.modelExecutionError(
            "Missing on-device Laya Core ML model. Export LAYA_MODEL_PATH=/path/to/LayaDecisionModel.mlmodelc (convert HuggingFace weights via Tools/CoreMLConverter/convert_laya_to_coreml.py) or bundle LayaDecisionModel.mlmodelc in your target."
        )
    }

    private static func resolveTokenizer(explicit: (any LayaTokenizer)?, adjacentTo modelURL: URL) throws -> any LayaTokenizer {
        if let explicit {
            return explicit
        }
        let fm = FileManager.default
        if let rawTokenizerPath = ProcessInfo.processInfo.environment["LAYA_TOKENIZER_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawTokenizerPath.isEmpty {
            let expanded = (rawTokenizerPath as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            if let modern = try? ModernBERTTokenizer(jsonURL: url) {
                return modern
            }
            return try MMBERTTokenizer(jsonURL: url)
        }

        let adjacentURL = modelURL.deletingLastPathComponent().appendingPathComponent("tokenizer.json")
        if fm.fileExists(atPath: adjacentURL.path) {
            if let modern = try? ModernBERTTokenizer(jsonURL: adjacentURL) {
                return modern
            }
            if let mmbert = try? MMBERTTokenizer(jsonURL: adjacentURL) {
                return mmbert
            }
        }

        return ModernBERTTokenizer.defaultTokenizer()
    }
}

/// An executor bridging `LanguageModelSession` requests to an on-device Laya Core ML engine.
public final class LayaOnDeviceExecutor: LanguageModelExecutor, Sendable {
    public typealias Model = LayaOnDeviceLanguageModel
    public typealias Configuration = LayaOnDeviceLanguageModel.Configuration

    public let configuration: Configuration
    private let underlyingExecutor: SystemOneExecutor
    private let coreModel: SystemOneLanguageModel

    public init(configuration: Configuration) throws {
        self.configuration = configuration
        let coreConfig = SystemOneLanguageModel.Configuration(
            backend: configuration.backend,
            modelID: configuration.modelID
        )
        self.coreModel = SystemOneLanguageModel(configuration: coreConfig)
        self.underlyingExecutor = SystemOneExecutor(configuration: coreConfig)
    }

    public func prewarm(model: LayaOnDeviceLanguageModel, transcript: Transcript) {
        underlyingExecutor.prewarm(model: coreModel, transcript: transcript)
    }

    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: LayaOnDeviceLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        try await underlyingExecutor.respond(to: request, model: coreModel, streamingInto: channel)
    }

    public func extractState(from transcript: Transcript) -> String {
        underlyingExecutor.extractState(from: transcript)
    }
}
