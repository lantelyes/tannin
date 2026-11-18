import SwiftUI

struct SettingsView: View {
    @Environment(Updates.self) private var updates
    @AppStorage("showMenuBarItem") private var showMenuBarItem = false

    var body: some View {
        @Bindable var updates = updates
        Form {
            Section {
                Toggle(isOn: $showMenuBarItem) {
                    Text("Show Tannin in the Menu Bar")
                    Text("Status at a glance, and a quick way to start an installed game.")
                }
            }
            Section("Updates") {
                if updates.canUpdate {
                    Toggle(isOn: $updates.checksAutomatically) {
                        Text("Check for Updates Automatically")
                        Text("Once a day. Tannin asks before it installs anything.")
                    }
                    UpdateStatusRow()
                } else {
                    // A copy built without an update feed: there is nothing to check, so it only says what it is.
                    LabeledContent("Version", value: updates.currentVersion)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
