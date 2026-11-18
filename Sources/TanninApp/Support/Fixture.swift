import Foundation
import TanninCore

/// Prepared data for one screen state, used only to take screenshots of states this Mac is not in.
/// Showing a fixture changes nothing outside the app.
struct Fixture {
    var status: TanninStatus
    var library: Library
    var logLines: [LogLine] = []
    var setup: [Setup.Step: Setup.State] = Fixture.setupDone
    var setupProgress: SetupProgress?
    var selection: SidebarSelection?
    var isShowingSteamPlaySheet = false
    /// What Tannin knows about its own updates; nil is a copy that cannot update itself.
    var updates: UpdateStatus?
    var upkeep: [Upkeep.Item] = []
    var upkeepProgress: UpkeepProgress?
    var layerUsage: [String: LayerUsage] = [:]
    var engines: [EngineRow] = Fixture.oneEngine
    var engineProgress: EngineProgress?
    var gameEngines: [String: GameEngine] = [:]
    var environmentCopies: [String: EnvironmentCopy.Info] = [:]
    var recentlyMoved: Set<String> = []
    var fixedWindows: [String: FixedWindow.Size] = [:]
    /// The fixtures' games have all been started, unless a scenario says otherwise.
    var gamesWithEnvironment: Set<String> = ["1544360", "50300"]
    var runningGames: Set<String> = []
    var refusedScreenSize: Set<String> = []
    var neededDirect3D12: Set<String> = []
    /// The Wine version a game's page fetched and the game has not moved to yet.
    var wantedEngines: [String: EngineSpec] = [:]
    /// Set to show the Add D3DMetal sheet, in this state.
    var d3dMetalAdd: D3DMetalAdd?

    /// Every drawn state of the main window, by the name its picture is saved under.
    static var mainWindowScenarios: [(name: String, fixture: Fixture)] {
        [
            ("game", Fixture(status: ready, library: library, selection: .game(lego.appID), layerUsage: [lego.appID: .d3dMetal])),
            ("game-d3dmetal", chosen("NOTPROTON_ENV_TANNIN_LAYER=d3dmetal D3DM_ENABLE_METALFX=1 D3DM_MAX_FPS=60 %command%", ran: .d3dMetal)),
            ("game-dxmt", chosen("NOTPROTON_RUNNER_VARIANT=tannin-dxmt DXMT_CONFIG=d3d11.preferredMaxFrameRate=60 %command%", ran: .dxmt)),
            ("game-dxvk", chosen("NOTPROTON_RUNNER_VARIANT=tannin-plain NOTPROTON_TANNIN_DXVK=1 DXVK_ASYNC=1 DXVK_FRAME_RATE=60 %command%", ran: nil)),
            ("game-never-run", Fixture(status: ready, library: library, selection: .game(lego.appID))),
            ("game-32-bit", thirtyTwoBit(ran: .dxmt)),
            ("game-direct3d-9", thirtyTwoBit(ran: .wineOwn)),
            ("game-no-toolkit", Fixture(status: noToolkit, library: Library(installed: [legoCapped], notInstalled: [silentHunter, specOps]),
                                        selection: .game(lego.appID), layerUsage: [lego.appID: .dxmt])),
            ("steam-play", Fixture(status: ready, library: library, selection: .steamPlay)),
            ("steam-play-off", Fixture(status: steamPlayOff, library: library, selection: .steamPlay)),
            ("steam-play-steam-moved", Fixture(status: steamUpdated, library: library, selection: .steamPlay)),
            ("steam-play-other-tool", Fixture(status: status(steamPlay: .foreign("/usr/local/lib/other.dylib")), library: library, selection: .steamPlay)),
            ("steam-play-setup-unfinished", Fixture(status: nothingInstalled, library: .empty, selection: .steamPlay, engines: noEngine)),
            ("steam-play-after-update", Fixture(status: ready, library: library, selection: .steamPlay, upkeep: [.graphicsLayers])),
            ("steam-play-after-update-working", Fixture(status: ready, library: library, selection: .steamPlay, upkeep: [.graphicsLayers],
                                                        upkeepProgress: .working(.graphicsLayers))),
            ("steam-play-after-update-finished", Fixture(status: ready, library: library, selection: .steamPlay, upkeepProgress: .finished)),
            ("steam-play-after-update-failed", Fixture(status: ready, library: library, selection: .steamPlay, upkeep: [.graphicsLayers],
                                                       upkeepProgress: .failed(.graphicsLayers, "A Windows game is running. Quit it first, then try again."))),
            ("after-update-sidebar", Fixture(status: ready, library: library, selection: .game(lego.appID), upkeep: [.graphicsLayers],
                                             layerUsage: [lego.appID: .d3dMetal])),
            ("renderers", Fixture(status: ready, library: threeGames, selection: .renderers, layerUsage: threeGamesUsage, engines: oneEngineThreeGames)),
            ("renderers-no-d3dmetal", Fixture(status: noToolkit, library: threeGames, selection: .renderers, layerUsage: threeGamesUsage,
                                              engines: oneEngineThreeGames)),
            ("renderers-downloading", Fixture(status: ready, library: library, selection: .renderers, engineProgress: downloading)),
            ("renderers-paused", Fixture(status: ready, library: library, selection: .renderers, engineProgress: paused)),
            ("renderers-two-engines", Fixture(status: ready, library: twoGames, selection: .renderers, engines: twoEngines)),
            ("renderers-setup-unfinished", Fixture(status: nothingInstalled, library: .empty, selection: .renderers, engines: noEngine)),
            ("d3dmetal-sheet", Fixture(status: noToolkit, library: library, selection: .renderers, d3dMetalAdd: .idle)),
            ("d3dmetal-sheet-checking", Fixture(status: noToolkit, library: library, selection: .renderers,
                                                d3dMetalAdd: .checking("Game_Porting_Toolkit_4.0_beta_3.dmg"))),
            ("d3dmetal-sheet-not-signed", Fixture(status: noToolkit, library: library, selection: .renderers,
                                                  d3dMetalAdd: .failed(GPTKError.notApple("").description))),
            ("d3dmetal-sheet-wrong-image", Fixture(status: noToolkit, library: library, selection: .renderers,
                                                   d3dMetalAdd: .failed(GPTKError.notAToolkit("").description))),
            ("d3dmetal-sheet-replace", Fixture(status: ready, library: library, selection: .renderers, d3dMetalAdd: .idle)),
            ("game-wine", wineVersion(pin: nil)),
            ("game-wine-pinned", wineVersion(pin: .wine1117)),
            ("game-wine-moved", wineVersion(pin: .wine1117, justMoved: true)),
            ("game-wine-removed", Fixture(status: ready, library: library, selection: .game(lego.appID), layerUsage: [lego.appID: .d3dMetal],
                                          gameEngines: [lego.appID: GameEngine(pin: .wine1117, runsOn: .wine1119)])),
            ("game-d3dmetal-removed", Fixture(status: noToolkit, library: Library(installed: [legoOnD3DMetal], notInstalled: [silentHunter, specOps]),
                                              selection: .game(lego.appID), layerUsage: [lego.appID: .dxmt])),
            ("game-needs-direct3d-12", Fixture(status: noToolkit, library: Library(installed: [legoCapped], notInstalled: [silentHunter, specOps]),
                                               selection: .game(lego.appID), neededDirect3D12: [lego.appID])),
            ("game-wine-fetching", Fixture(status: ready, library: library, selection: .game(lego.appID), layerUsage: [lego.appID: .d3dMetal],
                                           engineProgress: downloading, wantedEngines: [lego.appID: .wine1117])),
            ("game-wine-fetch-paused", Fixture(status: ready, library: library, selection: .game(lego.appID), layerUsage: [lego.appID: .d3dMetal],
                                               engineProgress: paused, wantedEngines: [lego.appID: .wine1117])),
            ("game-wine-arrived", Fixture(status: ready, library: library, selection: .game(lego.appID), layerUsage: [lego.appID: .d3dMetal],
                                          engines: twoEngines, gameEngines: [lego.appID: GameEngine(pin: nil, runsOn: .wine1119)],
                                          wantedEngines: [lego.appID: .wine1117])),
            ("game-fixed-window", fixedWindow(size: .usual)),
            ("game-fixed-window-off", fixedWindow(size: nil)),
            ("game-fixed-window-notice", fixedWindow(size: nil, refused: true)),
            ("game-fixed-window-never-started", fixedWindow(size: nil, started: false)),
            ("game-fixed-window-running", fixedWindow(size: .usual, running: true)),
            ("logs", Fixture(status: ready, library: library, logLines: log, selection: .logs)),
            ("empty", Fixture(status: ready, library: .empty, selection: nil)),
            ("not-installed", Fixture(status: ready, library: library, selection: .game(silentHunter.appID))),
            ("not-installed-no-toolkit", Fixture(status: noToolkit, library: library, selection: .game(silentHunter.appID))),
            ("attention", Fixture(status: steamUpdated, library: library, selection: .game(lego.appID))),
            ("sheet", Fixture(status: steamPlayOff, library: library, selection: .steamPlay, isShowingSteamPlaySheet: true)),
            ("update", Fixture(status: ready, library: library, selection: .game(lego.appID), updates: newer)),
            ("steam-moved-update", steamMoved(newer)),
            ("steam-moved-none", steamMoved(.upToDate)),
            ("steam-moved-checking", steamMoved(.checking)),
            ("steam-moved-failed", steamMoved(offline)),
        ]
    }

    /// The setup window: part-way through the download, waiting for its last step, and done.
    static var setupScenarios: [(name: String, fixture: Fixture)] {
        func setup(steamPlay: Setup.State) -> Fixture {
            Fixture(status: steamPlay.isDone ? ready : steamPlayOff, library: .empty, setup: [
                .rosetta: .done("Installed"), .steam: .done("In Applications"), .engine: .done("Wine 11.19"),
                .bridge: .done("NotProton 1.2.6"), .steamPlay: steamPlay,
            ])
        }
        return [
            ("setup", setupDownloading),
            ("setup-last-step", setup(steamPlay: .ready)),
            ("setup-done", setup(steamPlay: .done("On"))),
        ]
    }

    /// Every drawn state of the Updates group in Settings.
    static var settingsScenarios: [(name: String, updates: UpdateStatus?)] {
        [("plain", nil), ("up-to-date", .upToDate), ("checking", .checking), ("update", newer), ("failed", offline)]
    }

    /// The setup window part-way through the engine download.
    static var setupDownloading: Fixture {
        Fixture(
            status: steamPlayOff,
            library: .empty,
            setup: [
                .rosetta: .done("Installed"), .steam: .done("In Applications"), .engine: .ready,
                .bridge: .waiting("Needs the Wine engine first"), .steamPlay: .waiting("Needs the steps above first"),
            ],
            setupProgress: SetupProgress(
                step: .engine,
                download: DownloadProgress(name: Pins.engine.name, received: 312_000_000, total: Pins.engine.size, isVerifying: false)
            )
        )
    }

    // MARK: Pieces

    private static let setupDone: [Setup.Step: Setup.State] = [
        .rosetta: .done("Installed"), .steam: .done("In Applications"), .engine: .done("Wine 11.19"),
        .bridge: .done("NotProton 1.2.6"), .steamPlay: .done("On"),
    ]

    private static func status(steamPlay: SteamAddon.State = .on, addonLoaded: Bool? = true, d3dMetal: String? = "4.0b3",
                               engineInstalled: Bool = true) -> TanninStatus {
        TanninStatus(
            steamInstalled: true, steamPlay: steamPlay, steamBuild: "1794536281", steamRunning: false,
            steamIsValveSigned: steamPlay == .off, addonLoaded: addonLoaded, updateFreeze: steamPlay != .off, engineInstalled: engineInstalled,
            engineWine: Pins.engineWine, d3dMetalVersion: d3dMetal, bridgeVersion: Pins.notProtonVersion, runnerProblems: []
        )
    }

    /// The engine list as it is before a second engine is installed.
    static let oneEngine: [EngineRow] = [
        EngineRow(spec: .wine1119, isInstalled: true, isDefault: true, games: ["1544360"], size: 1_300_000_000),
        EngineRow(spec: .wine1117, isInstalled: false, isDefault: false, games: [], size: nil),
    ]

    /// The list on a Mac with three games, as the board draws it.
    private static let oneEngineThreeGames: [EngineRow] = [
        EngineRow(spec: .wine1119, isInstalled: true, isDefault: true, games: ["1544360", "15210", "50300"], size: 1_300_000_000),
        EngineRow(spec: .wine1117, isInstalled: false, isDefault: false, games: [], size: nil),
    ]

    /// Before setup has installed anything.
    private static let noEngine: [EngineRow] = [
        EngineRow(spec: .wine1119, isInstalled: false, isDefault: false, games: [], size: nil),
        EngineRow(spec: .wine1117, isInstalled: false, isDefault: false, games: [], size: nil),
    ]

    private static let downloading = EngineProgress(
        spec: .wine1117,
        download: DownloadProgress(name: Pins.engine1117.name, received: 212_000_000, total: Pins.engine1117.size, isVerifying: false))
    private static let paused = EngineProgress(
        spec: .wine1117,
        download: DownloadProgress(name: Pins.engine1117.name, received: 212_000_000, total: Pins.engine1117.size, isVerifying: false),
        isPaused: true)

    private static let twoEngines: [EngineRow] = [
        EngineRow(spec: .wine1119, isInstalled: true, isDefault: true, games: ["1544360"], size: 1_300_000_000),
        EngineRow(spec: .wine1117, isInstalled: true, isDefault: false, games: ["50300"], size: 1_280_000_000),
    ]

    /// The game page once a second engine is installed, with the game on the default or pinned.
    private static func wineVersion(pin: EngineSpec?, justMoved: Bool = false) -> Fixture {
        let copy = EnvironmentCopy.Info(made: Date(timeIntervalSince1970: 1_794_980_400), fromWine: "11.19", toWine: "11.17")
        return Fixture(status: ready, library: library, selection: .game(lego.appID), layerUsage: [lego.appID: .d3dMetal],
                       engines: twoEngines, gameEngines: [lego.appID: GameEngine(pin: pin, runsOn: pin ?? .wine1119)],
                       environmentCopies: pin == nil ? [:] : [lego.appID: copy], recentlyMoved: justMoved ? [lego.appID] : [])
    }

    /// An old Direct3D 9 game's page in each state of its Fixed Window row.
    private static func fixedWindow(size: FixedWindow.Size?, refused: Bool = false, started: Bool = true, running: Bool = false) -> Fixture {
        let game = silentHunterInstalled
        return Fixture(status: ready, library: Library(installed: [lego, game], notInstalled: [specOps]), selection: .game(game.appID),
                       layerUsage: started ? [game.appID: .wineOwn] : [:],
                       fixedWindows: size.map { [game.appID: $0] } ?? [:],
                       gamesWithEnvironment: started ? [lego.appID, game.appID] : [lego.appID],
                       runningGames: running ? [game.appID] : [],
                       refusedScreenSize: refused ? [game.appID] : [])
    }

    private static let ready = status()
    private static let steamUpdated = status(addonLoaded: false)
    private static let steamPlayOff = status(steamPlay: .off, addonLoaded: nil)
    private static let noToolkit = status(d3dMetal: nil)
    private static let nothingInstalled = status(steamPlay: .off, addonLoaded: nil, d3dMetal: nil, engineInstalled: false)

    /// The game page with a layer chosen by hand, and what the game last ran on.
    private static func chosen(_ options: String, ran: LayerUsage?) -> Fixture {
        let game = game(lego.appID, lego.name, install: .installed, size: lego.sizeOnDisk, options: options, is32Bit: false)
        return Fixture(status: ready, library: Library(installed: [game], notInstalled: [silentHunter, specOps]),
                       selection: .game(game.appID), layerUsage: ran.map { [game.appID: $0] } ?? [:])
    }

    private static func thirtyTwoBit(ran: LayerUsage) -> Fixture {
        Fixture(status: ready, library: Library(installed: [lego, specOpsInstalled], notInstalled: [silentHunter]),
                selection: .game(specOpsInstalled.appID), layerUsage: [specOpsInstalled.appID: ran])
    }

    private static let newer = UpdateStatus.available(version: "0.2.1")
    private static let offline = UpdateStatus.failed("This Mac appears to be offline.")

    private static func steamMoved(_ updates: UpdateStatus) -> Fixture {
        Fixture(status: steamUpdated, library: library, selection: .game(lego.appID), updates: updates)
    }

    /// Artwork comes from Steam's own cache on this Mac, when it has the game.
    private static func game(_ appID: String, _ name: String, install: LibraryGame.Install, size: Int64? = nil,
                             options: String = "", is32Bit: Bool? = nil) -> LibraryGame {
        LibraryGame(appID: appID, name: name, install: install, sizeOnDisk: size, launchOptions: options,
                    is32Bit: is32Bit, art: GameArt(appID: appID, paths: .live))
    }

    private static let lego = game("1544360", "LEGO® Builder's Journey", install: .installed, size: 4_322_970_119,
                                   options: "D3DM_ENABLE_METALFX=1 D3DM_MAX_FPS=60 DXMT_CONFIG=d3d11.preferredMaxFrameRate=60 %command%", is32Bit: false)
    private static let legoCapped = game("1544360", "LEGO® Builder's Journey", install: .installed, size: 4_322_970_119,
                                         options: "D3DM_MAX_FPS=60 DXMT_CONFIG=d3d11.preferredMaxFrameRate=60 %command%", is32Bit: false)
    private static let specOps = game("50300", "Spec Ops: The Line", install: .notInstalled)
    private static let specOpsInstalled = game("50300", "Spec Ops: The Line", install: .installed, size: 7_800_000_000, is32Bit: true)
    private static let silentHunter = game("15210", "Silent Hunter III", install: .notInstalled)
    private static let silentHunterInstalled = game("15210", "Silent Hunter III", install: .installed, size: 2_610_000_000, is32Bit: true)
    private static let legoOnD3DMetal = game("1544360", "LEGO® Builder's Journey", install: .installed, size: 4_322_970_119,
                                             options: "NOTPROTON_ENV_TANNIN_LAYER=d3dmetal D3DM_MAX_FPS=60 %command%", is32Bit: false)
    private static let library = Library(installed: [lego], notInstalled: [silentHunter, specOps])
    private static let threeGames = Library(installed: [lego, silentHunterInstalled, specOpsInstalled], notInstalled: [])
    /// One game on D3DMetal, one drawn by Wine itself, one on DXMT.
    private static let threeGamesUsage: [String: LayerUsage] = [lego.appID: .d3dMetal, silentHunterInstalled.appID: .wineOwn, specOpsInstalled.appID: .dxmt]
    private static let twoGames = Library(installed: [lego, specOpsInstalled], notInstalled: [silentHunter])

    private static let log: [LogLine] = [
        ("23:47:01", LogLine.Level.info, "loader", "notproton 1.2.6 starting in steam_osx"),
        ("23:47:01", .info, "resolver", "Steam build 1794536281, signature set 1794536281"),
        ("23:47:02", .info, "resolver", "18/18 signatures resolved"),
        ("23:47:02", .info, "tools", "registered notproton-tannin (tannin-1, rosetta)"),
        ("23:47:02", .info, "install_thread", "ready, 18/18 hooks installed"),
        ("23:47:09", .info, "compat", "wrote 5 file(s) to compatibilitytools.d/notproton-tannin"),
        ("23:52:40", .info, "launch", "app 1544360 starting with notproton-tannin"),
        ("23:52:41", .warning, "launch", "prefix template is older than the runner, rebuilding"),
        ("23:52:55", .info, "launch", "wineserver up, bridge steam.exe started"),
        ("23:52:58", .info, "bridge", "lsteamclient.dll loaded after steamclient64.dll"),
        ("23:53:01", .info, "launch", "app 1544360 running"),
        ("00:41:17", .info, "launch", "app 1544360 exited with status 0"),
    ].enumerated().map { index, line in
        LogLine(id: index, time: line.0, level: line.1, source: line.2, message: line.3)
    }
}
