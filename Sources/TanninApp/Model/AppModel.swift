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
    /// What an earlier Tannin installed that this one would bring up to date.
    private(set) var upkeep: [Upkeep.Item] = []
    private(set) var upkeepProgress: UpkeepProgress?
    /// Which graphics layer each installed game last ran on, where its log says.
    private(set) var layerUsage: [String: LayerUsage] = [:]
    /// The Wine engine's size on disk, worked out once.
    private(set) var engineSize: Int64?
    /// The Wine engines Tannin knows, installed or not.
    private(set) var engines: [EngineRow] = []
    /// The engine that is downloading or paused, if any.
    private(set) var engineProgress: EngineProgress?
    /// Which Wine engine each installed game uses.
    private(set) var gameEngines: [String: GameEngine] = [:]
    /// The copy of each game's Windows environment, where one has been made.
    private(set) var environmentCopies: [String: EnvironmentCopy.Info] = [:]
    /// Games moved to another Wine version since the app opened, for the notice on their page.
    private(set) var recentlyMoved: Set<String> = []
    private var engineSizes: [String: Int64] = [:]
    /// The fixed window each game is set to run in, for those that have one.
    private(set) var fixedWindows: [String: FixedWindow.Size] = [:]
    /// Games that have a Windows environment, which is where a fixed window is kept.
    private(set) var gamesWithEnvironment: Set<String> = []
    private(set) var runningGames: Set<String> = []
    /// Games whose last start was refused the screen size they asked for.
    private(set) var refusedScreenSize: Set<String> = []
    /// Games whose last start asked for Direct3D 12 while D3DMetal was not on the Mac, and drew nothing.
    private(set) var neededDirect3D12: Set<String> = []
    /// A plain description of the action in progress, or nil.
    private(set) var activity: String?
    private(set) var errorMessage: String?
    /// One flag per window, so a failure is reported once, in the window the user is looking at.
    var isShowingErrorInMain = false
    var isShowingErrorInSetup = false
    var selection: SidebarSelection?
    var search = ""
    var isShowingSteamPlaySheet = false
    /// The Add D3DMetal sheet, opened from the Engines & Renderers page or from a game's Renderer pop-up.
    var isShowingD3DMetalSheet = false
    private(set) var d3dMetalAdd = D3DMetalAdd.idle
    /// The Wine version a game's page asked for and that game has not moved to yet. Forgotten when the app quits;
    /// the engine itself stays, in the list of engines.
    private(set) var wantedEngines: [String: EngineSpec] = [:]

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

    var isBusy: Bool {
        activity != nil || (setupProgress != nil && setupProgress?.isPaused == false)
            || (engineProgress != nil && engineProgress?.isPaused == false)
    }

    /// The engine a game runs on, for writing its launch options.
    func engine(for appID: String) -> EngineSpec { gameEngines[appID]?.runsOn ?? .newest }
    /// True once a second engine is installed, which is when a game can be given a Wine version of its own.
    var hasSeveralEngines: Bool { engines.count(where: \.isInstalled) > 1 }
    var problem: SteamPlayProblem? { status.flatMap(SteamPlayProblem.init) }

    func canPlay(_ game: LibraryGame) -> Bool {
        game.install == .installed && status != nil && problem == nil
    }

    // MARK: Reading

    func refresh() async {
        guard !isShowingFixture else { return }
        let paths = paths
        let known = libraryFingerprint
        let installed = library.installed
        let needsEngineSize = engineSize == nil
        let knownSizes = engineSizes
        let snapshot = await Task.detached {
            let reader = LibraryReader(paths: paths)
            let fingerprint = reader.fingerprint()
            let library = fingerprint == known ? nil : reader.read()
            var usage: [String: LayerUsage] = [:]
            for game in library?.installed ?? installed {
                usage[game.appID] = LayerUsage.lastRun(appID: game.appID, is32Bit: game.is32Bit, paths: paths)
            }
            // Wine engines, and which game uses which.
            let games = (library?.installed ?? installed).map(\.appID)
            let store = EngineStore(paths: paths)
            let fallback = store.defaultEngine()
            let pins = SteamConfig(paths: paths).compatTools().compactMapValues(EngineSpec.named(tool:))
            var gameEngines: [String: GameEngine] = [:]
            var copies: [String: EnvironmentCopy.Info] = [:]
            if let fallback {
                for appID in games {
                    let pin = pins[appID]
                    gameEngines[appID] = GameEngine(pin: pin, runsOn: pin.flatMap { store.isInstalled($0) ? $0 : nil } ?? fallback)
                    copies[appID] = EnvironmentCopy(paths: paths).info(appID: appID)
                }
            }
            // Fixed windows: where one is set, where one can be, and which games asked for a size they did not get.
            let window = FixedWindow(paths: paths)
            var fixedWindows: [String: FixedWindow.Size] = [:]
            var withEnvironment: Set<String> = []
            var running: Set<String> = []
            var refused: Set<String> = []
            // Only D3DMetal has Direct3D 12; with it on the Mac there is nothing to say.
            let d3dMetalIsAdded = D3DMetalLink(paths: paths).linkedVersion() != nil
            let neededDirect3D12 = d3dMetalIsAdded ? [] : Set(games.filter { GameLogSigns.neededDirect3D12(appID: $0, paths: paths) })
            for appID in games where window.hasEnvironment(appID: appID) {
                withEnvironment.insert(appID)
                fixedWindows[appID] = window.size(appID: appID)
                if window.isRunning(appID: appID) { running.insert(appID) }
                if GameLogSigns.refusedScreenSize(appID: appID, paths: paths) { refused.insert(appID) }
            }
            var sizes = knownSizes
            let rows = EngineSpec.all.map { spec in
                let isInstalled = store.isInstalled(spec)
                if isInstalled, sizes[spec.id] == nil { sizes[spec.id] = store.sizeOnDisk(spec) }
                return EngineRow(spec: spec, isInstalled: isInstalled, isDefault: spec == fallback,
                                 games: games.filter { gameEngines[$0]?.runsOn == spec }, size: isInstalled ? sizes[spec.id] : nil)
            }
            return (
                status: StatusReader(paths: paths).read(),
                fingerprint: fingerprint,
                library: library,
                engines: rows,
                engineSizes: sizes,
                gameEngines: gameEngines,
                copies: copies,
                fixedWindows: fixedWindows,
                withEnvironment: withEnvironment,
                running: running,
                refused: refused,
                neededDirect3D12: neededDirect3D12,
                logLines: LogReader(paths: paths).recentLines(),
                setup: Setup(paths: paths).states(),
                upkeep: Upkeep(paths: paths).plan(),
                usage: usage,
                engineSize: needsEngineSize ? Engine(paths: paths).sizeOnDisk() : nil
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
        if upkeep != snapshot.upkeep { upkeep = snapshot.upkeep }
        if layerUsage != snapshot.usage { layerUsage = snapshot.usage }
        if let size = snapshot.engineSize { engineSize = size }
        if engines != snapshot.engines { engines = snapshot.engines }
        engineSizes = snapshot.engineSizes
        if gameEngines != snapshot.gameEngines { gameEngines = snapshot.gameEngines }
        if environmentCopies != snapshot.copies { environmentCopies = snapshot.copies }
        if fixedWindows != snapshot.fixedWindows { fixedWindows = snapshot.fixedWindows }
        if gamesWithEnvironment != snapshot.withEnvironment { gamesWithEnvironment = snapshot.withEnvironment }
        if runningGames != snapshot.running { runningGames = snapshot.running }
        if refusedScreenSize != snapshot.refused { refusedScreenSize = snapshot.refused }
        if neededDirect3D12 != snapshot.neededDirect3D12 { neededDirect3D12 = snapshot.neededDirect3D12 }
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
        if selection == .steamPlay || selection == .renderers || selection == .logs { return }
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
        isShowingD3DMetalSheet = fixture.d3dMetalAdd != nil
        d3dMetalAdd = fixture.d3dMetalAdd ?? .idle
        wantedEngines = fixture.wantedEngines
        upkeep = fixture.upkeep
        upkeepProgress = fixture.upkeepProgress
        layerUsage = fixture.layerUsage
        engineSize = 1_300_000_000
        engines = fixture.engines
        engineProgress = fixture.engineProgress
        gameEngines = fixture.gameEngines
        environmentCopies = fixture.environmentCopies
        recentlyMoved = fixture.recentlyMoved
        fixedWindows = fixture.fixedWindows
        gamesWithEnvironment = fixture.gamesWithEnvironment
        runningGames = fixture.runningGames
        refusedScreenSize = fixture.refusedScreenSize
        neededDirect3D12 = fixture.neededDirect3D12
    }

    /// Goes back to what is really on this Mac.
    func showLiveData() async {
        isShowingFixture = false
        libraryFingerprint = nil
        setupProgress = nil
        isShowingSteamPlaySheet = false
        isShowingD3DMetalSheet = false
        d3dMetalAdd = .idle
        wantedEngines = [:]
        selection = nil
        upkeepProgress = nil
        engineSize = nil
        engineProgress = nil
        recentlyMoved = []
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

    /// Saves what a game's page holds. Settings go into the game's Steam launch options, for which Steam is quit
    /// first if it is open and reopened afterwards. The fixed window goes into the game's Windows environment,
    /// and Steam is left alone when nothing else changed.
    func save(_ settings: GameSettings, fixedWindow: FixedWindow.Size?, appID: String) async {
        let paths = paths
        await perform("Saving game settings") {
            let config = SteamConfig(paths: paths)
            let engine = EngineStore(paths: paths).engine(for: appID) ?? .newest
            let existing = config.launchOptions(appID: appID) ?? ""
            let options = settings.launchOptions(merging: existing, engine: engine)
            if options != existing {
                let wasRunning = SteamInstall(paths: paths).isRunning()
                if wasRunning { try SteamAddon(paths: paths).stopSteam() }
                defer { if wasRunning { try? SteamLauncher(paths: paths).openSteam() } }
                try config.setLaunchOptions(appID: appID, options)
            }
            let window = FixedWindow(paths: paths)
            if window.hasEnvironment(appID: appID), window.size(appID: appID) != fixedWindow {
                try window.set(fixedWindow, appID: appID)
            }
        }
    }

    /// Whether saving these settings will have to quit Steam.
    func savingNeedsSteamClosed(_ settings: GameSettings, game: LibraryGame) -> Bool {
        status?.steamRunning == true
            && settings.launchOptions(merging: game.launchOptions, engine: engine(for: game.appID)) != game.launchOptions
    }

    /// Gives a game a fixed window straight away, from the notice that suggests it.
    func useFixedWindow(_ size: FixedWindow.Size, appID: String) async {
        let paths = paths
        await perform("Setting a fixed window") {
            try FixedWindow(paths: paths).set(size, appID: appID)
        }
    }

    // MARK: D3DMetal

    var d3dMetalIsAdded: Bool { status?.d3dMetalVersion != nil }

    /// Installed games by the renderer that really draws them, whether it was chosen or Automatic came to it.
    func games(drawnBy renderer: GraphicsLayer) -> [LibraryGame] {
        let added = d3dMetalIsAdded
        return library.installed.filter {
            GraphicsLayer.drawing(chosen: $0.settings.layer, is32Bit: $0.is32Bit, toolkitAdded: added, lastRan: layerUsage[$0.appID]) == renderer
        }
    }

    func showD3DMetalSheet() {
        if case .failed = d3dMetalAdd { d3dMetalAdd = .idle }
        isShowingD3DMetalSheet = true
    }

    /// Adds D3DMetal from the user's own copy of Apple's Game Porting Toolkit, replacing a version that was
    /// there. The sheet stays up while this runs; it closes on success and shows the reason on failure.
    func addD3DMetal(from url: URL) async {
        guard !isBusy else { return }
        let paths = paths
        activity = "Adding D3DMetal"
        d3dMetalAdd = .checking(url.lastPathComponent)
        do {
            try await Task.detached { _ = try EngineStore(paths: paths).addD3DMetal(from: url) }.value
            activity = nil
            // What is on the Mac is read again first, so a page that was waiting for D3DMetal sees it arrive.
            await refresh()
            d3dMetalAdd = .idle
            isShowingD3DMetalSheet = false
        } catch {
            activity = nil
            d3dMetalAdd = .failed(String(describing: error))
            await refresh()
        }
    }

    /// Takes D3DMetal out again. No game's own choice is rewritten, so Steam stays open.
    func removeD3DMetal() async {
        let paths = paths
        await perform("Removing D3DMetal") {
            try EngineStore(paths: paths).removeD3DMetal()
        }
    }

    func showD3DMetalInFinder() {
        guard let toolkit = EngineStore(paths: paths).d3dMetal() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([toolkit.lib.deletingLastPathComponent()])
    }

    /// Does one thing the after-update step found. Failure leaves everything as it was and is shown on its row.
    func runUpkeep(_ item: Upkeep.Item) async {
        guard !isBusy else { return }
        let paths = paths
        activity = "Finishing the update"
        upkeepProgress = .working(item)
        do {
            try await Task.detached { try Upkeep(paths: paths).run(item) }.value
            upkeepProgress = .finished
        } catch {
            upkeepProgress = .failed(item, String(describing: error))
        }
        activity = nil
        await refresh()
    }

    /// Clears the "Everything is up to date" line once it has been seen.
    func dismissUpkeepResult() {
        if upkeepProgress == .finished { upkeepProgress = nil }
    }

    /// True while there is something for the Steam Play page's "After the Update" rows to show.
    var hasUpkeepToShow: Bool { !upkeep.isEmpty || upkeepProgress != nil }

    // MARK: Wine engines

    /// Does something that rewrites Steam's settings: Steam is quit first if it is open, and reopened afterwards.
    private func withSteamClosed(_ label: String, _ work: @escaping @Sendable () throws -> Void) async {
        let paths = paths
        await perform(label) {
            let wasRunning = SteamInstall(paths: paths).isRunning()
            if wasRunning { try SteamAddon(paths: paths).stopSteam() }
            defer { if wasRunning { try? SteamLauncher(paths: paths).openSteam() } }
            try work()
        }
    }

    /// Downloads and installs another Wine engine beside the present one. Can be paused and resumed.
    func installEngine(_ spec: EngineSpec) async {
        guard !isBusy else { return }
        let cancellation = Cancellation()
        self.cancellation = cancellation
        engineProgress = EngineProgress(spec: spec)
        let paths = paths
        let context = WorkContext(quiet: true, progress: { [weak self] progress in
            Task { @MainActor in
                guard self?.engineProgress?.spec == spec, self?.engineProgress?.isPaused == false else { return }
                self?.engineProgress?.download = progress
            }
        }, cancellation: cancellation)
        do {
            try await Task.detached { try EngineStore(paths: paths).install(spec, context) }.value
            engineProgress = nil
        } catch is Cancelled {
            engineProgress?.isPaused = true
        } catch {
            engineProgress = nil
            fail(error)
        }
        self.cancellation = nil
        await refresh()
    }

    /// Fetches a Wine version a game's page asked for. Steam stays open; the game only moves when the user says
    /// so afterwards, from the notice on its page.
    func fetchEngine(_ spec: EngineSpec, for appID: String) async {
        wantedEngines[appID] = spec
        await installEngine(spec)
    }

    /// Leaves a game where it is after all. The engine that was fetched for it stays installed.
    func forgetWantedEngine(for appID: String) {
        wantedEngines[appID] = nil
    }

    /// Makes an engine the default. Games that follow the default move with it, each with a copy kept first.
    func makeDefaultEngine(_ spec: EngineSpec) async {
        let paths = paths
        let games = library.installed.map(\.appID)
        let moving = Set(games.filter { gameEngines[$0]?.pin == nil })
        await withSteamClosed("Making \(spec.title) the default") {
            try GameMove(paths: paths).makeDefault(spec, games: games)
        }
        if engines.first(where: { $0.spec == spec })?.isDefault == true { recentlyMoved.formUnion(moving) }
    }

    /// Moves an engine to the Trash. Games pinned to it go back to the default first.
    func removeEngine(_ spec: EngineSpec) async {
        let paths = paths
        if engines.first(where: { $0.spec == spec })?.games.isEmpty == false {
            await withSteamClosed("Removing \(spec.title)") { try GameMove(paths: paths).remove(spec) }
        } else {
            await perform("Removing \(spec.title)") { try GameMove(paths: paths).remove(spec) }
        }
    }

    /// Pins a game to a Wine version, or with nil lets it follow the default again.
    func moveGame(_ appID: String, to spec: EngineSpec?) async {
        let paths = paths
        let before = gameEngines[appID]
        await withSteamClosed("Moving the game to \(spec?.title ?? "the default Wine version")") {
            try GameMove(paths: paths).move(appID: appID, to: spec)
        }
        if gameEngines[appID]?.runsOn != before?.runsOn { recentlyMoved.insert(appID) }
        wantedEngines[appID] = nil
    }

    /// Puts back the copy of a game's Windows environment made before it last moved.
    func restoreGame(_ appID: String) async {
        let paths = paths
        await withSteamClosed("Putting the Windows environment back") {
            try GameMove(paths: paths).restore(appID: appID)
        }
        recentlyMoved.remove(appID)
    }

    func showEngineInFinder(_ spec: EngineSpec) {
        NSWorkspace.shared.activateFileViewerSelecting([Engine(paths: paths, spec: spec).root])
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
        return LogReader(paths: paths).bugReport(status: status, games: library.installed)
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
                case .steam, .steamPlay: break
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
