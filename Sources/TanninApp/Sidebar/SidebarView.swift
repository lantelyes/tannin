import SwiftUI
import TanninCore

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    /// Whether the Not Installed section is open. The setup window opens it when it hands over to this one.
    static let notInstalledExpandedKey = "notInstalledExpanded"
    @AppStorage(SidebarView.notInstalledExpandedKey) private var isNotInstalledExpanded = false

    private var isSearching: Bool { !model.search.trimmingCharacters(in: .whitespaces).isEmpty }

    private func matching(_ games: [LibraryGame]) -> [LibraryGame] {
        guard isSearching else { return games }
        return games.filter { $0.name.localizedStandardContains(model.search) }
    }

    var body: some View {
        @Bindable var model = model
        let installed = matching(model.library.installed)
        let notInstalled = matching(model.library.notInstalled)

        ScrollViewReader { proxy in
            list(installed: installed, notInstalled: notInstalled)
                // The setup window hands over with a game selected far down a long section; bring it into view.
                .task(id: model.gameToReveal) {
                    guard let appID = model.gameToReveal else { return }
                    // The section it is in has only just been opened.
                    try? await Task.sleep(for: .milliseconds(300))
                    proxy.scrollTo(appID, anchor: .center)
                    model.gameToReveal = nil
                }
        }
    }

    private func list(installed: [LibraryGame], notInstalled: [LibraryGame]) -> some View {
        @Bindable var model = model
        return List(selection: $model.selection) {
            Section("Windows Games") {
                ForEach(installed) { game in
                    GameRow(game: game).tag(SidebarSelection.game(game.appID))
                }
                if installed.isEmpty {
                    Text(isSearching ? "No results" : "None installed")
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                }
            }

            if isSearching {
                // While searching, matches are shown whether or not the section was open.
                if !notInstalled.isEmpty {
                    Section("Not Installed") { rows(notInstalled) }
                }
            } else if !notInstalled.isEmpty {
                Section(isExpanded: $isNotInstalledExpanded) {
                    rows(notInstalled)
                } header: {
                    // The count sits beside the title; the trailing edge is where the system puts its disclosure arrow.
                    HStack(spacing: 6) {
                        Text("Not Installed")
                        Text(notInstalled.count, format: .number)
                            .foregroundStyle(.tertiary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            if !isSearching {
                Section("Tannin") {
                    HStack {
                        Label("Steam Play", systemImage: "play.rectangle")
                        if model.problem?.isWarning == true {
                            Spacer(minLength: 0)
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .accessibilityLabel("Needs attention")
                        }
                    }
                    .tag(SidebarSelection.steamPlay)
                    Label("Engines & Renderers", systemImage: "cpu")
                        .tag(SidebarSelection.renderers)
                    Label("Logs", systemImage: "doc.text")
                        .tag(SidebarSelection.logs)
                }
            }
        }
        // A bar, not a plain inset: the system fades the list out underneath it.
        .safeAreaBar(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                UpdateSidebarRow()
                UpkeepSidebarRow()
                SidebarStatus()
            }
        }
    }

    private func rows(_ games: [LibraryGame]) -> some View {
        ForEach(games) { game in
            GameRow(game: game).tag(SidebarSelection.game(game.appID))
        }
    }
}
