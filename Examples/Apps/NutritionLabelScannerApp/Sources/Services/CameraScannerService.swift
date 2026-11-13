import AVFoundation
import CoreImage
import CoreGraphics
import Vision
import SwiftUI
import Observation

// MARK: - Thread-Safe Latest Pixel Buffer Store

private final class LatestScannerPixelBufferStore: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: CVPixelBuffer?

    func update(_ newBuffer: CVPixelBuffer?) {
        lock.lock()
        buffer = newBuffer
        lock.unlock()
    }

    func snapshot() -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}

// MARK: - Camera Scanner Service (AVFoundation + Vision OCR + Barcode Engine)

@MainActor
@Observable
public final class CameraScannerService: NSObject {
    public private(set) var isCameraAvailable: Bool = false
    public private(set) var isSessionRunning: Bool = false
    public private(set) var recognizedBarcode: String?
    public private(set) var recognizedText: String?
    public private(set) var lastCapturedImage: CGImage?
    public var isTorchOn: Bool = false

    // AVFoundation capture graph primitives: configuration and lifecycle mutations are serialized on `sessionQueue`
    // (`com.typesafe.camera.sessionQueue`); `captureSession` is only attached read-only to `AVCaptureVideoPreviewLayer`.
    @ObservationIgnored nonisolated(unsafe) public let captureSession = AVCaptureSession()
    // Synchronized exclusively on serial `sessionQueue` (`setupCaptureSession` and `toggleTorch`).
    @ObservationIgnored nonisolated(unsafe) private var videoDevice: AVCaptureDevice?
    // Configured exclusively on serial `sessionQueue` during `setupCaptureSession()`.
    @ObservationIgnored nonisolated(unsafe) private let videoOutput = AVCaptureVideoDataOutput()
    @ObservationIgnored nonisolated(unsafe) private let metadataOutput = AVCaptureMetadataOutput()

    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "com.typesafe.camera.sessionQueue")
    @ObservationIgnored private let visionQueue = DispatchQueue(label: "com.typesafe.camera.visionQueue", qos: .userInitiated)
    @ObservationIgnored private let ciContext = CIContext()
    @ObservationIgnored private let latestPixelBuffer = LatestScannerPixelBufferStore()

    // Synchronized exclusively on serial `visionQueue` (`com.typesafe.camera.visionQueue`) inside `captureOutput(_:didOutput:from:)`.
    @ObservationIgnored nonisolated(unsafe) private var lastOCRTimestamp = Date()
    @ObservationIgnored nonisolated private let ocrIntervalSeconds: TimeInterval = 0.8

    @ObservationIgnored private var lastRecognizedLabelHash: Int = 0

    @ObservationIgnored public var onBarcodeDetected: ((String) -> Void)?
    @ObservationIgnored public var onLabelTextDetected: ((String, CGImage?) -> Void)?
    @ObservationIgnored public var onPhotoImportedWithoutOCR: ((CGImage) -> Void)?

    public override init() {
        super.init()
        checkPermissionsAndConfigure()
    }

    public func checkPermissionsAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    Task { @MainActor in
                        self?.setupCaptureSession()
                    }
                }
            }
        default:
            isCameraAvailable = false
        }
    }

    private func setupCaptureSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .high

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                DispatchQueue.main.async {
                    self.isCameraAvailable = false
                }
                self.captureSession.commitConfiguration()
                return
            }

            self.videoDevice = device

            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.captureSession.canAddInput(input) {
                    self.captureSession.addInput(input)
                }

                if self.captureSession.canAddOutput(self.metadataOutput) {
                    self.captureSession.addOutput(self.metadataOutput)
                    self.metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                    self.metadataOutput.metadataObjectTypes = [
                        .ean13, .ean8, .upce, .qr, .code128, .code39
                    ]
                }

                if self.captureSession.canAddOutput(self.videoOutput) {
                    self.captureSession.addOutput(self.videoOutput)
                    self.videoOutput.alwaysDiscardsLateVideoFrames = true
                    self.videoOutput.setSampleBufferDelegate(self, queue: self.visionQueue)
                }

                self.captureSession.commitConfiguration()
                self.captureSession.startRunning()

                DispatchQueue.main.async {
                    self.isCameraAvailable = true
                    self.isSessionRunning = self.captureSession.isRunning
                }
            } catch {
                DispatchQueue.main.async {
                    self.isCameraAvailable = false
                }
                self.captureSession.commitConfiguration()
            }
        }
    }

    public func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = self.captureSession.isRunning
            }
        }
    }

    public func stopSession() {
        latestPixelBuffer.update(nil)
        sessionQueue.async { [weak self] in
            guard let self = self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
        }
    }

    public func toggleTorch() {
        let targetState = !isTorchOn
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.videoDevice, device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = targetState ? .on : .off
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.isTorchOn = targetState
                }
            } catch {
                print("Failed to toggle torch: \(error)")
            }
        }
    }

    /// Snapshots the latest live camera frame on demand (or returns the last imported/captured image)
    /// for vision-capable System One providers.
    public func snapshotCurrentFrame() async -> CGImage? {
        if isCameraAvailable {
            let context = ciContext
            let bufferStore = latestPixelBuffer
            let converted: CGImage? = await withCheckedContinuation { continuation in
                visionQueue.async {
                    guard let pixelBuffer = bufferStore.snapshot() else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
                    let cgImage = context.createCGImage(ciImage, from: ciImage.extent)
                    continuation.resume(returning: cgImage.map { Self.downsample(image: $0, maxDimension: 1024) })
                }
            }
            if let converted {
                lastCapturedImage = converted
                return converted
            }
        }
        return lastCapturedImage
    }

    /// Processes imported photos with rotation tolerance and multilingual OCR, preserving a downsampled
    /// `CGImage` for multimodal vision providers (`Clef`, `OpenAI`, `Gemini`, vision-enabled `ReverseProxy`).
    public func processStillImage(_ image: UIImage) {
        guard let rawCGImage = image.cgImage else { return }
        let downsampled = Self.downsample(image: rawCGImage, maxDimension: 1024)
        self.lastCapturedImage = downsampled

        visionQueue.async { [weak self] in
            guard let self = self else { return }

            let primaryOrientation = CGImagePropertyOrientation(image.imageOrientation)
            let orientations: [CGImagePropertyOrientation] = [
                primaryOrientation,
                .right,
                .left,
                .down,
                .up
            ]

            for orientation in orientations {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["de-DE", "en-US", "fr-FR", "es-ES", "it-IT"]
                request.automaticallyDetectsLanguage = true

                let handler = VNImageRequestHandler(cgImage: rawCGImage, orientation: orientation, options: [:])
                try? handler.perform([request])

                if let observations = request.results {
                    let spatialLines = NutritionLabelParser.reconstructSpatialLines(from: observations)
                    let text = spatialLines.isEmpty
                        ? observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                        : spatialLines.joined(separator: "\n")

                    if NutritionLabelParser.isNutritionLabelOrIngredients(text) {
                        DispatchQueue.main.async {
                            AudioFeedback.playNutritionLabelSound()
                            self.recognizedText = text
                            self.onLabelTextDetected?(text, downsampled)
                        }
                        return
                    }
                }
            }

            DispatchQueue.main.async {
                self.onPhotoImportedWithoutOCR?(downsampled)
            }
        }
    }

    nonisolated static func downsample(image: CGImage, maxDimension: Int = 1024) -> CGImage {
        let origWidth = image.width
        let origHeight = image.height
        let maxDim = max(origWidth, origHeight)
        guard maxDim > maxDimension else { return image }

        let scale = Double(maxDimension) / Double(maxDim)
        let targetWidth = max(1, Int((Double(origWidth) * scale).rounded()))
        let targetHeight = max(1, Int((Double(origHeight) * scale).rounded()))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return image
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage() ?? image
    }
}

// MARK: - AVCaptureMetadataOutputObjectsDelegate (Barcode Detection + Sound 1)

extension CameraScannerService: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated public func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        for object in metadataObjects {
            guard let readable = object as? AVMetadataMachineReadableCodeObject,
                  let code = readable.stringValue else { continue }

            Task { @MainActor in
                if self.recognizedBarcode != code {
                    self.recognizedBarcode = code
                    AudioFeedback.playBarcodeSound()
                    self.onBarcodeDetected?(code)
                }
            }
            break
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate (Live Multilingual Vision OCR + Sound 2)

extension CameraScannerService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latestPixelBuffer.update(pixelBuffer)

        let now = Date()
        guard now.timeIntervalSince(lastOCRTimestamp) >= ocrIntervalSeconds else { return }
        lastOCRTimestamp = now

        let context = ciContext
        let bufferStore = latestPixelBuffer

        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard error == nil, let observations = request.results as? [VNRecognizedTextObservation] else { return }
            let spatialLines = NutritionLabelParser.reconstructSpatialLines(from: observations)
            let fullText = spatialLines.isEmpty
                ? observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                : spatialLines.joined(separator: "\n")

            if NutritionLabelParser.isNutritionLabelOrIngredients(fullText) {
                let textHash = fullText.hashValue
                let capturedFrame: CGImage? = {
                    guard let snap = bufferStore.snapshot() else { return nil }
                    let ciImage = CIImage(cvPixelBuffer: snap).oriented(.right)
                    return context.createCGImage(ciImage, from: ciImage.extent)
                        .map { Self.downsample(image: $0, maxDimension: 1024) }
                }()

                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if self.lastRecognizedLabelHash != textHash {
                        self.lastRecognizedLabelHash = textHash
                        if let capturedFrame {
                            self.lastCapturedImage = capturedFrame
                        }
                        AudioFeedback.playNutritionLabelSound()
                        self.recognizedText = fullText
                        self.onLabelTextDetected?(fullText, capturedFrame)
                    }
                }
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["de-DE", "en-US", "fr-FR", "es-ES", "it-IT"]
        request.automaticallyDetectsLanguage = true

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        try? handler.perform([request])
    }
}

// MARK: - Orientation Helper

private extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
