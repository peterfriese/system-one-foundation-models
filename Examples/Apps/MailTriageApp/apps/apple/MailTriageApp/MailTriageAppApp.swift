import SwiftUI
import AppCore
import AppUI

@main
struct MailTriageAppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .frame(minWidth: 940, minHeight: 600)
                #endif
        }
        #if os(macOS)
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowResizability(.contentMinSize)
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
