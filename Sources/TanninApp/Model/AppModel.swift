import AppKit
import Observation
import TanninCore

/// What the app shows and the actions it can take. The core library blocks while it works,
/// so every call into it runs off the main actor and the results are brought back here.
@Observable @MainActor
final class AppModel {
    private(set) var status: TanninStatus?
    private(set) var library = Library.empty
    private(set) var logLines: [LogLine] = []
    private(set) var setup: [Setup.Step: Setup.State] = [:]
    /// The setup step that is downloading or paused, if any.
    private(set) var setupProgress: SetupProgress?
    /// A plain description of the action in progress, or nil.
    private(set) var activity: String?
    private(set) var errorMessage: String?
    /// One flag per window, so a failure is reported once, in the window the user is looking at.
    var isShowingErrorInMain = false
    var isShowingErrorInSetup = false
    var selection: SidebarSelection?
    var search = ""
    var isShowingSteamPlaySheet = false

    /// Decided once, before any window opens: whether the app starts in its setup window.
    let needsSetupAtLaunch: Bool

    private let paths = Paths.live
    private var libraryFingerprint: String?
    private var cancellation: Cancellation?
    /// Set while showing made-up data for screenshots, so nothing replaces it.
    private var isShowingFixture = false

    init() {
        let isTakingScreenshots = Snapshotter.outputFolder != nil
        needsSetupAtLaunch = !isTakingScreenshots && !Setup(paths: paths).isReadyForSteamPlay
        // The model lives as long as the app, and every window and the menu bar read from it,
        // so it keeps itself up to date rather than relying on one window being open.
        if !isTakingScreenshots {
            Task { await keepRefreshing() }
        }
    }

    var isBusy: Bool { activity != nil || (setupProgress != nil && setupProgress?.isPaused == false) }
    var problem: SteamPlayProblem? { status.flatMap(SteamPlayProblem.init) }

    func canPlay(_ game: LibraryGame) -> Bool {
        game.install == .installed && status != nil && problem == nil
    }

    // MARK: Reading

    func refresh() async {
        guard !isShowingFixture else { return }
        let paths = paths
        let known = libraryFingerprint
        let snapshot = await Task.detached {
            let reader = LibraryReader(paths: paths)
            let fingerprint = reader.fingerprint()
            return (
                status: StatusReader(paths: paths).read(),
                fingerprint: fingerprint,
                library: fingerprint == known ? nil : reader.read(),
                logLines: LogReader(paths: paths).recentLines(),
                setup: Setup(paths: paths).states()
            )
        }.value
        guard !isShowingFixture else { return }
        // Only assign what changed, so views that read the rest are left alone.
        if status != snapshot.status { status = snapshot.status }
        if let fresh = snapshot.library {
            libraryFingerprint = snapshot.fingerprint
            if library != fresh { library = fresh }
        }
        if logLines != snapshot.logLines { logLines = snapshot.logLines }
        let states = Dictionary(uniqueKeysWithValues: snapshot.setup.map { ($0.step, $0.state) })
        if setup != states { setup = states }
        reconcileSelection()
    }

    private func keepRefreshing() async {
        while !Task.isCancelled {
            if !isBusy { await refresh() }
            try? await Task.sleep(for: .seconds(10))
        }
    }

    /// Keeps the selection pointing at something that exists, starting on the first installed game.
    private func reconcileSelection() {
        if case let .game(appID) = selection, library.game(appID) != nil { return }
        if selection == .engine || selection == .logs { return }
        selection = library.installed.first.map { .game($0.appID) }
    }

    /// Replaces everything shown with prepared data. Used only to take screenshots of states this Mac is not in.
    func show(_ fixture: Fixture) {
        isShowingFixture = true
        status = fixture.status
        library = fixture.library
        logLines = fixture.logLines
        setup = fixture.setup
        setupProgress = fixture.setupProgress
        selection = fixture.selection
        isShowingSteamPlaySheet = fixture.isShowingSteamPlaySheet
    }

    /// Goes back to what is really on this Mac.
    func showLiveData() async {
        isShowingFixture = false
        libraryFingerprint = nil
        setupProgress = nil
        isShowingSteamPlaySheet = false
        selection = nil
        await refresh()
    }

    // MARK: Changing things

    private func fail(_ error: any Error) {
        errorMessage = String(describing: error)
        let setupIsInFront = NSApp.keyWindow?.identifier?.rawValue.hasPrefix(WindowID.setup) ?? false
        if setupIsInFront {
            isShowingErrorInSetup = true
        } else {
            isShowingErrorInMain = true
        }
    }

    private func perform(_ label: String, _ work: @escaping @Sendable () throws -> Void) async {
        guard !isBusy else { return }
        activity = label
        do {
            try await Task.detached(operation: work).value
        } catch {
            fail(error)
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
            try? SteamLauncher(paths: paths).openSteam()
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
            if wasRunning { try? SteamLauncher(paths: paths).openSteam() }
        }
    }

    func importToolkit(from url: URL) async {
        let paths = paths
        await perform("Importing the Game Porting Toolkit") {
            try Setup(paths: paths).importToolkit(from: url)
        }
    }

    // MARK: Asking Steam

    private func ask(_ request: SteamLauncher.Request) {
        let paths = paths
        Task {
            do {
                try await Task.detached { try SteamLauncher(paths: paths).send(request) }.value
            } catch {
                fail(error)
            }
        }
    }

    func play(_ game: LibraryGame) { ask(.play(game.appID)) }
    func install(_ game: LibraryGame) { ask(.install(game.appID)) }
    func showInSteam(_ game: LibraryGame) { ask(.showInLibrary(game.appID)) }

    func openSteam() {
        let paths = paths
        Task.detached { try? SteamLauncher(paths: paths).openSteam() }
    }

    func bugReport() -> String {
        guard let status else { return "Tannin has not finished reading its status yet." }
        return LogReader(paths: paths).bugReport(status: status)
    }

    var logFile: URL { LogReader(paths: paths).addonLog }

    // MARK: Setup

    /// Runs the setup steps that download things, one after the other: Rosetta, the engine, then the bridge.
    /// Stops at the first one that fails or is paused.
    func runDownloads(startingWith first: Setup.Step) async {
        let order: [Setup.Step] = [.rosetta, .engine, .bridge]
        guard let start = order.firstIndex(of: first) else { return }
        for step in order[start...] {
            // Rosetta is only installed when asked for directly; the engine carries on into the bridge.
            if step != first, step == .rosetta { continue }
            if setup[step]?.isDone == true { continue }
            guard await run(step) else { return }
        }
    }

    /// Returns whether the step finished.
    private func run(_ step: Setup.Step) async -> Bool {
        guard !isBusy else { return false }
        let cancellation = Cancellation()
        self.cancellation = cancellation
        setupProgress = SetupProgress(step: step)
        let paths = paths
        let context = WorkContext(quiet: true, progress: { [weak self] progress in
            Task { @MainActor in self?.report(progress, for: step) }
        }, cancellation: cancellation)

        var finished = false
        do {
            try await Task.detached {
                let setup = Setup(paths: paths)
                switch step {
                case .rosetta: try setup.installRosetta(context)
                case .engine: try setup.installEngine(context)
                case .bridge: try setup.installBridge(context)
                case .steam, .toolkit, .steamPlay: break
                }
            }.value
            finished = true
            setupProgress = nil
        } catch is Cancelled {
            setupProgress?.isPaused = true
        } catch {
            setupProgress = nil
            fail(error)
        }
        self.cancellation = nil
        await refresh()
        return finished
    }

    private func report(_ progress: DownloadProgress, for step: Setup.Step) {
        // Reports can arrive just after the step ended; those are dropped.
        guard setupProgress?.step == step, setupProgress?.isPaused == false else { return }
        setupProgress?.download = progress
    }

    func pauseDownloads() {
        cancellation?.cancel()
    }
}
