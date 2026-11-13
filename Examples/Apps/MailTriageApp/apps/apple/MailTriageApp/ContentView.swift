import SwiftUI
import AppCore
import AppUI
import FactoryKit

struct ContentView: View {
    var body: some View {
        MailSplitView()
    }
}

#Preview {
    let _ = Container.shared.mailStore.register {
        MailStore(emails: InboxData.sampleEmails)
    }
    ContentView()
}
