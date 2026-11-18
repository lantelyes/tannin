import SwiftUI

@main
struct TanninApp: App {
    @State private var model = AppModel()
    @AppStorage("showMenuBarItem") private var showMenuBarItem = false

    var body: some Scene {
        Window("Tannin", id: WindowID.main) {
            RootView()
                .environment(model)
        }
        .defaultSize(width: 960, height: 700)
        .defaultLaunchBehavior(model.needsSetupAtLaunch ? .suppressed : .presented)
        .commands {
            SetupCommands()
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
