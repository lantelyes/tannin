import SwiftUI
import TanninCore

struct GamesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.gamesPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Your Windows games from Steam. Install and play them in Steam; here you choose how each one runs.")
                        .foregroundStyle(Theme.secondary)
                    if model.games.isEmpty {
                        ContentUnavailableView {
                            Label("No Windows games yet", systemImage: "gamecontroller")
                        } description: {
                            Text("Install one in Steam and it appears here.")
                        } actions: {
                            Button("Open Steam") { model.openSteam() }
                        }
                    } else {
                        CardSection(title: "Installed") {
                            ForEach(model.games) { game in
                                NavigationLink(value: game) {
                                    CardRow(title: game.name, status: .ok, showsDivider: game.id != model.games.last?.id) {
                                        Text(GamePreset(matching: game.settings).title)
                                            .foregroundStyle(Theme.secondary)
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(Theme.secondary)
                                            .accessibilityHidden(true)
                                    }
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(24)
            }
            .background(Theme.window)
            .navigationTitle("Games")
            .navigationDestination(for: WindowsGame.self) { game in
                GameSettingsView(game: game)
            }
        }
    }
}
