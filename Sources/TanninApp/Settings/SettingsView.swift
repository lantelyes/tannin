import SwiftUI

struct SettingsView: View {
    @AppStorage("showMenuBarItem") private var showMenuBarItem = false

    var body: some View {
        Form {
            Toggle("Show Tannin in the menu bar", isOn: $showMenuBarItem)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
