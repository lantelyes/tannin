import SwiftUI

@main
struct TanninApp: App {
    @State private var model = AppModel()
    @State private var updates = Updates()
    @AppStorage("showMenuBarItem") private var showMenuBarItem = false

    var body: some Scene {
        Window("Tannin", id: WindowID.main) {
            RootView()
                .environment(model)
                .environment(updates)
        }
        .defaultSize(width: 960, height: 700)
        .defaultLaunchBehavior(model.needsSetupAtLaunch ? .suppressed : .presented)
        .commands {
            SetupCommands()
            UpdatesCommands(updates: updates)
        }

        Window("Set Up Tannin", id: WindowID.setup) {
            SetupView()
                .environment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(model.needsSetupAtLaunch ? .presented : .suppressed)

        Settings {
            SettingsView()
                .environment(updates)
        }

        MenuBarExtra(isInserted: $showMenuBarItem) {
            MenuBarContent()
                .environment(model)
        } label: {
            Image(nsImage: MenuBarGlyph.image)
                .accessibilityLabel("Tannin")
        }
    }
}
