import Foundation
import Observation
@preconcurrency import CoreML
import FactoryKit
import zlib

/// Strongly-typed domain error for Core ML model management operations.
public enum CoreMLError: Error, LocalizedError, Sendable, Equatable, CustomNSError {
    case invalidURL(String)
    case insecureURL(String)
    case downloadFailed(statusCode: Int, message: String)
    case unsupportedFormat(String)
    case uncompiledWeights(String)
    case extractionFailed(exitCode: Int32)
    case modelNotFound(String)
    case modelNotFoundInArchive
    case compilationFailed(String)

    public static var errorDomain: String { "CoreMLModelManager" }

    public var errorCode: Int {
        switch self {
        case .invalidURL: return 1
        case .insecureURL: return 400
        case .downloadFailed(let statusCode, _): return statusCode
        case .unsupportedFormat: return 400
        case .uncompiledWeights: return 422
        case .extractionFailed(let exitCode): return Int(exitCode)
        case .modelNotFound: return 404
        case .modelNotFoundInArchive: return 2
        case .compilationFailed: return 500
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return url.isEmpty
                ? "No Core ML download URL configured. Provide a compiled Core ML (.mlmodelc.zip / .mlpackage.zip) HTTPS URL or import a converted local model."
                : "Invalid download URL configured: \(url)"
        case .insecureURL(let message):
            return "Insecure download URL: \(message)"
        case .downloadFailed(let statusCode, let message):
            return "Download failed (HTTP \(statusCode)): \(message)"
        case .unsupportedFormat(let ext):
            let normalized = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return "Unsupported model format: .\(normalized). Please provide an .mlmodel, .mlpackage, .mlmodelc, or .zip archive."
        case .uncompiledWeights(let filename):
            return "Raw weights (\(filename)) cannot run directly on Core ML. Convert them to Core ML first with: python3 Tools/CoreMLConverter/convert_laya_to_coreml.py"
        case .extractionFailed(let exitCode):
            return "Archive extraction failed with exit code \(exitCode)"
        case .modelNotFound(let path):
            return "Model file does not exist at: \(path)"
        case .modelNotFoundInArchive:
            return "No .mlmodel, .mlpackage, or .mlmodelc found in extracted archive"
        case .compilationFailed(let message):
            return "Compilation failed: \(message)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .invalidURL, .insecureURL:
            return "Please provide a valid HTTPS URL to a Core ML model archive in Settings."
        case .downloadFailed(let statusCode, _):
            if statusCode == 401 {
                return "Check that your Hugging Face access token has read permissions for this model repository."
            }
            return "Check your network connection and verify the remote model server is reachable."
        case .unsupportedFormat:
            return "Import a valid Core ML package (.mlpackage), compiled model (.mlmodelc), or a .zip archive containing one."
        case .uncompiledWeights:
            return "Run `python3 Tools/CoreMLConverter/convert_laya_to_coreml.py` to convert .safetensors weights into a Core ML .mlpackage, then import the converted package."
        case .extractionFailed:
            return "Ensure the downloaded or imported zip archive is not corrupted."
        case .modelNotFound:
            return "Verify that the specified file path exists on disk and is accessible."
        case .modelNotFoundInArchive:
            return "Verify the zip archive contains a valid Core ML model bundle (.mlmodel, .mlpackage, or .mlmodelc)."
        case .compilationFailed:
            return "Check system console logs or re-download the model bundle."
        }
    }
}

/// Manages on-device Core ML model discovery, download, compilation, and storage.
@Observable
public final class CoreMLModelManager: @unchecked Sendable {
    private let lock = NSLock()
    private var _customModelsDirectory: URL? = nil

    @ObservationIgnored
    @Injected(\.backendConfigurationStore) private var configStore

    public var isDownloading: Bool = false
    public var isCompiling: Bool = false
    public var downloadProgress: Double = 0.0
    public var statusMessage: String = ""
    public var errorMessage: String? = nil

    public init() {}

    // MARK: - File Paths

    public var customModelsDirectory: URL? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _customModelsDirectory
        }
        set {
            lock.lock()
            _customModelsDirectory = newValue
            lock.unlock()
        }
    }

    public var modelsDirectory: URL {
        if let custom = customModelsDirectory {
            try? FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
            return custom
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "dev.peterfriese.mailtriageapp"
        let dir = appSupport.appendingPathComponent(bundleID).appendingPathComponent("Models")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public var canonicalModelURL: URL {
        modelsDirectory.appendingPathComponent("LayaDecisionModel.mlmodelc")
    }

    public var legacyModelURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Models").appendingPathComponent("LayaDecisionModel.mlmodelc")
    }

    /// Returns the active model URL if found on disk.
    public var resolvedModelURL: URL? {
        if let custom = customModelsDirectory {
            let customModelURL = custom.appendingPathComponent("LayaDecisionModel.mlmodelc")
            if FileManager.default.fileExists(atPath: customModelURL.path) {
                return customModelURL
            }
            let customSafetensors = custom.appendingPathComponent("model.safetensors")
            if FileManager.default.fileExists(atPath: customSafetensors.path) {
                return customSafetensors
            }
            return nil
        }

        // Auto-migrate legacy model path to canonical path if found
        if !FileManager.default.fileExists(atPath: canonicalModelURL.path) && FileManager.default.fileExists(atPath: legacyModelURL.path) {
            try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
            if (try? FileManager.default.copyItem(at: legacyModelURL, to: canonicalModelURL)) != nil {
                try? FileManager.default.removeItem(at: legacyModelURL)
                return canonicalModelURL
            }
            return legacyModelURL
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let candidateURLs: [URL] = [
            canonicalModelURL,
            appSupport.appendingPathComponent("dev.peterfriese.mailtriageapp").appendingPathComponent("Models").appendingPathComponent("LayaDecisionModel.mlmodelc"),
            appSupport.appendingPathComponent("dev.peterfriese.mailtriageapp").appendingPathComponent("Models").appendingPathComponent("model.safetensors"),
            appSupport.appendingPathComponent("MailTriage").appendingPathComponent("Models").appendingPathComponent("LayaDecisionModel.mlmodelc"),
            appSupport.appendingPathComponent("MailTriage").appendingPathComponent("Models").appendingPathComponent("model.safetensors"),
            appSupport.appendingPathComponent(Bundle.main.bundleIdentifier ?? "dev.peterfriese.mailtriageapp").appendingPathComponent("Models").appendingPathComponent("LayaDecisionModel.mlmodelc"),
            appSupport.appendingPathComponent(Bundle.main.bundleIdentifier ?? "dev.peterfriese.mailtriageapp").appendingPathComponent("Models").appendingPathComponent("model.safetensors"),
            appSupport.appendingPathComponent("ai.typesafe.MailTriage").appendingPathComponent("Models").appendingPathComponent("LayaDecisionModel.mlmodelc"),
            appSupport.appendingPathComponent("ai.typesafe.MailTriage").appendingPathComponent("Models").appendingPathComponent("model.safetensors"),
            legacyModelURL
        ]

        for candidate in candidateURLs {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    public var isInstalled: Bool {
        resolvedModelURL != nil
    }

    /// Returns human-readable model size on disk (e.g., "412.5 MB").
    public var modelSizeFormatted: String? {
        guard let url = resolvedModelURL else { return nil }
        guard let size = directorySize(at: url) else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    // MARK: - Download & Compile

    /// Resolves a Hugging Face repository URL to its compiled Core ML archive URL if no explicit file path is given.
    public static func resolveDownloadURL(_ inputURL: URL) -> URL {
        if inputURL.absoluteString.contains("/resolve/") {
            return inputURL
        }
        var str = inputURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if str.contains("huggingface.co") && !str.contains("/resolve/") {
            if let treeRange = str.range(of: "/tree/main") {
                str.removeSubrange(treeRange)
                str = str.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            let ext = URL(string: str)?.pathExtension.lowercased() ?? ""
            if ext.isEmpty {
                str += "/resolve/main/LayaDecisionModel.mlmodelc.zip"
                return URL(string: str) ?? inputURL
            }
        }
        return inputURL
    }

    public func downloadAndCompile(from sourceURL: URL? = nil) async throws {
        await MainActor.run {
            self.isDownloading = true
            self.isCompiling = false
            self.downloadProgress = 0.0
            self.statusMessage = "Starting download..."
            self.errorMessage = nil
        }

        var completedSuccessfully = false
        defer {
            if !completedSuccessfully {
                Task { @MainActor [weak self] in
                    self?.isDownloading = false
                    self?.isCompiling = false
                }
            }
        }

        let rawDownloadURL: URL
        if let sourceURL {
            rawDownloadURL = sourceURL
        } else {
            let trimmed = configStore.coreMLDownloadURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let parsed = URL(string: trimmed) else {
                let error = CoreMLError.invalidURL(trimmed)
                await setErrorMessage(error.localizedDescription)
                throw error
            }
            rawDownloadURL = parsed
        }

        let downloadURL = Self.resolveDownloadURL(rawDownloadURL)

        // Validate scheme and transport security (SEC-3 / SEC-4)
        guard let scheme = downloadURL.scheme?.lowercased(),
              scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(downloadURL.host?.lowercased() ?? "")) else {
            let error = CoreMLError.insecureURL("HTTPS is required for remote model downloads.")
            await setErrorMessage(error.localizedDescription)
            throw error
        }

        // Reject raw uncompiled weights (.safetensors / .bin) immediately before downloading or overwriting canonicalModelURL
        let urlExt = downloadURL.pathExtension.lowercased()
        if urlExt == "safetensors" || urlExt == "bin" {
            let error = CoreMLError.uncompiledWeights(downloadURL.lastPathComponent)
            await setErrorMessage(error.localizedDescription)
            throw error
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // 1. Download model file directly to disk via URLSession streaming
        let workingFile = tempDir.appendingPathComponent(downloadURL.lastPathComponent.isEmpty ? "model.zip" : downloadURL.lastPathComponent)
        do {
            var request = URLRequest(url: downloadURL)
            let token = configStore.huggingFaceToken.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Domain-restricted authorization (SEC-3): Only send token to official Hugging Face domains
            let host = downloadURL.host?.lowercased() ?? ""
            let isHuggingFaceHost = host == "huggingface.co" || host.hasSuffix(".huggingface.co")
            if !token.isEmpty && isHuggingFaceHost {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let delegate = ModelDownloadDelegate { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress
                    self?.statusMessage = "Downloading model: \(Int(progress * 100))%"
                }
            }

            var (tempDownloadedURL, response) = try await URLSession.shared.download(for: request, delegate: delegate)

            // If 401 and an authorization header was used, retry without authorization for public repos (SEC-3)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 && !token.isEmpty && isHuggingFaceHost {
                let publicRequest = URLRequest(url: downloadURL)
                (tempDownloadedURL, response) = try await URLSession.shared.download(for: publicRequest, delegate: delegate)
            }

            if let http = response as? HTTPURLResponse {
                if http.statusCode == 401 {
                    let msg = "Repository not found or private on Hugging Face. Check the URL or provide an Access Token."
                    throw CoreMLError.downloadFailed(statusCode: 401, message: msg)
                }
                guard (200...299).contains(http.statusCode) else {
                    let msg = "HTTP download failed with status \(http.statusCode)"
                    throw CoreMLError.downloadFailed(statusCode: http.statusCode, message: msg)
                }
            }

            if FileManager.default.fileExists(atPath: workingFile.path) {
                try FileManager.default.removeItem(at: workingFile)
            }
            try FileManager.default.moveItem(at: tempDownloadedURL, to: workingFile)
        } catch {
            await MainActor.run {
                self.isDownloading = false
                self.isCompiling = false
            }
            let errorToThrow: Error
            if let coreMLError = error as? CoreMLError {
                errorToThrow = coreMLError
            } else {
                errorToThrow = CoreMLError.downloadFailed(statusCode: (error as NSError).code, message: error.localizedDescription)
            }
            await setErrorMessage("Download failed: \(errorToThrow.localizedDescription)")
            throw errorToThrow
        }

        // 2. Prepare & compile model on-device
        await MainActor.run {
            self.isDownloading = false
            self.isCompiling = true
            self.statusMessage = "Preparing model package..."
        }

        var modelToCompile: URL = workingFile
        var precompiledModel: URL? = nil

        let ext = workingFile.pathExtension.lowercased()
        if ext == "safetensors" || ext == "bin" {
            let error = CoreMLError.uncompiledWeights(workingFile.lastPathComponent)
            await setErrorMessage(error.localizedDescription)
            throw error
        } else if ext == "mlmodelc" {
            precompiledModel = workingFile
        } else if ext == "zip" {
            await MainActor.run {
                self.statusMessage = "Extracting model archive..."
            }

            let extractedDir = tempDir.appendingPathComponent("extracted")
            try FileManager.default.createDirectory(at: extractedDir, withIntermediateDirectories: true)

            do {
                try Self.extractZipArchive(at: workingFile, to: extractedDir)
            } catch let coreMLError as CoreMLError {
                await setErrorMessage(coreMLError.localizedDescription)
                throw coreMLError
            } catch {
                let extractionError = CoreMLError.extractionFailed(exitCode: 1)
                await setErrorMessage(extractionError.localizedDescription)
                throw extractionError
            }

            // Locate .mlmodelc, .mlpackage, or .mlmodel within extracted folder
            var foundRawWeightsName: String? = nil
            let enumerator = FileManager.default.enumerator(at: extractedDir, includingPropertiesForKeys: [.isDirectoryKey])
            while let fileURL = enumerator?.nextObject() as? URL {
                let fileExt = fileURL.pathExtension.lowercased()
                if fileExt == "mlmodelc" {
                    precompiledModel = fileURL
                    break
                } else if fileExt == "mlpackage" || fileExt == "mlmodel" {
                    modelToCompile = fileURL
                    break
                } else if fileExt == "safetensors" || fileExt == "bin" {
                    foundRawWeightsName = fileURL.lastPathComponent
                }
            }

            if precompiledModel == nil && modelToCompile == workingFile {
                let error: CoreMLError = if let foundRawWeightsName {
                    .uncompiledWeights(foundRawWeightsName)
                } else {
                    .modelNotFoundInArchive
                }
                await setErrorMessage(error.localizedDescription)
                throw error
            }
        } else if ext == "mlpackage" || ext == "mlmodel" {
            modelToCompile = workingFile
        } else {
            let error = CoreMLError.unsupportedFormat(ext)
            await setErrorMessage(error.localizedDescription)
            throw error
        }

        do {
            let finalCompiledURL: URL
            if let precompiledModel {
                finalCompiledURL = precompiledModel
            } else {
                await MainActor.run {
                    self.statusMessage = "Compiling for Apple Neural Engine..."
                }
                finalCompiledURL = try await MLModel.compileModel(at: modelToCompile)
            }
            defer {
                if precompiledModel == nil {
                    try? FileManager.default.removeItem(at: finalCompiledURL)
                }
            }

            // 3. Move to permanent Application Support location
            if FileManager.default.fileExists(atPath: canonicalModelURL.path) {
                try FileManager.default.removeItem(at: canonicalModelURL)
            }

            try FileManager.default.moveItem(at: finalCompiledURL, to: canonicalModelURL)

            await MainActor.run {
                self.isDownloading = false
                self.isCompiling = false
                self.statusMessage = "Ready for inference"
                self.downloadProgress = 1.0
                self.errorMessage = nil
            }
            completedSuccessfully = true
        } catch {
            await MainActor.run {
                self.isDownloading = false
                self.isCompiling = false
            }
            let errorToThrow: Error
            if let coreMLError = error as? CoreMLError {
                errorToThrow = coreMLError
            } else {
                errorToThrow = CoreMLError.compilationFailed(error.localizedDescription)
            }
            await setErrorMessage("Compilation failed: \(errorToThrow.localizedDescription)")
            throw errorToThrow
        }
    }

    // MARK: - Local Model Import

    /// Imports a local model file (.mlmodel, .mlpackage, .mlmodelc, or .zip archive) from disk into the canonical Application Support location.
    public func importLocalModel(from sourceURL: URL) async throws {
        let shouldStopAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        await MainActor.run {
            self.isDownloading = false
            self.isCompiling = true
            self.downloadProgress = 0.0
            self.statusMessage = "Importing model..."
            self.errorMessage = nil
        }

        var completedSuccessfully = false
        defer {
            if !completedSuccessfully {
                Task { @MainActor [weak self] in
                    self?.isCompiling = false
                }
            }
        }

        do {
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                let error = CoreMLError.modelNotFound(sourceURL.path)
                await setErrorMessage(error.localizedDescription)
                throw error
            }

            _ = modelsDirectory

            let ext = sourceURL.pathExtension.lowercased()
            let finalCompiledURL: URL
            var tempExtractionDir: URL? = nil

            if ext == "safetensors" || ext == "bin" {
                let error = CoreMLError.uncompiledWeights(sourceURL.lastPathComponent)
                await setErrorMessage(error.localizedDescription)
                throw error
            } else if ext == "mlmodelc" {
                finalCompiledURL = sourceURL
            } else if ext == "zip" {
                await MainActor.run {
                    self.statusMessage = "Extracting model archive..."
                }
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("import_\(UUID().uuidString)")
                tempExtractionDir = tempDir
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

                do {
                    try Self.extractZipArchive(at: sourceURL, to: tempDir)
                } catch let coreMLError as CoreMLError {
                    try? FileManager.default.removeItem(at: tempDir)
                    await setErrorMessage(coreMLError.localizedDescription)
                    throw coreMLError
                } catch {
                    try? FileManager.default.removeItem(at: tempDir)
                    let extractionError = CoreMLError.extractionFailed(exitCode: 1)
                    await setErrorMessage(extractionError.localizedDescription)
                    throw extractionError
                }

                var foundPrecompiled: URL? = nil
                var foundToCompile: URL? = nil
                var foundRawWeightsName: String? = nil

                let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: [.isDirectoryKey])
                while let fileURL = enumerator?.nextObject() as? URL {
                    let fileExt = fileURL.pathExtension.lowercased()
                    if fileExt == "mlmodelc" {
                        foundPrecompiled = fileURL
                        break
                    } else if fileExt == "mlpackage" || fileExt == "mlmodel" {
                        foundToCompile = fileURL
                        break
                    } else if fileExt == "safetensors" || fileExt == "bin" {
                        foundRawWeightsName = fileURL.lastPathComponent
                    }
                }

                if let foundPrecompiled {
                    finalCompiledURL = foundPrecompiled
                } else if let foundToCompile {
                    await MainActor.run {
                        self.statusMessage = "Compiling for Apple Neural Engine..."
                    }
                    do {
                        finalCompiledURL = try await MLModel.compileModel(at: foundToCompile)
                    } catch {
                        try? FileManager.default.removeItem(at: tempDir)
                        throw error
                    }
                } else {
                    try? FileManager.default.removeItem(at: tempDir)
                    let error: CoreMLError = if let foundRawWeightsName {
                        .uncompiledWeights(foundRawWeightsName)
                    } else {
                        .modelNotFoundInArchive
                    }
                    await setErrorMessage(error.localizedDescription)
                    throw error
                }
            } else if ext == "mlmodel" || ext == "mlpackage" {
                await MainActor.run {
                    self.statusMessage = "Compiling for Apple Neural Engine..."
                }
                finalCompiledURL = try await MLModel.compileModel(at: sourceURL)
            } else {
                let error = CoreMLError.unsupportedFormat(ext)
                await setErrorMessage(error.localizedDescription)
                throw error
            }

            defer {
                if let tempExtractionDir {
                    try? FileManager.default.removeItem(at: tempExtractionDir)
                }
                if finalCompiledURL != sourceURL && finalCompiledURL.path != tempExtractionDir?.path {
                    try? FileManager.default.removeItem(at: finalCompiledURL)
                }
            }

            // Remove existing canonical model if present
            if FileManager.default.fileExists(atPath: canonicalModelURL.path) {
                try FileManager.default.removeItem(at: canonicalModelURL)
            }
            if FileManager.default.fileExists(atPath: legacyModelURL.path) {
                try? FileManager.default.removeItem(at: legacyModelURL)
            }

            // Copy to canonical location
            try FileManager.default.copyItem(at: finalCompiledURL, to: canonicalModelURL)

            await MainActor.run {
                self.statusMessage = "Ready for inference"
                self.downloadProgress = 1.0
                self.errorMessage = nil
            }
            completedSuccessfully = true
        } catch {
            await MainActor.run {
                self.isCompiling = false
            }
            let errorToThrow: Error
            if let coreMLError = error as? CoreMLError {
                errorToThrow = coreMLError
            } else {
                errorToThrow = CoreMLError.compilationFailed(error.localizedDescription)
            }
            await setErrorMessage("Import failed: \(errorToThrow.localizedDescription)")
            throw errorToThrow
        }
    }

    public func removeInstalledModel() throws {
        if let resolved = resolvedModelURL, FileManager.default.fileExists(atPath: resolved.path) {
            try FileManager.default.removeItem(at: resolved)
        }
        if FileManager.default.fileExists(atPath: canonicalModelURL.path) {
            try FileManager.default.removeItem(at: canonicalModelURL)
        }
        if FileManager.default.fileExists(atPath: legacyModelURL.path) {
            try? FileManager.default.removeItem(at: legacyModelURL)
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.statusMessage = "Model removed"
                self.downloadProgress = 0.0
                self.errorMessage = nil
            }
        } else {
            Task { @MainActor [weak self] in
                self?.statusMessage = "Model removed"
                self?.downloadProgress = 0.0
                self?.errorMessage = nil
            }
        }
    }

    // MARK: - Cross-Platform ZIP Extraction (iOS & macOS)

    /// Extracts standard PKZIP archives (Stored method 0 and Deflate method 8) on both iOS and macOS
    /// using Darwin `zlib`, with Central Directory parsing and Zip-Slip path containment.
    public static func extractZipArchive(at archiveURL: URL, to destinationDir: URL) throws {
        let data = try Data(contentsOf: archiveURL, options: .mappedIfSafe)
        guard data.count >= 22 else {
            throw CoreMLError.extractionFailed(exitCode: 1)
        }

        // Locate End of Central Directory (EOCD) signature 0x06054b50 scanning backwards from end of file
        let minEOCDOffset = max(0, data.count - 65_557)
        var foundEOCDOffset: Int? = nil
        var candidate = data.count - 22
        while candidate >= minEOCDOffset {
            if readUInt32LE(data, at: candidate) == 0x06054b50 {
                let commentLen = Int(readUInt16LE(data, at: candidate + 20))
                if candidate + 22 + commentLen <= data.count {
                    foundEOCDOffset = candidate
                    break
                }
            }
            candidate -= 1
        }

        guard let eocdOffset = foundEOCDOffset else {
            throw CoreMLError.extractionFailed(exitCode: 1)
        }

        let totalEntries = Int(readUInt16LE(data, at: eocdOffset + 10))
        let centralDirSize = Int(readUInt32LE(data, at: eocdOffset + 12))
        let centralDirOffset = Int(readUInt32LE(data, at: eocdOffset + 16))

        // On macOS, if ZIP64 sentinel values are encountered (>4GB archive), fall back to /usr/bin/ditto
        if totalEntries == 0xFFFF || centralDirOffset == 0xFFFF_FFFF {
            #if os(macOS)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-xk", archiveURL.path, destinationDir.path]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw CoreMLError.extractionFailed(exitCode: process.terminationStatus)
            }
            return
            #else
            throw CoreMLError.extractionFailed(exitCode: 1)
            #endif
        }

        guard centralDirOffset >= 0, centralDirSize >= 0, centralDirOffset + centralDirSize <= eocdOffset else {
            throw CoreMLError.extractionFailed(exitCode: 1)
        }

        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        let safeRoot = destinationDir.resolvingSymlinksInPath().standardizedFileURL
        let safeRootPrefix = safeRoot.path.hasSuffix("/") ? safeRoot.path : (safeRoot.path + "/")

        var cdCursor = centralDirOffset
        for _ in 0..<totalEntries {
            guard cdCursor + 46 <= data.count, readUInt32LE(data, at: cdCursor) == 0x02014b50 else {
                throw CoreMLError.extractionFailed(exitCode: 1)
            }

            let compressionMethod = readUInt16LE(data, at: cdCursor + 10)
            let expectedCRC = readUInt32LE(data, at: cdCursor + 16)
            let compressedSize = Int(readUInt32LE(data, at: cdCursor + 20))
            let uncompressedSize = Int(readUInt32LE(data, at: cdCursor + 24))
            let fileNameLen = Int(readUInt16LE(data, at: cdCursor + 28))
            let extraLen = Int(readUInt16LE(data, at: cdCursor + 30))
            let commentLen = Int(readUInt16LE(data, at: cdCursor + 32))
            let externalAttrs = readUInt32LE(data, at: cdCursor + 38)
            let localHeaderOffset = Int(readUInt32LE(data, at: cdCursor + 42))

            let nameStart = cdCursor + 46
            let nameEnd = nameStart + fileNameLen
            let nextCDCursor = nameEnd + extraLen + commentLen
            guard nextCDCursor <= data.count,
                  let rawEntryName = String(data: data.subdata(in: nameStart..<nameEnd), encoding: .utf8) else {
                throw CoreMLError.extractionFailed(exitCode: 1)
            }
            cdCursor = nextCDCursor

            // Skip macOS resource fork metadata and empty names
            let trimmedName = rawEntryName.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if trimmedName.isEmpty || rawEntryName == "__MACOSX" || rawEntryName.hasPrefix("__MACOSX/") {
                continue
            }

            // Reject path traversal components and UNIX symlinks
            let pathComponents = rawEntryName.split(separator: "/").map(String.init)
            if pathComponents.contains("..") || pathComponents.contains(".") {
                throw CoreMLError.extractionFailed(exitCode: 1)
            }
            let unixMode = (externalAttrs >> 16) & 0xF000
            if unixMode == 0xA000 {
                continue
            }

            let entryURL = safeRoot.appendingPathComponent(trimmedName).standardizedFileURL
            guard entryURL.path.hasPrefix(safeRootPrefix) else {
                throw CoreMLError.extractionFailed(exitCode: 1)
            }

            let isDirectory = rawEntryName.hasSuffix("/") || unixMode == 0x4000
            if isDirectory {
                try FileManager.default.createDirectory(at: entryURL, withIntermediateDirectories: true)
                continue
            }

            // Parse Local File Header at localHeaderOffset to find exact payload offset
            guard localHeaderOffset >= 0,
                  localHeaderOffset + 30 <= data.count,
                  readUInt32LE(data, at: localHeaderOffset) == 0x04034b50 else {
                throw CoreMLError.extractionFailed(exitCode: 1)
            }

            let localNameLen = Int(readUInt16LE(data, at: localHeaderOffset + 26))
            let localExtraLen = Int(readUInt16LE(data, at: localHeaderOffset + 28))
            let payloadStart = localHeaderOffset + 30 + localNameLen + localExtraLen
            let payloadEnd = payloadStart + compressedSize
            guard payloadStart >= 0, payloadEnd <= data.count else {
                throw CoreMLError.extractionFailed(exitCode: 1)
            }

            let compressedSlice = data.subdata(in: payloadStart..<payloadEnd)
            let uncompressedData: Data
            switch compressionMethod {
            case 0: // Stored
                uncompressedData = compressedSlice
            case 8: // Deflate (raw RFC 1951)
                uncompressedData = try inflateRawDeflate(compressedSlice, expectedSize: uncompressedSize)
            default:
                throw CoreMLError.extractionFailed(exitCode: 1)
            }

            let computedCRC: UInt32 = uncompressedData.withUnsafeBytes { rawBuf in
                let initial = zlib.crc32(0, nil, 0)
                guard let ptr = rawBuf.bindMemory(to: Bytef.self).baseAddress, !rawBuf.isEmpty else {
                    return UInt32(initial)
                }
                return UInt32(zlib.crc32(initial, ptr, uInt(rawBuf.count)))
            }
            guard computedCRC == expectedCRC else {
                throw CoreMLError.extractionFailed(exitCode: 1)
            }

            try FileManager.default.createDirectory(at: entryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try uncompressedData.write(to: entryURL, options: .atomic)
        }
    }

    private static func inflateRawDeflate(_ compressed: Data, expectedSize: Int) throws -> Data {
        if compressed.isEmpty && expectedSize == 0 {
            return Data()
        }
        var stream = z_stream()
        let initStatus = inflateInit2_(
            &stream,
            -MAX_WBITS,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else {
            throw CoreMLError.extractionFailed(exitCode: initStatus)
        }
        defer { inflateEnd(&stream) }

        var output = Data()
        output.reserveCapacity(max(expectedSize, 4096))
        let chunkSize = max(min(max(expectedSize, 16_384), 1_048_576), 4096)
        var chunk = [UInt8](repeating: 0, count: chunkSize)

        let inflateResult: Int32 = compressed.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: Bytef.self).baseAddress else {
                return Z_DATA_ERROR
            }
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: baseAddress)
            stream.avail_in = uInt(rawBuffer.count)

            while true {
                let status: Int32 = chunk.withUnsafeMutableBufferPointer { outBuf in
                    stream.next_out = outBuf.baseAddress
                    stream.avail_out = uInt(outBuf.count)
                    return zlib.inflate(&stream, Z_NO_FLUSH)
                }
                let produced = chunkSize - Int(stream.avail_out)
                if produced > 0 {
                    output.append(chunk, count: produced)
                }
                if status == Z_STREAM_END {
                    return Z_STREAM_END
                }
                if status != Z_OK {
                    return status
                }
                if stream.avail_in == 0 && produced == 0 {
                    return Z_BUF_ERROR
                }
            }
        }

        guard inflateResult == Z_STREAM_END else {
            throw CoreMLError.extractionFailed(exitCode: inflateResult)
        }
        return output
    }

    private static func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    // MARK: - Helpers

    @MainActor
    private func updateProgress(_ progress: Double, message: String) {
        self.downloadProgress = progress
        self.statusMessage = message
    }

    private func setErrorMessage(_ message: String) async {
        await MainActor.run {
            self.errorMessage = message
            self.statusMessage = "Error"
        }
    }

    private func directorySize(at url: URL) -> Int64? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }

        if !isDir.boolValue {
            let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
            return attr?[.size] as? Int64
        }

        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: []) else {
            return nil
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(resourceValues?.fileSize ?? 0)
        }
        return total
    }
}

/// URLSession download task delegate streaming progress updates directly to disk without memory buffering.
private final class ModelDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progressHandler: @Sendable (Double) -> Void

    init(progressHandler: @escaping @Sendable (Double) -> Void) {
        self.progressHandler = progressHandler
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler(progress)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Handled by URLSession.download(for:delegate:) async return value
    }
}
