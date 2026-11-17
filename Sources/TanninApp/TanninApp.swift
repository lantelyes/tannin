import SwiftUI

@main
struct TanninApp: App {
    @State private var model = AppModel()
    @AppStorage("showMenuBarItem") private var showMenuBarItem = false

    var body: some Scene {
        Window("Tannin", id: "main") {
            RootView()
                .environment(model)
                .tint(Theme.accent)
        }
        .defaultSize(width: 920, height: 620)

        Settings {
            SettingsView()
        }

        MenuBarExtra("Tannin", systemImage: "hexagon", isInserted: $showMenuBarItem) {
            MenuBarContent()
                .environment(model)
        }
    }
}
