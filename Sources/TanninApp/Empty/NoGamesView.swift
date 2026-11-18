import SwiftUI

/// Shown when no Windows game is installed yet.
struct NoGamesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("No Windows Games Yet", systemImage: "gamecontroller")
        } description: {
            Text(model.problem == nil
                ? "Steam can now install Windows games. Install one from your Steam library and it appears here."
                : "Once Steam Play is on, install a Windows game from your Steam library and it appears here.")
        } actions: {
            Button("Open Steam") { model.openSteam() }
                .buttonStyle(.borderedProminent)
        }
        .navigationTitle("Tannin")
        .toolbar(removing: .title)
    }
}
