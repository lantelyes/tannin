import Foundation

/// Everything the app's status screens show, read in one pass. Reading it changes nothing.
public struct TanninStatus: Sendable, Equatable {
    public var steamInstalled: Bool
    public var steamPlay: SteamAddon.State
    public var steamBuild: String?
    public var steamRunning: Bool
    public var steamIsValveSigned: Bool
    /// Whether the add-on reported its hooks installed the last time Steam started. Nil if it has never run.
    public var addonLoaded: Bool?
    public var updateFreeze: Bool
    public var engineInstalled: Bool
    public var engineWine: String
    public var d3dMetalVersion: String?
    public var bridgeVersion: String
    /// Problems with the runner, in plain words. Empty when it is complete.
    public var runnerProblems: [String]

    public init(steamInstalled: Bool, steamPlay: SteamAddon.State, steamBuild: String?, steamRunning: Bool,
                steamIsValveSigned: Bool, addonLoaded: Bool?, updateFreeze: Bool, engineInstalled: Bool,
                engineWine: String, d3dMetalVersion: String?, bridgeVersion: String, runnerProblems: [String]) {
        self.steamInstalled = steamInstalled
        self.steamPlay = steamPlay
        self.steamBuild = steamBuild
        self.steamRunning = steamRunning
        self.steamIsValveSigned = steamIsValveSigned
        self.addonLoaded = addonLoaded
        self.updateFreeze = updateFreeze
        self.engineInstalled = engineInstalled
        self.engineWine = engineWine
        self.d3dMetalVersion = d3dMetalVersion
        self.bridgeVersion = bridgeVersion
        self.runnerProblems = runnerProblems
    }

    /// "Wine 11.19, D3DMetal 4.0b3", or with DXMT when Apple's toolkit has not been added.
    public var stackSummary: String {
        "Wine \(engineWine), " + (d3dMetalVersion.map { "D3DMetal \($0)" } ?? "DXMT \(LayerStore.dxmtVersion)")
    }

    public enum Headline: Sendable, Equatable {
        case ready
        case steamPlayOff
        case steamUpdatedPastAddon
        case foreignTool(String)
        case setupIncomplete([String])
        case steamMissing
    }

    public var headline: Headline {
        guard steamInstalled else { return .steamMissing }
        var missing = runnerProblems
        if !engineInstalled { missing.insert("Wine isn’t installed", at: 0) }
        if !missing.isEmpty { return .setupIncomplete(missing) }
        switch steamPlay {
        case .off: return .steamPlayOff
        case let .foreign(value): return .foreignTool(value)
        case .on: return addonLoaded == false ? .steamUpdatedPastAddon : .ready
        }
    }
}

public struct StatusReader: Sendable {
    public let paths: Paths

    public init(paths: Paths = .live) { self.paths = paths }

    public func read() -> TanninStatus {
        let steam = SteamInstall(paths: paths)
        let engine = Engine(paths: paths)
        let runnerChecks = Runner(paths: paths).verify()
        let problems = runnerChecks
            .filter { $0.state == .broken && $0.name != "D3DMetal" }
            .map { "\($0.name): \($0.detail)" }
        return TanninStatus(
            steamInstalled: steam.isInstalled,
            steamPlay: SteamAddon(paths: paths).state(),
            steamBuild: steam.clientBuild(),
            steamRunning: steam.isRunning(),
            steamIsValveSigned: steam.signature().isValve,
            addonLoaded: LogReader(paths: paths).addonLoadedOnLastStart(),
            updateFreeze: UpdateFreeze(paths: paths).isOn,
            engineInstalled: engine.isInstalled,
            // The engine games use unless they are given another, which is the newest one unless the user chose.
            engineWine: EngineStore(paths: paths).defaultEngine()?.wine ?? Pins.engineWine,
            d3dMetalVersion: D3DMetalLink(paths: paths).linkedVersion(),
            bridgeVersion: Pins.notProtonVersion,
            runnerProblems: engine.isInstalled ? problems : []
        )
    }
}
