@preconcurrency import AVFoundation
import CoreImage
import CoreGraphics
import ImageIO
import SwiftUI
import Observation

// MARK: - Lock-Protected Latest Pixel Buffer Store

private final class LatestPixelBufferStore: @unchecked Sendable {
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

// MARK: - Cross-Platform Camera Manager (AVFoundation + Swift 6 Concurrency)

/// Manages hardware camera capture session, device discovery, on-demand frame conversion,
/// and real photo import when running without physical camera hardware.
@Observable
@MainActor
public final class CameraManager: NSObject {
    // MARK: - Observable UI State

    public private(set) var isCameraAvailable: Bool = false
    public private(set) var isSessionRunning: Bool = false
    public private(set) var importedImage: CGImage?
    public private(set) var importedImageName: String?
    public private(set) var cameraUnavailableReason: String?
    public private(set) var errorMessage: String?
    public var isTorchOn: Bool = false

    public var hasInspectableInput: Bool {
        isCameraAvailable || importedImage != nil
    }

    // MARK: - Internal Hardware Infrastructure

    @ObservationIgnored nonisolated(unsafe) public let session = AVCaptureSession()
    @ObservationIgnored nonisolated(unsafe) private var videoDevice: AVCaptureDevice?
    @ObservationIgnored nonisolated(unsafe) private var videoOutput: AVCaptureVideoDataOutput?

    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "com.typesafe.clef.camera.session")
    @ObservationIgnored private let sampleQueue = DispatchQueue(label: "com.typesafe.clef.camera.sample", qos: .userInitiated)
    @ObservationIgnored private let ciContext = CIContext()
    @ObservationIgnored private let latestPixelBuffer = LatestPixelBufferStore()

    // MARK: - Initialization & Lifecycle

    public override init() {
        super.init()
    }

    public func configure() async {
        let authorized = await checkAuthorization()
        guard authorized else {
            markCameraUnavailable(
                reason: Self.defaultUnavailableMessage()
            )
            return
        }

        await setupHardwareSession()
    }

    public func start() {
        guard isCameraAvailable, !isSessionRunning else { return }

        sessionQueue.async { [weak self, session] in
            guard let self = self, !session.isRunning else { return }
            session.startRunning()
            let running = session.isRunning
            Task { @MainActor in
                self.isSessionRunning = running
            }
        }
    }

    public func stop() {
        guard isSessionRunning else { return }

        latestPixelBuffer.update(nil)
        sessionQueue.async { [weak self, session] in
            guard let self = self, session.isRunning else { return }
            session.stopRunning()
            let running = session.isRunning
            Task { @MainActor in
                self.isSessionRunning = running
            }
        }
    }

    // MARK: - On-Demand Frame Capture & Real Photo Import

    /// Converts the latest captured `CVPixelBuffer` to a downsampled `CGImage` on demand,
    /// or returns the user's imported photo when running without a physical camera.
    public func captureFrame() async -> CGImage? {
        if isCameraAvailable {
            let context = ciContext
            let bufferStore = latestPixelBuffer
            let converted: CGImage? = await withCheckedContinuation { continuation in
                sampleQueue.async {
                    guard let pixelBuffer = bufferStore.snapshot() else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                    let cgImage = context.createCGImage(ciImage, from: ciImage.extent)
                    continuation.resume(returning: cgImage.map { Self.downsample(image: $0, maxDimension: 1024) })
                }
            }
            if let converted {
                errorMessage = nil
                return converted
            }
        }

        if let importedImage {
            errorMessage = nil
            return Self.downsample(image: importedImage, maxDimension: 1024)
        }

        errorMessage = isCameraAvailable
            ? "Waiting for first video frame from camera. Try again in a moment."
            : "No camera or imported photo available. Import a real photo to inspect."
        return nil
    }

    /// Loads a real image from raw image data (e.g. from `PhotosPicker`).
    @discardableResult
    public func importPhotoData(_ data: Data, name: String? = nil) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            errorMessage = "Could not decode the selected image. Choose a PNG, JPEG, HEIC, or WebP file."
            return false
        }

        importedImage = Self.downsample(image: cgImage, maxDimension: 1024)
        importedImageName = name ?? "Imported Photo"
        errorMessage = nil
        return true
    }

    /// Loads a real image file from disk (e.g. from SwiftUI `.fileImporter`).
    @discardableResult
    public func importPhotoFile(at url: URL) -> Bool {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "Unable to read image file at \(url.lastPathComponent)."
            return false
        }

        return importPhotoData(data, name: url.lastPathComponent)
    }

    public func clearImportedPhoto() {
        importedImage = nil
        importedImageName = nil
    }

    /// Downsamples a `CGImage` preserving aspect ratio so its maximum dimension does not exceed `maxDimension`.
    public nonisolated static func downsample(image: CGImage, maxDimension: Int = 1024) -> CGImage {
        let origWidth = image.width
        let origHeight = image.height
        let maxDim = max(origWidth, origHeight)

        guard maxDim > maxDimension else {
            return image
        }

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

    public func toggleTorch() {
        #if os(iOS)
        guard let device = videoDevice, device.hasTorch, device.isTorchAvailable else { return }
        let targetState = !isTorchOn
        sessionQueue.async { [weak self] in
            do {
                try device.lockForConfiguration()
                device.torchMode = targetState ? .on : .off
                device.unlockForConfiguration()
                Task { @MainActor in
                    self?.isTorchOn = targetState
                }
            } catch {
                Task { @MainActor in
                    self?.errorMessage = "Failed to toggle torch: \(error.localizedDescription)"
                }
            }
        }
        #endif
    }

    // MARK: - Permissions & Configuration

    private func checkAuthorization() async -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
        #endif
    }

    private func setupHardwareSession() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }

                // 1. Discover Video Device
                guard let device = Self.discoverVideoDevice() else {
                    Task { @MainActor in
                        self.markCameraUnavailable(reason: "No physical video capture device detected. Import a photo to inspect real images.")
                        continuation.resume()
                    }
                    return
                }

                self.videoDevice = device

                // 2. Configure Session
                self.session.beginConfiguration()
                defer { self.session.commitConfiguration() }

                self.session.sessionPreset = .high

                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    guard self.session.canAddInput(input) else {
                        Task { @MainActor in
                            self.markCameraUnavailable(reason: "Unable to attach video capture input. Import a photo to inspect real images.")
                            continuation.resume()
                        }
                        return
                    }
                    self.session.addInput(input)

                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                    ]

                    guard self.session.canAddOutput(output) else {
                        Task { @MainActor in
                            self.markCameraUnavailable(reason: "Unable to configure camera video output. Import a photo to inspect real images.")
                            continuation.resume()
                        }
                        return
                    }

                    self.session.addOutput(output)
                    output.setSampleBufferDelegate(self, queue: self.sampleQueue)
                    self.videoOutput = output

                    Task { @MainActor in
                        self.isCameraAvailable = true
                        self.cameraUnavailableReason = nil
                        self.errorMessage = nil
                        continuation.resume()
                    }
                } catch {
                    Task { @MainActor in
                        self.markCameraUnavailable(reason: "Camera setup failed (\(error.localizedDescription)). Import a photo to inspect real images.")
                        continuation.resume()
                    }
                }
            }
        }
    }

    private nonisolated static func discoverVideoDevice() -> AVCaptureDevice? {
        #if os(macOS)
        return AVCaptureDevice.default(for: .video)
        #else
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
        #endif
    }

    private nonisolated static func defaultUnavailableMessage() -> String {
        #if targetEnvironment(simulator)
        return "iOS Simulator does not provide a hardware camera feed. Import a real photo to evaluate System One multimodal decisions."
        #else
        return "Camera permission was not granted or no camera is connected. Import a real photo to evaluate System One multimodal decisions."
        #endif
    }

    private func markCameraUnavailable(reason: String) {
        isCameraAvailable = false
        isSessionRunning = false
        cameraUnavailableReason = reason
        latestPixelBuffer.update(nil)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latestPixelBuffer.update(pixelBuffer)
    }
}
