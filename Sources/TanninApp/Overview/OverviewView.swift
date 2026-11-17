import SwiftUI
import TanninCore

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            if let status = model.status {
                VStack(alignment: .leading, spacing: 18) {
                    hero(Headline(status))
                    thisMac(status)
                    games
                }
                .padding(24)
            } else {
                ProgressView("Checking this Mac…")
                    .padding(60)
            }
        }
        .navigationTitle("Overview")
    }

    private func hero(_ headline: Headline) -> some View {
        HStack(spacing: 14) {
            StatusGlyph(kind: headline.kind, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(headline.detail)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let action = headline.action {
                Button(action) { model.isShowingSteamPlaySheet = true }
                    .buttonStyle(.primary)
                    .disabled(model.isBusy)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func thisMac(_ status: TanninStatus) -> some View {
        CardSection(title: "This Mac") {
            CardRow(title: "Steam Play in Steam", status: status.steamPlay == .on ? .ok : .off) {
                Text(status.steamPlay == .on ? "On" : "Off").foregroundStyle(Theme.secondary)
                if let build = status.steamBuild { VersionChip(text: build) }
            }
            CardRow(title: "Wine engine", status: status.engineInstalled ? .ok : .pending) {
                Text(status.engineInstalled ? "Installed" : "Not installed").foregroundStyle(Theme.secondary)
                VersionChip(text: status.engineWine)
            }
            CardRow(title: "D3DMetal", status: status.d3dMetalVersion == nil ? .pending : .ok) {
                Text(status.d3dMetalVersion == nil ? "Not imported" : "From your Game Porting Toolkit")
                    .foregroundStyle(Theme.secondary)
                if let version = status.d3dMetalVersion { VersionChip(text: version) }
            }
            CardRow(title: "Steam updates",
                    caption: "Frozen keeps Steam on this build so Steam Play stays on.",
                    showsDivider: false) {
                Text(status.updateFreeze ? "Frozen" : "Allowed").foregroundStyle(Theme.secondary)
            }
        }
    }

    private var games: some View {
        CardSection(title: "Windows games") {
            if model.games.isEmpty {
                CardRow(title: "No Windows games yet",
                        caption: "Install one in Steam and it appears here.",
                        status: .pending, showsDivider: false) {
                    Button("Open Steam") { model.openSteam() }
                }
            } else {
                ForEach(model.games) { game in
                    CardRow(title: game.name, showsDivider: game.id != model.games.last?.id) {
                        Text(GamePreset(matching: game.settings).title)
                            .foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
    }
}
