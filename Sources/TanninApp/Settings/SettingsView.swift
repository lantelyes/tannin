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
                    Text("See Steam Play’s status and start games from the menu bar.")
                }
            }
            Section("Updates") {
                if updates.canUpdate {
                    Toggle(isOn: $updates.checksAutomatically) {
                        Text("Check for Updates Automatically")
                        Text("Tannin checks once a day and asks before installing.")
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
