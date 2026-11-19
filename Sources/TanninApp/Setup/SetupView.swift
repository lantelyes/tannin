import SwiftUI
import TanninCore

/// The first-run window: one screen that changes as setup goes. Seven covers run across the top, the same for
/// everyone; the middle holds the one thing to do, or what is happening.
/// Everything shown is worked out from what is on disk, so the window can be closed and reopened at any point.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    /// This window's own sheet, so asking here does not also open one on the main window.
    @State private var isAddingSteamPlay = false
    @AppStorage("setupDetailsExpanded") private var isShowingDetails = false

    var body: some View {
        @Bindable var model = model
        let phase = model.setupPhase

        VStack(spacing: 0) {
            VStack(spacing: 0) {
                SetupCoverBand(pictures: model.setupArt)
                header(phase)
                SetupAction(phase: phase, isAddingSteamPlay: $isAddingSteamPlay, finish: showMyGames)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 30)
            }
            .frame(height: Self.bandHeight)

            if isShowingDetails {
                SetupDetails(phase: phase)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
            }
            footer(phase)
        }
        .frame(width: 720)
        // The pictures this Mac does not have yet are fetched for the window, not before anyone has opened it.
        .task { await model.loadSetupArt() }
        .sheet(isPresented: $isAddingSteamPlay) {
            SteamPlaySheet(isForSetup: true)
        }
        .alert(model.errorTitle, isPresented: $model.isShowingErrorInSetup) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    /// The height of everything between the title bar and the footer. It is the same in every state, so the
    /// window never changes size except for Details.
    private static let bandHeight: CGFloat = 504

    // MARK: Words

    private func header(_ phase: SetupPhase) -> some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.22), radius: 6, y: 5)
                .accessibilityHidden(true)
            Text(title(phase))
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .padding(.top, 12)
            Text(lead(phase))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 500)
                .padding(.top, 8)
        }
        .padding(.horizontal, 30)
        // The icon sits half over the covers.
        .padding(.top, -40)
    }

    private var gameCount: Int { model.library.all.count }

    private func title(_ phase: SetupPhase) -> String {
        switch phase {
        case .done:
            gameCount == 0 ? "Steam can now install Windows games" : "Steam can now install your Windows games"
        case .readyForSteamPlay, .foreignTool, .addingSteamPlay, .steamPlayRefused, .steamPlayFailed:
            "Almost there"
        case .checking, .steamMissing, .before, .working, .paused, .failed:
            switch gameCount {
            case 0: "Set Up Tannin"
            case 1: "1 of your Steam games is Windows-only"
            default: "\(gameCount) of your Steam games are Windows-only"
            }
        }
    }

    private func lead(_ phase: SetupPhase) -> String {
        switch phase {
        case .done:
            let games = gameCount == 0
                ? "Windows games in your Steam library now have an Install button, like any Mac game."
                : "Find them in your Steam library and click Install, like any Mac game."
            return model.d3dMetalIsAdded
                ? games
                : games + " Direct3D 12 games also need Apple’s D3DMetal, which you can add in Engines & Renderers."
        case .readyForSteamPlay, .foreignTool, .addingSteamPlay, .steamPlayRefused, .steamPlayFailed:
            return "Wine and the Steam bridge are installed. The last step adds Steam Play to Steam."
        case .checking, .steamMissing, .before, .working, .paused, .failed:
            let what = switch gameCount {
            case 0: "Tannin lets you install and play Windows games from Steam on your Mac."
            case 1: "Tannin lets you install and play it from Steam on your Mac."
            default: "Tannin lets you install and play them from Steam on your Mac."
            }
            return "\(what) Setup downloads about \(Setup.downloadBytes.roundedMegabytes) and asks before it changes Steam."
        }
    }

    // MARK: Footer

    private func footer(_ phase: SetupPhase) -> some View {
        HStack {
            Button {
                isShowingDetails.toggle()
            } label: {
                Label("Details", systemImage: isShowingDetails ? "chevron.down" : "chevron.right")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityValue(isShowingDetails ? "Open" : "Closed")

            Spacer()
            corner(phase)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(height: 44, alignment: .top)
    }

    /// The one button in the corner, which is never the main thing to do.
    @ViewBuilder private func corner(_ phase: SetupPhase) -> some View {
        switch phase {
        case let .working(work):
            Button("Pause") { model.pauseDownloads() }
                .disabled(!work.canPause)
        case .readyForSteamPlay, .foreignTool, .steamPlayRefused, .steamPlayFailed:
            Button("Not Now", action: showMainWindow)
        case .addingSteamPlay:
            EmptyView()
        case .done:
            if !model.setupIsFirstRun {
                Button("Close") { dismissWindow(id: WindowID.setup) }
            }
        case .checking, .steamMissing, .before, .paused, .failed:
            if model.setupIsFirstRun {
                Button("Quit") { NSApp.terminate(nil) }
            } else {
                Button("Close") { dismissWindow(id: WindowID.setup) }
            }
        }
    }

    private func showMainWindow() {
        openWindow(id: WindowID.main)
        dismissWindow(id: WindowID.setup)
    }

    private func showMyGames() {
        model.showMyGames()
        showMainWindow()
    }
}
