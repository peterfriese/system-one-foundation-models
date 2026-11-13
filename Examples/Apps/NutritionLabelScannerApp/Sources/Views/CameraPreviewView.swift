import SwiftUI
import AVFoundation

// MARK: - Native AVCaptureVideoPreviewLayer SwiftUI Container

public struct CameraPreviewView: UIViewRepresentable {
    public let session: AVCaptureSession
    public let isCameraAvailable: Bool

    public init(session: AVCaptureSession, isCameraAvailable: Bool) {
        self.session = session
        self.isCameraAvailable = isCameraAvailable
    }

    public func makeUIView(context: Context) -> VideoPreviewUIView {
        let view = VideoPreviewUIView()
        view.backgroundColor = .black
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    public func updateUIView(_ uiView: VideoPreviewUIView, context: Context) {
        if uiView.videoPreviewLayer.session != session {
            uiView.videoPreviewLayer.session = session
        }
    }
}

public class VideoPreviewUIView: UIView {
    public override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    public var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
