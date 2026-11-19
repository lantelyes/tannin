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

    /// "Downloading. 212 MB of 461 MB.", with the words to begin with left to the place that shows it.
    func caption(working: String = "Downloading") -> String {
        guard let download else { return isPaused ? "Paused." : "Starting…" }
        if download.isVerifying { return "Verifying and unpacking the download…" }
        let received = download.received.megabytes
        let amount = download.total.map { "\(received) of \($0.megabytes)" } ?? received
        return isPaused ? "Paused at \(amount)." : "\(working). \(amount)."
    }

    /// How far along it is, while there is a bar to draw.
    var fraction: Double? {
        guard let fraction = download?.fraction, download?.isVerifying == false || isPaused else { return nil }
        return fraction
    }
}

extension EngineSpec {
    /// "461 MB", for an engine that is not installed.
    var downloadSize: String { (pin.size ?? 0).megabytes }
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
