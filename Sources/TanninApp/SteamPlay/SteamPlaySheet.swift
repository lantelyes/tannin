import SwiftUI

/// Shown before Steam is changed: what happens, what macOS will ask, and how to undo it.
struct SteamPlaySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// True when the setup window asks: what happens next is then shown in that window, not in an alert.
    var isForSetup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Steam Play to Steam?")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 12) {
                point("arrow.clockwise", "Steam quits once and reopens",
                      "Tannin adds one file to Steam and signs Steam again on this Mac.")
                point("lock.shield", "macOS asks for permission",
                      "Allow Tannin to change other apps. macOS then asks again for Steam's controller and keyboard access.")
                point("arrow.uturn.backward", "You can remove it at any time",
                      "Steam goes back exactly as Valve ships it. Your games, saves and account are not touched.")
            }

            Text("Valve does not support this.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Steam Play") {
                    dismiss()
                    Task {
                        if isForSetup {
                            await model.addSteamPlayFromSetup()
                        } else {
                            await model.addSteamPlay()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 22)
        }
    }
}
