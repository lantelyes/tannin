import Foundation

public enum UpkeepError: Error, CustomStringConvertible {
    case gameRunning

    public var description: String {
        switch self {
        case .gameRunning: return "A Windows game is running. Quit it first, then try again."
        }
    }
}

/// Whether a Windows game is running. What it runs from must not be changed underneath it.
public enum WindowsGames {
    public static func anyRunning(paths: Paths = .live) -> Bool {
        // A game runs from the add-on's per-game copy of the runner, or from the runner itself.
        let folders = [paths.notproton.appending(path: "launchers").path, paths.notproton.appending(path: "runners").path]
        return (try? Shell.run("/usr/bin/pgrep", ["-f", folders.joined(separator: "|")]))?.ok ?? false
    }
}

/// Brings what an earlier Tannin installed up to what this one expects, after Tannin has updated itself.
/// Nothing here runs by itself: `plan()` only looks, and each item is done when the user asks for it.
public struct Upkeep: Sendable {
    public enum Item: String, Sendable, CaseIterable, Identifiable {
        /// The runner was built by Tannin 0.2: no DXMT in it, no per-game layer files, no 32-bit Steam bridge.
        case graphicsLayers

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .graphicsLayers: "Renderers are ready to add"
            }
        }

        public var detail: String {
            switch self {
            case .graphicsLayers:
                "Adds DXMT and the Steam bridge for 32-bit games, and the choice of renderer on each game's page. Nothing is downloaded and Steam is not changed."
            }
        }

        public var action: String {
            switch self {
            case .graphicsLayers: "Add"
            }
        }

        /// Whether Steam has to be closed while this is done.
        public var needsSteamClosed: Bool {
            switch self {
            case .graphicsLayers: false
            }
        }
    }

    public let paths: Paths
    let gameIsRunning: @Sendable () -> Bool

    public init(paths: Paths = .live) {
        self.init(paths: paths) { WindowsGames.anyRunning(paths: paths) }
    }

    init(paths: Paths, gameIsRunning: @escaping @Sendable () -> Bool) {
        self.paths = paths
        self.gameIsRunning = gameIsRunning
    }

    /// What is behind. Empty when there is nothing to do, and when nothing has been installed at all
    /// (that is first-run setup's business, not this).
    public func plan() -> [Item] {
        let runner = Runner(paths: paths)
        guard Engine(paths: paths).isInstalled,
              FileManager.default.fileExists(atPath: runner.root.appending(path: "lib/wine").path) else { return [] }
        let checks = runner.verify()
        // A runner with something broken needs setup's Steam bridge step, which rebuilds it in full.
        guard !checks.contains(where: { $0.state == .broken }) else { return [] }
        let behind = checks.contains { $0.state == .attention && ($0.name == Runner.layersCheck || $0.name.hasPrefix("ntdll")) }
        return behind ? [.graphicsLayers] : []
    }

    /// Does one item. On failure the runner is left as it was.
    public func run(_ item: Item) throws {
        switch item {
        case .graphicsLayers:
            guard !gameIsRunning() else { throw UpkeepError.gameRunning }
            try rebuildRunner()
        }
    }

    /// Builds the runner again from the engine and the staged bridge, keeping the old one until the new one
    /// has passed its checks.
    private func rebuildRunner() throws {
        let fm = FileManager.default
        let runner = Runner(paths: paths)
        let kept = runner.root.deletingLastPathComponent().appendingPathExtension("before-upkeep")
        try? fm.removeItem(at: kept)
        try Shell.check("/bin/cp", ["-c", "-R", runner.root.deletingLastPathComponent().path, kept.path])
        do {
            try runner.build(patch: NtdllPatch(paths: paths))
            if let toolkit = try? GPTK(paths: paths).current() { try D3DMetalLink(paths: paths).link(toolkit) }
            let broken = runner.verify().filter { $0.state == .broken }
            if let first = broken.first { throw RunnerError.kitIncomplete(["\(first.name): \(first.detail)"]) }
            try InstallRecord.write(paths: paths)
            try? fm.removeItem(at: kept)
        } catch {
            // Put the old runner back exactly as it was.
            try? fm.removeItem(at: runner.root.deletingLastPathComponent())
            try? fm.moveItem(at: kept, to: runner.root.deletingLastPathComponent())
            // The layer files were written for the new runner. Without DXMT in the old one they have no use.
            let layers = LayerStore(paths: paths)
            if layers.runnerHasDXMT(runner.root, arch: "i386") { try? layers.prepare() } else { try? layers.remove() }
            throw error
        }
    }
}
