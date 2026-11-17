import SwiftUI
import TanninCore

/// The menu bar item: status at a glance and a way back to the window. A menu, not a popover.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let status = model.status {
            Text(Headline(status).title)
            Text("Wine \(status.engineWine), D3DMetal \(status.d3dMetalVersion ?? "not imported")")
        } else {
            Text("Checking this Mac…")
        }
        Divider()
        Button("Open Tannin") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Button("Open Steam") { model.openSteam() }
        Divider()
        Button("Quit Tannin") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
