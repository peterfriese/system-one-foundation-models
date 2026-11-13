import AudioToolbox
import UIKit

// MARK: - Audio & Haptic Feedback for Real-Time Scanning

public enum AudioFeedback {
    /// Plays a short, crisp scan beep when a barcode is detected by the camera.
    @MainActor
    public static func playBarcodeSound() {
        // System Sound 1057: Standard scanning click / confirmation tone
        AudioServicesPlaySystemSound(1057)
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.prepare()
        impact.impactOccurred()
    }

    /// Plays a distinct melodic chime when a nutrition label or ingredients table is locked by Vision OCR.
    @MainActor
    public static func playNutritionLabelSound() {
        // System Sound 1016: Musical chime indicating content recognized
        AudioServicesPlaySystemSound(1016)
        let notification = UINotificationFeedbackGenerator()
        notification.prepare()
        notification.notificationOccurred(.success)
    }
}
