import SwiftUI

/// Main entry point for the cross-platform System One Vision Scanner SwiftUI reference application.
@main
struct VisionScannerApp: App {
    var body: some Scene {
        WindowGroup {
            VisionScannerView()
                #if os(macOS)
                .frame(minWidth: 540, minHeight: 720)
                #endif
        }
    }
}
