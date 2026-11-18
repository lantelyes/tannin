import SwiftUI
import TanninCore

/// The menu bar item: status at a glance, installed games to start, and a way back to the window.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(Updates.self) private var updates
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if case let .available(version) = updates.status {
            Button("Update to Tannin \(version)…") {
                NSApp.activate()
                updates.checkNow()
            }
            Divider()
        }
        if let status = model.status {
            Text(model.problem?.title ?? "Steam Play is on")
            Text("Wine \(status.engineWine), D3DMetal \(status.d3dMetalVersion ?? "not imported")")
        } else {
            Text("Checking this Mac…")
        }
        if !model.library.installed.isEmpty {
            Divider()
            ForEach(model.library.installed) { game in
                Button("Play \(game.name)") { model.play(game) }
                    .disabled(!model.canPlay(game))
            }
        }
        Divider()
        Button("Open Tannin") {
            openWindow(id: WindowID.main)
            NSApp.activate()
        }
        Button("Open Steam") { model.openSteam() }
        Divider()
        Button("Quit Tannin") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
