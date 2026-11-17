import SwiftUI
import TanninCore

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $model.selection) { item in
                Label {
                    Text(item.title)
                } icon: {
                    Image(systemName: item.symbol)
                        .foregroundStyle(Theme.accentText)
                }
                .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Theme.window)
        }
        .task {
            if let folder = Snapshotter.outputFolder {
                await Snapshotter.run(model: model, into: folder)
            } else {
                await model.keepRefreshing()
            }
        }
        .sheet(isPresented: $model.isShowingSteamPlaySheet) {
            SteamPlaySheet()
        }
        .alert("That didn't work", isPresented: $model.isShowingError) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .overlay(alignment: .bottom) {
            if let activity = model.activity {
                ActivityBanner(text: activity)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.selection ?? .overview {
        case .overview: OverviewView()
        case .games: GamesView()
        case .engine: EngineView()
        case .logs: LogsView()
        }
    }
}
