import SwiftUI
import TanninCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(Updates.self) private var updates
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

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
                await Snapshotter.run(model: model, updates: updates, into: folder,
                                      openWindow: { openWindow(id: $0) }, openSettings: { openSettings() })
            }
        }
        // When Steam moves past the build this Tannin supports, a newer Tannin is the fix: look for one straight away.
        .onChange(of: model.problem, initial: true) { checkIfSteamMoved() }
        .onChange(of: updates.canCheck) {
            // At launch the problem can be known before Sparkle is ready to check.
            if updates.status == .unknown { checkIfSteamMoved() }
        }
        .sheet(isPresented: $model.isShowingSteamPlaySheet) {
            SteamPlaySheet()
        }
        .sheet(isPresented: $model.isShowingD3DMetalSheet) {
            AddD3DMetalSheet()
        }
        .alert(model.errorTitle, isPresented: $model.isShowingErrorInMain) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func checkIfSteamMoved() {
        if model.problem == .steamUpdated { updates.checkQuietly() }
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
        case .steamPlay:
            SteamPlayView()
        case .renderers:
            RenderersView()
        case .logs:
            LogsView()
        case nil:
            if model.status == nil {
                ProgressView("Checking Steam…")
            } else {
                NoGamesView()
            }
        }
    }
}
