import Foundation
import Observation
@preconcurrency import CoreML
import FactoryKit

/// Strongly-typed domain error for Core ML model management operations.
public enum CoreMLError: Error, LocalizedError, Sendable, Equatable, CustomNSError {
    case invalidURL(String)
    case insecureURL(String)
    case downloadFailed(statusCode: Int, message: String)
    case unsupportedFormat(String)
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
        case .extractionFailed(let exitCode): return Int(exitCode)
        case .modelNotFound: return 404
        case .modelNotFoundInArchive: return 2
        case .compilationFailed: return 500
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid download URL configured: \(url)"
        case .insecureURL(let message):
            return "Insecure download URL: \(message)"
        case .downloadFailed(let statusCode, let message):
            return "Download failed (HTTP \(statusCode)): \(message)"
        case .unsupportedFormat(let ext):
            let normalized = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return "Unsupported model format: .\(normalized). Please provide an .mlmodel, .mlpackage, .mlmodelc, .safetensors, or .zip archive."
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
            return "Please provide a valid HTTPS URL in Settings."
        case .downloadFailed(let statusCode, _):
            if statusCode == 401 {
                return "Check that your Hugging Face access token has read permissions for this model repository."
            }
            return "Check your network connection and verify the remote model server is reachable."
        case .unsupportedFormat:
            return "Import a valid Core ML package (.mlpackage), compiled model (.mlmodelc), safetensors weights (.safetensors), or a zip archive containing them."
        case .extractionFailed:
            return "Ensure the downloaded or imported zip archive is not corrupted."
        case .modelNotFound:
            return "Verify that the specified file path exists on disk and is accessible."
        case .modelNotFoundInArchive:
            return "Verify the zip archive contains a valid Core ML model bundle."
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

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let candidateURLs: [URL] = [
            appSupport.appendingPathComponent("dev.peterfriese.mailtriageapp").appendingPathComponent("Models").appendingPathComponent("LayaDecisionModel.mlmodelc"),
            appSupport.appendingPathComponent("dev.peterfriese.mailtriageapp").appendingPathComponent("Models").appendingPathComponent("model.safetensors"),
            appSupport.appendingPathComponent("MailTriage").appendingPathComponent("Models").appendingPathComponent("LayaDecisionModel.mlmodelc"),
            appSupport.appendingPathComponent("MailTriage").appendingPathComponent("Models").appendingPathComponent("model.safetensors"),
            appSupport.appendingPathComponent(Bundle.main.bundleIdentifier ?? "dev.peterfriese.mailtriageapp").appendingPathComponent("Models").appendingPathComponent("LayaDecisionModel.mlmodelc"),
            appSupport.appendingPathComponent(Bundle.main.bundleIdentifier ?? "dev.peterfriese.mailtriageapp").appendingPathComponent("Models").appendingPathComponent("model.safetensors"),
            appSupport.appendingPathComponent("ai.typesafe.MailTriage").appendingPathComponent("Models").appendingPathComponent("LayaDecisionModel.mlmodelc"),
            appSupport.appendingPathComponent("ai.typesafe.MailTriage").appendingPathComponent("Models").appendingPathComponent("model.safetensors")
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

    /// Resolves a Hugging Face repository URL to its primary weights file URL.
    public static func resolveDownloadURL(_ inputURL: URL) -> URL {
        if inputURL.absoluteString.contains("/resolve/main/model.safetensors") {
            return inputURL
        }
        var str = inputURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if str.contains("huggingface.co") && !str.contains("/resolve/") {
            if let treeRange = str.range(of: "/tree/main") {
                str.removeSubrange(treeRange)
                str = str.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            str += "/resolve/main/model.safetensors"
            return URL(string: str) ?? inputURL
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
        } else if let parsed = URL(string: configStore.coreMLDownloadURL) {
            rawDownloadURL = parsed
        } else {
            let error = CoreMLError.invalidURL(configStore.coreMLDownloadURL)
            await setErrorMessage(error.localizedDescription)
            throw error
        }

        let downloadURL = Self.resolveDownloadURL(rawDownloadURL)

        // Validate scheme and transport security (SEC-3 / SEC-4)
        guard let scheme = downloadURL.scheme?.lowercased(),
              scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(downloadURL.host?.lowercased() ?? "")) else {
            let error = CoreMLError.insecureURL("HTTPS is required for remote model downloads.")
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
        if ext == "safetensors" || ext == "bin" || ext == "mlmodelc" {
            precompiledModel = workingFile
        } else if ext == "zip" {
            await MainActor.run {
                self.statusMessage = "Extracting model archive..."
            }

            let extractedDir = tempDir.appendingPathComponent("extracted")
            try FileManager.default.createDirectory(at: extractedDir, withIntermediateDirectories: true)

            #if os(macOS)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-xk", workingFile.path, extractedDir.path]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let error = CoreMLError.extractionFailed(exitCode: process.terminationStatus)
                await setErrorMessage(error.localizedDescription)
                throw error
            }
            #endif

            // Locate .mlmodelc, .mlpackage, or .mlmodel within extracted folder
            let enumerator = FileManager.default.enumerator(at: extractedDir, includingPropertiesForKeys: [.isDirectoryKey])
            while let fileURL = enumerator?.nextObject() as? URL {
                let fileExt = fileURL.pathExtension.lowercased()
                if fileExt == "mlmodelc" {
                    precompiledModel = fileURL
                    break
                } else if fileExt == "mlpackage" || fileExt == "mlmodel" {
                    modelToCompile = fileURL
                    break
                }
            }

            if precompiledModel == nil && modelToCompile == workingFile {
                let error = CoreMLError.modelNotFoundInArchive
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

            if ext == "safetensors" || ext == "bin" || ext == "mlmodelc" {
                finalCompiledURL = sourceURL
            } else if ext == "zip" {
                await MainActor.run {
                    self.statusMessage = "Extracting model archive..."
                }
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("import_\(UUID().uuidString)")
                tempExtractionDir = tempDir
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

                #if os(macOS)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                process.arguments = ["-xk", sourceURL.path, tempDir.path]
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    let error = CoreMLError.extractionFailed(exitCode: process.terminationStatus)
                    await setErrorMessage(error.localizedDescription)
                    throw error
                }
                #endif

                var foundPrecompiled: URL? = nil
                var foundToCompile: URL? = nil

                let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: [.isDirectoryKey])
                while let fileURL = enumerator?.nextObject() as? URL {
                    let fileExt = fileURL.pathExtension.lowercased()
                    if fileExt == "mlmodelc" {
                        foundPrecompiled = fileURL
                        break
                    } else if fileExt == "mlpackage" || fileExt == "mlmodel" {
                        foundToCompile = fileURL
                        break
                    }
                }

                if let foundPrecompiled {
                    finalCompiledURL = foundPrecompiled
                } else if let foundToCompile {
                    await MainActor.run {
                        self.statusMessage = "Compiling for Apple Neural Engine..."
                    }
                    finalCompiledURL = try await MLModel.compileModel(at: foundToCompile)
                } else {
                    let error = CoreMLError.modelNotFoundInArchive
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
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.statusMessage = "Model removed"
                self.downloadProgress = 0.0
                self.errorMessage = nil
            }
        } else {
            DispatchQueue.main.sync {
                self.statusMessage = "Model removed"
                self.downloadProgress = 0.0
                self.errorMessage = nil
            }
        }
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
