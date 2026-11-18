import SwiftUI

/// Adds "Set Up Tannin…" to the app menu, so setup can be reopened at any time.
struct SetupCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Button("Set Up Tannin…") { openWindow(id: WindowID.setup) }
        }
    }
}
