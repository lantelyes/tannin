import Foundation

public enum EngineStoreError: Error, CustomStringConvertible {
    case isTheDefault(String)
    case isTheOnlyOne
    case notInstalled(String)
    case gameRunning
    case isTheNewest(String)

    public var description: String {
        switch self {
        case let .isTheDefault(name): return "\(name) is the default. Make another engine the default first."
        case .isTheOnlyOne: return "This is the only Wine engine installed."
        case let .notInstalled(name): return "\(name) is not installed."
        case .gameRunning: return "A Windows game is running. Quit it first, then try again."
        case let .isTheNewest(name): return "\(name) is the engine Tannin sets up, so it stays."
        }
    }
}

/// The Wine engines on this Mac: which are installed, which one games use by default, and which games are
/// pinned to which. An engine only counts as installed once its runner is built, since that is what Steam uses.
public struct EngineStore: Sendable {
    public let paths: Paths
    let gameIsRunning: @Sendable () -> Bool
    let disposal: Disposal

    public init(paths: Paths = .live) {
        self.init(paths: paths, gameIsRunning: { WindowsGames.anyRunning(paths: paths) }, disposal: .trash)
    }

    init(paths: Paths, gameIsRunning: @escaping @Sendable () -> Bool, disposal: Disposal) {
        self.paths = paths
        self.gameIsRunning = gameIsRunning
        self.disposal = disposal
    }

    public func isInstalled(_ spec: EngineSpec) -> Bool {
        Engine(paths: paths, spec: spec).isInstalled && Runner(paths: paths, spec: spec).exists
    }

    /// Installed engines, newest first.
    public func installed() -> [EngineSpec] { EngineSpec.all.filter(isInstalled) }

    /// The engine a game gets when it has none of its own: the first one the add-on is told about.
    public func defaultEngine() -> EngineSpec? {
        let listed = Runner.listedTools(paths: paths).compactMap(EngineSpec.named(tool:)).filter(isInstalled)
        return listed.first ?? installed().first
    }

    /// The engine a game is pinned to, or nil when it follows the default. A pin to an engine that is no longer
    /// installed still counts as a pin, so the app can say so.
    public func pin(appID: String) -> EngineSpec? {
        SteamConfig(paths: paths).compatTool(appID: appID).flatMap(EngineSpec.named(tool:))
    }

    /// The engine a game will really run on.
    public func engine(for appID: String) -> EngineSpec? {
        if let pinned = pin(appID: appID), isInstalled(pinned) { return pinned }
        return defaultEngine()
    }

    /// The app IDs pinned to this engine.
    public func pinnedGames(_ spec: EngineSpec) -> [String] {
        SteamConfig(paths: paths).compatTools().filter { $0.value == spec.toolName }.map(\.key).sorted()
    }

    public func sizeOnDisk(_ spec: EngineSpec) -> Int64? { Engine(paths: paths, spec: spec).sizeOnDisk() }

    /// Downloads, checks and unpacks an engine, builds its runner and lists it for Steam. It does not become
    /// the default. Steam has to start again before it shows the new tool.
    public func install(_ spec: EngineSpec, _ context: WorkContext = .terminal) throws {
        try Engine(paths: paths, spec: spec).install(context)
        try context.cancellation?.check()
        try Runner(paths: paths, spec: spec).build(patch: NtdllPatch(paths: paths, spec: spec))
        if let toolkit = try? GPTK(paths: paths).current() {
            try D3DMetalLink(paths: paths, spec: spec).link(toolkit)
        }
        try InstallRecord.write(paths: paths)
    }

    /// Puts the imported D3DMetal into every installed engine's runner. One D3DMetal at a time, for all of them.
    public func linkToolkit(_ toolkit: GPTK.Imported) throws {
        for spec in installed() { try D3DMetalLink(paths: paths, spec: spec).link(toolkit) }
        try InstallRecord.write(paths: paths)
    }

    /// Takes D3DMetal out of every installed engine's runner.
    public func unlinkToolkit() throws {
        for spec in installed() { try D3DMetalLink(paths: paths, spec: spec).unlink() }
        try InstallRecord.write(paths: paths)
    }

    // MARK: D3DMetal, the one renderer that does not come inside Wine

    /// The version of D3DMetal on this Mac, if it has been added.
    public func d3dMetal() -> GPTK.Imported? { GPTK(paths: paths).imported().last }

    /// Adds D3DMetal from the user's own copy of Apple's Game Porting Toolkit, after checking Apple's
    /// signature, and puts it to use in every installed engine. A version that was there before is replaced.
    @discardableResult
    public func addD3DMetal(from source: URL) throws -> GPTK.Imported {
        guard !gameIsRunning() else { throw EngineStoreError.gameRunning }
        let toolkit = try GPTK(paths: paths).importToolkit(from: source)
        try adopt(toolkit)
        return toolkit
    }

    /// Makes an imported version the only one, in use by every installed engine.
    func adopt(_ toolkit: GPTK.Imported) throws {
        try GPTK(paths: paths).retireOthers(keeping: toolkit, disposal: disposal)
        try linkToolkit(toolkit)
    }

    /// Takes D3DMetal out of every engine and gets rid of Tannin's copy. Games then run on DXMT. No game's own
    /// choice is rewritten, so Steam can stay open.
    public func removeD3DMetal() throws {
        guard !gameIsRunning() else { throw EngineStoreError.gameRunning }
        try unlinkToolkit()
        try GPTK(paths: paths).removeAll(disposal: disposal)
    }

    public func makeDefault(_ spec: EngineSpec) throws {
        guard isInstalled(spec) else { throw EngineStoreError.notInstalled(spec.title) }
        try Runner(paths: paths, spec: spec).makeDefault()
    }

    /// Moves an engine and everything built from it to the Trash. Games pinned to it have to be moved first.
    public func remove(_ spec: EngineSpec) throws {
        guard spec != .newest else { throw EngineStoreError.isTheNewest(spec.title) }
        guard installed().count > 1 else { throw EngineStoreError.isTheOnlyOne }
        guard defaultEngine() != spec else { throw EngineStoreError.isTheDefault(spec.title) }
        let fm = FileManager.default
        let runner = Runner(paths: paths, spec: spec)
        try runner.removeToolsLine()
        try LayerStore(paths: paths, spec: spec).remove()
        let leftovers = [
            Engine(paths: paths, spec: spec).root,
            runner.root.deletingLastPathComponent(),
            NtdllPatch(paths: paths, spec: spec).output(arch: "x86_64").deletingLastPathComponent().deletingLastPathComponent(),
            runner.stagedNtdll,
            runner.defaultsFile,
            paths.downloads.appending(path: spec.pin.name),
        ]
        for url in leftovers where fm.fileExists(atPath: url.path) {
            try fm.trashItem(at: url, resultingItemURL: nil)
        }
        try InstallRecord.write(paths: paths)
    }
}
