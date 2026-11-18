import SwiftUI

struct SettingsView: View {
    @AppStorage("showMenuBarItem") private var showMenuBarItem = false

    var body: some View {
        Form {
            Toggle(isOn: $showMenuBarItem) {
                Text("Show Tannin in the Menu Bar")
                Text("Status at a glance, and a quick way to start an installed game.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
