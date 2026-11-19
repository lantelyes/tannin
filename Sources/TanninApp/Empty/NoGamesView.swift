import SwiftUI

/// Shown when no Windows game is installed yet.
struct NoGamesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("No Windows Games Installed", systemImage: "gamecontroller")
        } description: {
            Text(model.problem == nil
                ? "Install a Windows game from your Steam library and it’ll show up here."
                : "Turn on Steam Play, then install a Windows game from your Steam library.")
        } actions: {
            Button("Open Steam") { model.openSteam() }
                .buttonStyle(.borderedProminent)
        }
        .navigationTitle("Tannin")
        .toolbar(removing: .title)
    }
}
