import TanninCore

/// One line of the Engine page's list of Wine engines.
struct EngineRow: Equatable, Identifiable {
    var spec: EngineSpec
    var isInstalled: Bool
    var isDefault: Bool
    /// Installed games that run on it: those pinned to it, and for the default those that follow the default.
    var games: [String]
    var size: Int64?

    var id: String { spec.id }
}

/// A Wine engine that is downloading or paused.
struct EngineProgress: Equatable {
    var spec: EngineSpec
    var download: DownloadProgress?
    var isPaused = false
}

/// Which Wine engine one game uses.
struct GameEngine: Equatable {
    /// The engine it is pinned to, or nil when it follows the default.
    var pin: EngineSpec?
    /// The engine it really runs on.
    var runsOn: EngineSpec
    /// False when it is pinned to an engine that has been removed.
    var pinIsInstalled: Bool { pin == nil || pin == runsOn }
}
