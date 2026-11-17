import SwiftUI

/// Shown before Steam is changed: what changes, what does not, and how to undo it.
struct SteamPlaySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let changes = [
        ("add", "one add-on file inside Steam"),
        ("edit", "two lines of Steam's settings file"),
        ("sign", "Steam, signed again on this Mac"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Steam Play to Steam?")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.text)

            heading("What changes")
            VStack(spacing: 0) {
                ForEach(changes, id: \.0) { change in
                    HStack(spacing: 10) {
                        Text(change.0)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.accentText)
                            .frame(width: 34, alignment: .leading)
                        Text(change.1).foregroundStyle(Theme.text)
                        Spacer()
                    }
                    .font(.callout.monospaced())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                }
            }
            .background(Theme.card, in: .rect(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line) }

            heading("What does not change")
            Text("Your games, your saves and your Steam account.")
                .foregroundStyle(Theme.text)

            heading("How to undo it")
            Text("Choose Remove Steam Play in Tannin. Steam is put back exactly as Valve ships it, and Tannin checks Valve's signature first.")
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
            Text("Valve does not support this. Steam quits now and reopens afterwards. macOS then asks once more for Steam's controller and keyboard permissions.")
                .font(.callout)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Not Now", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Steam Play") {
                    dismiss()
                    Task { await model.addSteamPlay() }
                }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Theme.window)
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(Theme.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}
