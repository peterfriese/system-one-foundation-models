import SwiftUI

/// Main entry point for the cross-platform Clef Camera Scanner SwiftUI reference application.
@main
struct ClefCameraScannerApp: App {
    var body: some Scene {
        WindowGroup {
            ClefCameraScannerView()
                #if os(macOS)
                .frame(minWidth: 520, minHeight: 700)
                #endif
        }
    }
}
