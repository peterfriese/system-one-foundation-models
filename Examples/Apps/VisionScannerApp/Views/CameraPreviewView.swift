import SwiftUI
import AVFoundation
import CoreGraphics
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Cross-Platform Camera Preview View

public struct CameraPreviewView: View {
    @Bindable public var cameraManager: CameraManager
    @Binding public var isFileImporterPresented: Bool
    @State private var selectedPhotoItem: PhotosPickerItem?

    public init(
        cameraManager: CameraManager,
        isFileImporterPresented: Binding<Bool>
    ) {
        self.cameraManager = cameraManager
        self._isFileImporterPresented = isFileImporterPresented
    }

    public var body: some View {
        ZStack {
            if let importedImage = cameraManager.importedImage {
                ImportedPhotoCanvasView(
                    image: importedImage,
                    imageName: cameraManager.importedImageName,
                    selectedPhotoItem: $selectedPhotoItem,
                    onChooseFile: { isFileImporterPresented = true },
                    onClearImportedPhoto: cameraManager.isCameraAvailable ? {
                        cameraManager.clearImportedPhoto()
                    } : nil
                )
            } else if cameraManager.isCameraAvailable {
                #if canImport(UIKit) && !os(macOS)
                CameraPreviewRepresentable(session: cameraManager.session)
                    .ignoresSafeArea()
                #elseif canImport(AppKit)
                CameraPreviewNSRepresentable(session: cameraManager.session)
                    .ignoresSafeArea()
                #else
                Color.black.ignoresSafeArea()
                #endif
            } else {
                CameraUnavailableView(
                    reason: cameraManager.cameraUnavailableReason
                        ?? "Connect a physical camera or import a photo to evaluate real System One multimodal decisions.",
                    selectedPhotoItem: $selectedPhotoItem,
                    onChooseFile: { isFileImporterPresented = true }
                )
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    cameraManager.importPhotoData(data, name: "Photos Library Image")
                }
            }
        }
    }
}

// MARK: - Imported Real Photo Canvas

private struct ImportedPhotoCanvasView: View {
    let image: CGImage
    let imageName: String?
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let onChooseFile: () -> Void
    let onClearImportedPhoto: (() -> Void)?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                Image(decorative: image, scale: 1.0, orientation: .up)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)

                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.fill")
                            .foregroundStyle(.cyan)
                        Text(imageName ?? "Imported Photo")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Label("Photos", systemImage: "photo.on.rectangle")
                                .font(.caption2.bold())
                        }
                        .buttonStyle(.glass)

                        Button(action: onChooseFile) {
                            Label("File…", systemImage: "folder")
                                .font(.caption2.bold())
                        }
                        .buttonStyle(.glass)

                        if let onClearImportedPhoto {
                            Button(action: onClearImportedPhoto) {
                                Label("Live Camera", systemImage: "video.fill")
                                    .font(.caption2.bold())
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.top, 56)

                    Spacer()
                }
            }
        }
    }
}

// MARK: - Camera Unavailable State (Principle 7: Real Photo Import, Zero Synthetic Feeds)

private struct CameraUnavailableView: View {
    let reason: String
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let onChooseFile: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.12),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 64, height: 64)
                    Circle()
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                        .frame(width: 64, height: 64)
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.cyan)
                }

                VStack(spacing: 6) {
                    Text("Camera Unavailable")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)

                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                }

                HStack(spacing: 12) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Import Photo…", systemImage: "photo.on.rectangle.angled")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)

                    Button(action: onChooseFile) {
                        Label("Choose File…", systemImage: "folder")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(24)
            .padding(.bottom, 180)
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
