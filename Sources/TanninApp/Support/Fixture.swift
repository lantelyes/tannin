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
            ("engine", Fixture(status: ready, library: library, selection: .engine)),
            ("engine-no-toolkit", Fixture(status: noToolkit, library: library, selection: .engine)),
            ("engine-after-update", Fixture(status: ready, library: library, selection: .engine, upkeep: [.graphicsLayers])),
            ("engine-after-update-working", Fixture(status: ready, library: library, selection: .engine, upkeep: [.graphicsLayers],
                                                    upkeepProgress: .working(.graphicsLayers))),
            ("engine-after-update-finished", Fixture(status: ready, library: library, selection: .engine, upkeepProgress: .finished)),
            ("engine-after-update-failed", Fixture(status: ready, library: library, selection: .engine, upkeep: [.graphicsLayers],
                                                   upkeepProgress: .failed(.graphicsLayers, "A Windows game is running. Quit it first, then try again."))),
            ("after-update-sidebar", Fixture(status: ready, library: library, selection: .game(lego.appID), upkeep: [.graphicsLayers],
                                             layerUsage: [lego.appID: .d3dMetal])),
            ("logs", Fixture(status: ready, library: library, logLines: log, selection: .logs)),
            ("empty", Fixture(status: ready, library: .empty, selection: nil)),
            ("not-installed", Fixture(status: ready, library: library, selection: .game(silentHunter.appID))),
            ("not-installed-no-toolkit", Fixture(status: noToolkit, library: library, selection: .game(silentHunter.appID))),
            ("attention", Fixture(status: steamUpdated, library: library, selection: .game(lego.appID))),
            ("sheet", Fixture(status: steamPlayOff, library: library, selection: .engine, isShowingSteamPlaySheet: true)),
            ("update", Fixture(status: ready, library: library, selection: .game(lego.appID), updates: newer)),
            ("steam-moved-update", steamMoved(newer)),
            ("steam-moved-none", steamMoved(.upToDate)),
            ("steam-moved-checking", steamMoved(.checking)),
            ("steam-moved-failed", steamMoved(offline)),
        ]
    }

    /// The setup window in each state of the toolkit step.
    static var setupScenarios: [(name: String, fixture: Fixture)] {
        func setup(_ toolkit: Setup.State) -> Fixture {
            Fixture(status: toolkit.isDone ? steamPlayOff : noToolkitOff, library: .empty, setup: [
                .rosetta: .done("Installed"), .steam: .done("In Applications"), .engine: .done("Wine 11.19"), .toolkit: toolkit,
                .bridge: .done("NotProton 1.2.6"), .steamPlay: .ready,
            ])
        }
        return [
            ("setup", setupDownloading),
            ("setup-toolkit", setup(.ready)),
            ("setup-toolkit-skipped", setup(.skipped("Skipped. Games use DXMT. You can add it later on the Engine page."))),
            ("setup-toolkit-added", setup(.done("D3DMetal 4.0b3"))),
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
                .rosetta: .done("Installed"), .steam: .done("In Applications"), .engine: .ready, .toolkit: .ready,
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
        .toolkit: .done("D3DMetal 4.0b3"), .bridge: .done("NotProton 1.2.6"), .steamPlay: .done("On"),
    ]

    private static func status(steamPlay: SteamAddon.State = .on, addonLoaded: Bool? = true, d3dMetal: String? = "4.0b3") -> TanninStatus {
        TanninStatus(
            steamInstalled: true, steamPlay: steamPlay, steamBuild: "1794536281", steamRunning: false,
            steamIsValveSigned: steamPlay == .off, addonLoaded: addonLoaded, updateFreeze: true, engineInstalled: true,
            engineWine: Pins.engineWine, d3dMetalVersion: d3dMetal, bridgeVersion: Pins.notProtonVersion, runnerProblems: []
        )
    }

    private static let ready = status()
    private static let steamUpdated = status(addonLoaded: false)
    private static let steamPlayOff = status(steamPlay: .off, addonLoaded: nil)
    private static let noToolkit = status(d3dMetal: nil)
    private static let noToolkitOff = status(steamPlay: .off, addonLoaded: nil, d3dMetal: nil)

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
    private static let library = Library(installed: [lego], notInstalled: [silentHunter, specOps])

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
