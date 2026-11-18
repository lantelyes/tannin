import SwiftUI
import TanninCore

/// The one step of setup that changes another app, under Steam's own icon. Its button opens the sheet that
/// explains the step before anything happens.
struct SteamPlayCard: View {
    @Environment(AppModel.self) private var model
    @Binding var isAddingSteamPlay: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Paths.app.steamApp.path))
                .resizable()
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ready to add Steam Play to Steam").fontWeight(.semibold)
                Text("The only step that changes Steam. Steam quits once, and macOS asks for permission.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Add Steam Play…") { isAddingSteamPlay = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(model.isBusy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 560)
        .background(.fill.quaternary, in: .rect(cornerRadius: 12))
    }
}
