import Foundation

public enum EnvironmentCopyError: Error, CustomStringConvertible {
    case noEnvironment
    case noCopy

    public var description: String {
        switch self {
        case .noEnvironment: return "This game doesn’t have a Windows environment yet. Steam creates one the first time you play it."
        case .noCopy: return "There’s no backup of this game’s Windows environment to restore."
        }
    }
}

/// A copy of one game's Windows environment (its Wine prefix: settings, and for some games their saves), made
/// before the game moves to another Wine version so the move can be undone. One copy is kept per game, the newest.
/// Copies are APFS clones, so they take almost no room until the game changes its files.
public struct EnvironmentCopy: Sendable {
    public struct Info: Codable, Sendable, Equatable {
        public var made: Date
        /// The Wine version the game was on when the copy was made, and the one it was moving to.
        public var fromWine: String
        public var toWine: String

        public init(made: Date, fromWine: String, toWine: String) {
            self.made = made
            self.fromWine = fromWine
            self.toWine = toWine
        }
    }

    public let paths: Paths

    public init(paths: Paths = .live) { self.paths = paths }

    /// The game's Windows environment in Steam's library, if it has one.
    public func environment(appID: String) -> URL? {
        SteamInstall(paths: paths).libraries()
            .map { $0.appending(path: "steamapps/compatdata/\(appID)") }
            .first { FileManager.default.fileExists(atPath: $0.appending(path: "pfx").path) }
    }

    private func folder(_ appID: String) -> URL { paths.environments.appending(path: appID) }
    private func copy(_ appID: String) -> URL { folder(appID).appending(path: "compatdata") }
    private func infoFile(_ appID: String) -> URL { folder(appID).appending(path: "copy.json") }

    /// What is known about the game's copy, or nil when there is none.
    public func info(appID: String) -> Info? {
        guard FileManager.default.fileExists(atPath: copy(appID).path),
              let data = try? Data(contentsOf: infoFile(appID)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Info.self, from: data)
    }

    /// Copies the game's environment, replacing an older copy. A game that has never been started has nothing
    /// to copy, which is not an error: it returns nil.
    @discardableResult
    public func make(appID: String, from: EngineSpec, to: EngineSpec, now: Date = Date()) throws -> Info? {
        guard let environment = environment(appID: appID) else { return nil }
        let fm = FileManager.default
        try fm.createDirectory(at: folder(appID), withIntermediateDirectories: true)
        let fresh = folder(appID).appending(path: ".copy-\(UUID().uuidString)")
        try Shell.check("/bin/cp", ["-c", "-R", environment.path, fresh.path])
        if fm.fileExists(atPath: copy(appID).path) { try fm.removeItem(at: copy(appID)) }
        try fm.moveItem(at: fresh, to: copy(appID))
        let info = Info(made: now, fromWine: from.wine, toWine: to.wine)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(info).write(to: infoFile(appID), options: .atomic)
        return info
    }

    /// Puts the copy back in place of the game's present environment, which goes to the Trash.
    /// The copy itself is kept.
    public func restore(appID: String) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: copy(appID).path) else { throw EnvironmentCopyError.noCopy }
        let library = SteamInstall(paths: paths).libraries().first {
            fm.fileExists(atPath: $0.appending(path: "steamapps/compatdata/\(appID)").path)
        } ?? paths.steamData
        let place = library.appending(path: "steamapps/compatdata/\(appID)")
        let fresh = place.deletingLastPathComponent().appending(path: ".restore-\(appID)-\(UUID().uuidString)")
        try fm.createDirectory(at: place.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Shell.check("/bin/cp", ["-c", "-R", copy(appID).path, fresh.path])
        if fm.fileExists(atPath: place.path) { try fm.trashItem(at: place, resultingItemURL: nil) }
        try fm.moveItem(at: fresh, to: place)
    }

    public func remove(appID: String) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: folder(appID).path) { try fm.removeItem(at: folder(appID)) }
    }
}

/// Moves a game from one Wine engine to another. Steam has to be closed: its settings are rewritten.
public struct GameMove: Sendable {
    public let paths: Paths
    let steamIsRunning: @Sendable () -> Bool

    public init(paths: Paths = .live) {
        self.init(paths: paths) { SteamInstall(paths: paths).isRunning() }
    }

    init(paths: Paths, steamIsRunning: @escaping @Sendable () -> Bool) {
        self.paths = paths
        self.steamIsRunning = steamIsRunning
    }

    private var config: SteamConfig { SteamConfig(paths: paths, steamIsRunning: steamIsRunning) }

    /// Pins the game to an engine, or with nil lets it follow the default again. The game's Windows environment
    /// is copied first, and its launch options are rewritten for the new engine's layer files.
    public func move(appID: String, to target: EngineSpec?, now: Date = Date()) throws {
        let store = EngineStore(paths: paths)
        guard !steamIsRunning() else { throw SteamConfigError.steamRunning }
        guard let from = store.engine(for: appID) else { throw EngineStoreError.isTheOnlyOne }
        if let target, !store.isInstalled(target) { throw EngineStoreError.notInstalled(target.title) }
        guard let destination = target ?? store.defaultEngine() else { throw EngineStoreError.isTheOnlyOne }

        if destination != from {
            try EnvironmentCopy(paths: paths).make(appID: appID, from: from, to: destination, now: now)
        }
        try config.setCompatTool(appID: appID, tool: target?.toolName)
        let existing = config.launchOptions(appID: appID) ?? ""
        let rewritten = GameSettings(parsing: existing).launchOptions(merging: existing, engine: destination)
        if rewritten != existing { try config.setLaunchOptions(appID: appID, rewritten) }
    }

    /// Makes another engine the default. Every game that follows the default moves with it, so each of `games`
    /// that is not pinned gets its copy first and has its launch options rewritten for the new engine.
    public func makeDefault(_ target: EngineSpec, games: [String], now: Date = Date()) throws {
        let store = EngineStore(paths: paths)
        guard !steamIsRunning() else { throw SteamConfigError.steamRunning }
        guard store.isInstalled(target) else { throw EngineStoreError.notInstalled(target.title) }
        guard let from = store.defaultEngine(), from != target else { return }
        for appID in games where store.pin(appID: appID) == nil {
            try EnvironmentCopy(paths: paths).make(appID: appID, from: from, to: target, now: now)
            let existing = config.launchOptions(appID: appID) ?? ""
            let rewritten = GameSettings(parsing: existing).launchOptions(merging: existing, engine: target)
            if rewritten != existing { try config.setLaunchOptions(appID: appID, rewritten) }
        }
        try store.makeDefault(target)
    }

    /// Removes an engine. Games pinned to it go back to the default first, each with its copy.
    public func remove(_ spec: EngineSpec, now: Date = Date()) throws {
        let store = EngineStore(paths: paths)
        let pinned = store.pinnedGames(spec)
        if !pinned.isEmpty {
            guard !steamIsRunning() else { throw SteamConfigError.steamRunning }
            guard store.defaultEngine() != spec else { throw EngineStoreError.isTheDefault(spec.title) }
            for appID in pinned { try move(appID: appID, to: nil, now: now) }
        }
        try store.remove(spec)
    }

    /// Puts back the copy made before the game last moved, and the Wine version it was on then.
    public func restore(appID: String) throws {
        let copies = EnvironmentCopy(paths: paths)
        guard let info = copies.info(appID: appID) else { throw EnvironmentCopyError.noCopy }
        guard !steamIsRunning() else { throw SteamConfigError.steamRunning }
        let store = EngineStore(paths: paths)
        try copies.restore(appID: appID)
        // Back to the engine the copy belongs to, when that engine is still here.
        if let engine = EngineSpec.all.first(where: { $0.wine == info.fromWine }), store.isInstalled(engine) {
            try config.setCompatTool(appID: appID, tool: engine == store.defaultEngine() ? nil : engine.toolName)
            let existing = config.launchOptions(appID: appID) ?? ""
            let rewritten = GameSettings(parsing: existing).launchOptions(merging: existing, engine: engine)
            if rewritten != existing { try config.setLaunchOptions(appID: appID, rewritten) }
        }
    }
}
