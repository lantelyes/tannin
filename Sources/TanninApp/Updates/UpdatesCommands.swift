import SwiftUI

/// Adds "Check for Updates…" to the app menu, under About, where Mac apps keep it.
struct UpdatesCommands: Commands {
    let updates: Updates

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updates.checkNow() }
                .disabled(!updates.canCheck)
        }
    }
}
