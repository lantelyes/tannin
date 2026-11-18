import SwiftUI

/// The row in Settings that says which Tannin this is, how the last check went, and offers the next step.
struct UpdateStatusRow: View {
    @Environment(Updates.self) private var updates

    var body: some View {
        LabeledContent {
            action
        } label: {
            Label {
                Text(title)
                Text(caption)
            } icon: {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
            }
        }
    }

    private var title: String {
        if case let .available(version) = updates.status {
            "Tannin \(version) is available"
        } else {
            "Tannin \(updates.currentVersion)"
        }
    }

    private var caption: String {
        switch updates.status {
        case .unknown: lastChecked ?? "Not checked yet."
        case .checking: "Checking for updates…"
        case .upToDate: ["Up to date.", lastChecked].compactMap(\.self).joined(separator: " ")
        case .available: "You have \(updates.currentVersion)."
        case let .failed(reason): "Couldn't check. \(reason)"
        }
    }

    /// "Last checked today at 09:41."
    private var lastChecked: String? {
        guard let date = updates.lastChecked else { return nil }
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        let day = if calendar.isDateInToday(date) {
            "today"
        } else if calendar.isDateInYesterday(date) {
            "yesterday"
        } else {
            "on \(date.formatted(.dateTime.day().month(.wide)))"
        }
        return "Last checked \(day) at \(time)."
    }

    @ViewBuilder private var action: some View {
        switch updates.status {
        case .checking:
            ProgressView().controlSize(.small)
        case .available:
            Button("Update…") { updates.checkNow() }
                .buttonStyle(.borderedProminent)
        case .failed:
            Button("Try Again") { updates.checkNow() }
                .disabled(!updates.canCheck)
        case .unknown, .upToDate:
            Button("Check Now") { updates.checkNow() }
                .disabled(!updates.canCheck)
        }
    }
}
