import Foundation
import Observation
import TanninCore

/// Stands in until the app is rebuilt around `LibraryGame`.
typealias WindowsGame = LibraryGame

/// What the app shows and the actions it can take. The core library blocks while it works,
/// so every call into it runs off the main actor and the results are brought back here.
@Observable @MainActor
final class AppModel {
    private(set) var status: TanninStatus?
    private(set) var games: [WindowsGame] = []
    private(set) var logLines: [LogLine] = []
    /// A plain description of the action in progress, or nil.
    private(set) var activity: String?
    private(set) var errorMessage: String?
    var isShowingError = false
    var selection: SidebarItem? = .overview
    var isShowingSteamPlaySheet = false
    /// The game settings screen currently pushed in Games, if any.
    var gamesPath: [WindowsGame] = []

    private let paths = Paths.live

    var isBusy: Bool { activity != nil }

    func refresh() async {
        let paths = paths
        let snapshot = await Task.detached {
            (StatusReader(paths: paths).read(),
             LibraryReader(paths: paths).read().installed,
             LogReader(paths: paths).recentLines())
        }.value
        status = snapshot.0
        games = snapshot.1
        logLines = snapshot.2
    }

    /// Refreshes every few seconds for as long as the calling task lives.
    func keepRefreshing() async {
        while !Task.isCancelled {
            if !isBusy { await refresh() }
            try? await Task.sleep(for: .seconds(10))
        }
    }

    private func perform(_ label: String, _ work: @escaping @Sendable () throws -> Void) async {
        guard activity == nil else { return }
        activity = label
        do {
            try await Task.detached(operation: work).value
        } catch {
            errorMessage = String(describing: error)
            isShowingError = true
        }
        activity = nil
        await refresh()
    }

    func setUpdateFreeze(_ on: Bool) async {
        let paths = paths
        await perform(on ? "Freezing Steam updates" : "Allowing Steam updates") {
            try UpdateFreeze(paths: paths).set(on)
        }
    }

    func addSteamPlay() async {
        let paths = paths
        await perform("Adding Steam Play to Steam") {
            try SteamAddon(paths: paths).enable()
            _ = try? Shell.run("/usr/bin/open", ["-a", paths.steamApp.path])
        }
    }

    func removeSteamPlay() async {
        let paths = paths
        await perform("Putting Steam back as Valve ships it") {
            try SteamAddon(paths: paths).disable(quiet: true)
        }
    }

    /// Writes a game's settings into its Steam launch options. Steam is quit first if needed, then reopened.
    func save(_ settings: GameSettings, appID: String) async {
        let paths = paths
        await perform("Saving game settings") {
            let wasRunning = SteamInstall(paths: paths).isRunning()
            if wasRunning { try SteamAddon(paths: paths).stopSteam() }
            let config = SteamConfig(paths: paths)
            let options = settings.launchOptions(merging: config.launchOptions(appID: appID) ?? "")
            try config.setLaunchOptions(appID: appID, options)
            if wasRunning { _ = try? Shell.run("/usr/bin/open", ["-a", paths.steamApp.path]) }
        }
    }

    func importToolkit(from url: URL) async {
        let paths = paths
        await perform("Importing the Game Porting Toolkit") {
            let toolkit = try GPTK(paths: paths).importToolkit(from: url)
            try D3DMetalLink(paths: paths).link(toolkit)
        }
    }

    func openSteam() {
        let app = paths.steamApp.path
        Task.detached { _ = try? Shell.run("/usr/bin/open", ["-a", app]) }
    }

    func bugReport() -> String {
        guard let status else { return "Tannin has not finished reading its status yet." }
        return LogReader(paths: paths).bugReport(status: status)
    }
}
