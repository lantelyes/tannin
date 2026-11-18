import SwiftUI

/// The row above the sidebar's status lines, shown only while an update is waiting.
/// Clicking it brings up the standard update window.
struct UpdateSidebarRow: View {
    @Environment(Updates.self) private var updates

    var body: some View {
        if case let .available(version) = updates.status {
            Button {
                NSApp.activate()
                updates.checkNow()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Update Available")
                        Text("Tannin \(version)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 9)
                .frame(height: 42)
                .background(.quaternary, in: .rect(cornerRadius: 8))
                .contentShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .help("See what's new in Tannin \(version) and install it")
        }
    }
}
