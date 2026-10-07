@preconcurrency import AVFoundation
import CoreImage
import CoreGraphics
import SwiftUI
import Observation

// MARK: - Cross-Platform Camera Manager (AVFoundation + Swift 6 Concurrency)

/// Manages camera capture session, device discovery, live frame streaming, and simulation fallback.
@Observable
@MainActor
public final class CameraManager: NSObject {
    // MARK: - Observable UI State

    public private(set) var isCameraAvailable: Bool = false
    public private(set) var isSessionRunning: Bool = false
    public private(set) var isSimulatedFeed: Bool = false
    public private(set) var currentFrame: CGImage?
    public private(set) var errorMessage: String?
    public var isTorchOn: Bool = false
    public private(set) var simulationItemIndex: Int = 0

    // MARK: - Internal Hardware Infrastructure

    @ObservationIgnored nonisolated(unsafe) public let session = AVCaptureSession()
    @ObservationIgnored nonisolated(unsafe) private var videoDevice: AVCaptureDevice?
    @ObservationIgnored nonisolated(unsafe) private var videoOutput: AVCaptureVideoDataOutput?

    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "com.typesafe.clef.camera.session")
    @ObservationIgnored private let sampleQueue = DispatchQueue(label: "com.typesafe.clef.camera.sample", qos: .userInitiated)
    @ObservationIgnored private let ciContext = CIContext()

    @ObservationIgnored private var simulationTask: Task<Void, Never>?

    // MARK: - Initialization & Lifecycle

    public override init() {
        super.init()
    }

    public func configure() async {
        let authorized = await checkAuthorization()
        guard authorized else {
            activateSimulationMode(reason: "Camera access not granted or denied. Running simulation feed.")
            return
        }

        await setupHardwareSession()
    }

    public func start() {
        guard !isSessionRunning else { return }

        if isSimulatedFeed {
            isSessionRunning = true
            startSimulationStream()
            return
        }

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

        if isSimulatedFeed {
            isSessionRunning = false
            simulationTask?.cancel()
            simulationTask = nil
            return
        }

        sessionQueue.async { [weak self, session] in
            guard let self = self, session.isRunning else { return }
            session.stopRunning()
            let running = session.isRunning
            Task { @MainActor in
                self.isSessionRunning = running
            }
        }
    }

    // MARK: - Frame Capture

    /// Captures the most recent live frame or generates a fresh synthetic inspection frame,
    /// downsampling so its maximum dimension does not exceed 1024.
    public func captureFrame() async -> CGImage? {
        guard let existing = currentFrame else {
            errorMessage = "No camera frame available. Please ensure camera permissions are granted and video capture hardware is active."
            return nil
        }

        let downsampled = Self.downsample(image: existing, maxDimension: 1024)
        currentFrame = downsampled
        return downsampled
    }

    /// Downsamples a `CGImage` preserving aspect ratio so its maximum dimension does not exceed `maxDimension`.
    public static func downsample(image: CGImage, maxDimension: Int = 1024) -> CGImage {
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

    /// Cycles through candidate synthetic items in simulation mode.
    public func nextSimulationItem() {
        simulationItemIndex = (simulationItemIndex + 1) % 4
        currentFrame = generateSimulationFrame(forIndex: simulationItemIndex)
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
                let device = Self.discoverVideoDevice()
                guard let device = device else {
                    Task { @MainActor in
                        self.activateSimulationMode(reason: "No physical video capture device found.")
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
                    if self.session.canAddInput(input) {
                        self.session.addInput(input)
                    } else {
                        Task { @MainActor in
                            self.activateSimulationMode(reason: "Failed to attach camera input.")
                            continuation.resume()
                        }
                        return
                    }

                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                    ]

                    guard self.session.canAddOutput(output) else {
                        Task { @MainActor in
                            self.errorMessage = "Unable to configure camera video output."
                            self.isCameraAvailable = false
                            continuation.resume()
                        }
                        return
                    }

                    self.session.addOutput(output)
                    output.setSampleBufferDelegate(self, queue: self.sampleQueue)
                    self.videoOutput = output

                    Task { @MainActor in
                        self.isCameraAvailable = true
                        self.isSimulatedFeed = false
                        self.errorMessage = nil
                        continuation.resume()
                    }
                } catch {
                    Task { @MainActor in
                        self.activateSimulationMode(reason: "Camera setup error: \(error.localizedDescription)")
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

    private func activateSimulationMode(reason: String) {
        isCameraAvailable = false
        isSimulatedFeed = true
        errorMessage = reason
        currentFrame = generateSimulationFrame(forIndex: simulationItemIndex)
    }

    // MARK: - Simulation Frame Feed

    private func startSimulationStream() {
        simulationTask?.cancel()
        simulationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard !Task.isCancelled, let self = self else { break }
                self.currentFrame = self.generateSimulationFrame(forIndex: self.simulationItemIndex)
            }
        }
    }

    public func generateSimulationFrame(forIndex index: Int) -> CGImage {
        let width = 640
        let height = 480
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            fatalError("Failed to allocate CGContext for simulation frame")
        }

        // Fill background
        context.setFillColor(CGColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Draw camera grid overlay lines
        context.setStrokeColor(CGColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 0.4))
        context.setLineWidth(1.0)
        context.strokeLineSegments(between: [
            CGPoint(x: width / 3, y: 0), CGPoint(x: width / 3, y: height),
            CGPoint(x: (width * 2) / 3, y: 0), CGPoint(x: (width * 2) / 3, y: height),
            CGPoint(x: 0, y: height / 3), CGPoint(x: width, y: height / 3),
            CGPoint(x: 0, y: (height * 2) / 3), CGPoint(x: width, y: (height * 2) / 3)
        ])

        // Draw simulated subject based on item index
        switch index % 4 {
        case 0:
            // Snack Bar
            drawSnackBar(in: context, width: width, height: height)
        case 1:
            // Beverage Can
            drawBeverageCan(in: context, width: width, height: height)
        case 2:
            // Electronics Gadget
            drawElectronicsGadget(in: context, width: width, height: height)
        default:
            // Document / Invoice
            drawDocument(in: context, width: width, height: height)
        }

        return context.makeImage()!
    }

    private func drawSnackBar(in context: CGContext, width: Int, height: Int) {
        let rect = CGRect(x: 180, y: 170, width: 280, height: 140)
        context.setFillColor(CGColor(red: 0.85, green: 0.45, blue: 0.15, alpha: 1.0))
        context.fill(rect)
        context.setStrokeColor(CGColor(red: 0.95, green: 0.80, blue: 0.30, alpha: 1.0))
        context.setLineWidth(3.0)
        context.stroke(rect)

        // Wrapper text / design
        context.setFillColor(CGColor(red: 0.2, green: 0.1, blue: 0.05, alpha: 1.0))
        context.fill(CGRect(x: 210, y: 220, width: 220, height: 40))
    }

    private func drawBeverageCan(in context: CGContext, width: Int, height: Int) {
        let rect = CGRect(x: 240, y: 120, width: 160, height: 260)
        context.setFillColor(CGColor(red: 0.80, green: 0.12, blue: 0.18, alpha: 1.0))
        context.fill(rect)
        context.setStrokeColor(CGColor(red: 0.90, green: 0.90, blue: 0.95, alpha: 1.0))
        context.setLineWidth(4.0)
        context.stroke(rect)

        // Can logo stripe
        context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.9))
        context.fill(CGRect(x: 240, y: 220, width: 160, height: 45))
    }

    private func drawElectronicsGadget(in context: CGContext, width: Int, height: Int) {
        let rect = CGRect(x: 180, y: 140, width: 280, height: 200)
        context.setFillColor(CGColor(red: 0.18, green: 0.22, blue: 0.28, alpha: 1.0))
        context.fill(rect)
        context.setStrokeColor(CGColor(red: 0.35, green: 0.70, blue: 0.90, alpha: 1.0))
        context.setLineWidth(3.0)
        context.stroke(rect)

        // Screen area
        context.setFillColor(CGColor(red: 0.06, green: 0.45, blue: 0.85, alpha: 0.95))
        context.fill(CGRect(x: 200, y: 160, width: 240, height: 130))
    }

    private func drawDocument(in context: CGContext, width: Int, height: Int) {
        let rect = CGRect(x: 200, y: 100, width: 240, height: 300)
        context.setFillColor(CGColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0))
        context.fill(rect)
        context.setStrokeColor(CGColor(red: 0.60, green: 0.60, blue: 0.65, alpha: 1.0))
        context.setLineWidth(2.0)
        context.stroke(rect)

        // Text lines
        context.setFillColor(CGColor(red: 0.25, green: 0.25, blue: 0.30, alpha: 0.8))
        for i in 0..<8 {
            let lineY = 140 + (i * 24)
            context.fill(CGRect(x: 220, y: lineY, width: 200, height: 10))
        }
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
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        Task { @MainActor in
            self.currentFrame = cgImage
        }
    }
}
