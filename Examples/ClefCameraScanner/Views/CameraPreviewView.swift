import SwiftUI
import AVFoundation
import CoreGraphics

// MARK: - Cross-Platform Camera Preview View

public struct CameraPreviewView: View {
    @Bindable public var cameraManager: CameraManager

    public init(cameraManager: CameraManager) {
        self.cameraManager = cameraManager
    }

    public var body: some View {
        ZStack {
            if cameraManager.isSimulatedFeed {
                // Simulated Camera Feed Rendering
                SimulatedFeedView(cameraManager: cameraManager)
            } else {
                #if canImport(UIKit) && !os(macOS)
                CameraPreviewRepresentable(session: cameraManager.session)
                    .ignoresSafeArea()
                #elseif canImport(AppKit)
                CameraPreviewNSRepresentable(session: cameraManager.session)
                    .ignoresSafeArea()
                #else
                Color.black.ignoresSafeArea()
                #endif
            }
        }
    }
}

// MARK: - Simulation Feed View

private struct SimulatedFeedView: View {
    @Bindable var cameraManager: CameraManager
    @State private var scanLaserY: CGFloat = 0.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if let currentFrame = cameraManager.currentFrame {
                    #if canImport(UIKit) && !os(macOS)
                    Image(uiImage: UIImage(cgImage: currentFrame))
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                    #elseif canImport(AppKit)
                    Image(nsImage: NSImage(cgImage: currentFrame, size: NSSize(width: currentFrame.width, height: currentFrame.height)))
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                    #endif
                } else {
                    ProgressView("Initializing Camera Feed...")
                        .tint(.white)
                        .foregroundStyle(.white)
                }

                // Laser scan line animation
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .cyan.opacity(0.8), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 3)
                    .position(x: geometry.size.width / 2, y: scanLaserY * geometry.size.height)
                    .onAppear {
                        withAnimation(
                            .easeInOut(duration: 2.2)
                            .repeatForever(autoreverses: true)
                        ) {
                            scanLaserY = 1.0
                        }
                    }

                // Simulation overlay notice
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "video.slash.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.amber)
                        Text("SIMULATED CAMERA FEED")
                            .font(.system(.caption, design: .monospaced, weight: .bold))
                            .foregroundStyle(.white)

                        Button {
                            cameraManager.nextSimulationItem()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Switch Item")
                            }
                            .font(.caption2.bold())
                        }
                        .buttonStyle(.glass)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.top, 16)

                    Spacer()
                }
            }
        }
    }
}

// MARK: - iOS Representable

#if canImport(UIKit) && !os(macOS)
import UIKit

public struct CameraPreviewRepresentable: UIViewRepresentable {
    public let session: AVCaptureSession

    public init(session: AVCaptureSession) {
        self.session = session
    }

    public func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    public func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
    }
}

public final class CameraPreviewUIView: UIView {
    public override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    public var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
#endif

// MARK: - macOS Representable

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit

public struct CameraPreviewNSRepresentable: NSViewRepresentable {
    public let session: AVCaptureSession

    public init(session: AVCaptureSession) {
        self.session = session
    }

    public func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.wantsLayer = true
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer = previewLayer
        return view
    }

    public func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        if let previewLayer = nsView.layer as? AVCaptureVideoPreviewLayer,
           previewLayer.session !== session {
            previewLayer.session = session
        }
    }
}

public final class CameraPreviewNSView: NSView {
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    public override func layout() {
        super.layout()
        layer?.frame = bounds
    }
}
#endif
