import SwiftUI
import TanninCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 236, ideal: 250, max: 340)
        } detail: {
            detail
        }
        .frame(minWidth: 780, minHeight: 520)
        .searchable(text: $model.search, placement: .sidebar, prompt: "Search")
        .task {
            if let folder = Snapshotter.outputFolder {
                await Snapshotter.run(model: model, into: folder) { openWindow(id: $0) }
            }
        }
        .sheet(isPresented: $model.isShowingSteamPlaySheet) {
            SteamPlaySheet()
        }
        .alert("That didn't work", isPresented: $model.isShowingErrorInMain) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.selection {
        case let .game(appID):
            if let game = model.library.game(appID) {
                // A new identity per game, so one game's unsaved changes never show on another.
                GamePage(game: game).id(appID)
            } else {
                NoGamesView()
            }
        case .engine:
            EngineView()
        case .logs:
            LogsView()
        case nil:
            if model.status == nil {
                ProgressView("Checking this Mac…")
            } else {
                NoGamesView()
            }
        }
    }
}
