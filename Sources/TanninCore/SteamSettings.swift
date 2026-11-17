import Foundation

/// Stops Steam from updating itself at launch, so a new Steam build cannot switch Steam Play off unannounced.
public struct UpdateFreeze: Sendable {
    public let paths: Paths
    static let line = "BootStrapperInhibitUpdateOnLaunch=enable"

    public init(paths: Paths = .live) { self.paths = paths }

    var files: [URL] {
        var result = [paths.steamCfg]
        let inner = paths.steamInnerBundle.appending(path: "Contents/MacOS")
        if FileManager.default.fileExists(atPath: inner.path) { result.append(inner.appending(path: "steam.cfg")) }
        return result
    }

    public var isOn: Bool {
        files.contains { ((try? String(contentsOf: $0, encoding: .utf8)) ?? "").contains(Self.line) }
    }

    /// Adds or removes the one line, keeping anything else in the file. Removes the file if it ends up empty.
    public func set(_ on: Bool) throws {
        for file in files {
            let existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            var lines = existing.split(separator: "\n", omittingEmptySubsequences: true).map(String.init).filter { $0 != Self.line }
            if on { lines.append(Self.line) }
            if lines.isEmpty {
                try? FileManager.default.removeItem(at: file)
            } else {
                try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
            }
        }
    }
}

public enum SteamConfigError: Error, CustomStringConvertible {
    case steamRunning
    case unsafeRoundTrip(String)
    case noUser

    public var description: String {
        switch self {
        case .steamRunning: return "Quit Steam first: it rewrites its settings when it exits and would undo this change."
        case let .unsafeRoundTrip(file):
            return "\(file) does not survive being read and written back unchanged, so Tannin left it alone."
        case .noUser: return "No Steam user folder was found. Sign in to Steam once first."
        }
    }
}

/// Edits to Steam's own settings files. Each one is refused while Steam runs, backed up first,
/// and only written if reading the result back gives exactly the intended change and nothing else.
public struct SteamConfig: Sendable {
    public let paths: Paths

    public init(paths: Paths = .live) { self.paths = paths }

    static let mappingPath = ["InstallConfigStore", "Software", "Valve", "Steam", "CompatToolMapping"]

    /// Applies `change` to a VDF file with the safety checks described above.
    func edit(_ file: URL, _ change: (inout VDFValue) -> Void) throws {
        guard !SteamInstall(paths: paths).isRunning() else { throw SteamConfigError.steamRunning }
        let fm = FileManager.default
        let original = try VDF.load(file)
        // If our reader and writer cannot reproduce the file as it is, do not touch it.
        guard try VDF.parse(VDF.serialize(original)) == original else {
            throw SteamConfigError.unsafeRoundTrip(file.lastPathComponent)
        }
        var edited = original
        change(&edited)
        let text = VDF.serialize(edited)
        guard try VDF.parse(text) == edited else { throw SteamConfigError.unsafeRoundTrip(file.lastPathComponent) }

        try fm.createDirectory(at: paths.backups, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        // The short random suffix keeps two edits in the same second from colliding.
        let suffix = UUID().uuidString.prefix(8)
        try fm.copyItem(at: file, to: paths.backups.appending(path: "\(file.lastPathComponent).\(stamp)-\(suffix)"))
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    /// Tells Steam to run this game with Tannin's runner (or clears that choice).
    public func setCompatTool(appID: String, enabled: Bool) throws {
        try edit(paths.steamConfig) { vdf in
            let path = Self.mappingPath + [appID]
            if enabled {
                vdf.set(.object([
                    VDFPair("name", .string(Runner.toolName)),
                    VDFPair("config", .string("")),
                    VDFPair("priority", .string("250")),
                ]), at: path)
            } else {
                vdf.remove(at: path)
            }
        }
    }

    public func compatTool(appID: String) -> String? {
        (try? VDF.load(paths.steamConfig))?.value(at: Self.mappingPath + [appID, "name"])?.string
    }

    /// The signed-in user's settings file: the most recently changed one if several accounts have used this Mac.
    func localConfig() throws -> URL {
        let userdata = paths.steamData.appending(path: "userdata")
        let users = (try? FileManager.default.contentsOfDirectory(at: userdata, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let candidates = users.map { $0.appending(path: "config/localconfig.vdf") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        guard let newest = candidates.max(by: { modified($0) < modified($1) }) else { throw SteamConfigError.noUser }
        return newest
    }

    static func launchOptionsPath(_ appID: String) -> [String] {
        ["UserLocalConfigStore", "Software", "Valve", "Steam", "apps", appID, "LaunchOptions"]
    }

    public func launchOptions(appID: String) -> String? {
        guard let file = try? localConfig() else { return nil }
        return (try? VDF.load(file))?.value(at: Self.launchOptionsPath(appID))?.string
    }

    public func setLaunchOptions(appID: String, _ options: String) throws {
        try edit(try localConfig()) { vdf in
            if options.isEmpty {
                vdf.remove(at: Self.launchOptionsPath(appID))
            } else {
                vdf.set(.string(options), at: Self.launchOptionsPath(appID))
            }
        }
    }
}

/// How one game should run. Nil means "leave it to the default".
public struct GameSettings: Sendable, Equatable {
    public var rayTracing: Bool?
    public var metalFX: Bool?
    public var frameCap: Int?
    public var performanceHUD: Bool?
    public var metal4: Bool?

    public init(rayTracing: Bool? = nil, metalFX: Bool? = nil, frameCap: Int? = nil, performanceHUD: Bool? = nil, metal4: Bool? = nil) {
        self.rayTracing = rayTracing
        self.metalFX = metalFX
        self.frameCap = frameCap
        self.performanceHUD = performanceHUD
        self.metal4 = metal4
    }

    /// Variables Tannin owns in a game's launch options. Anything else the user typed there is kept.
    static let ownedKeys = ["CX_ACTIVE_GRAPHICS_BACKEND", "D3DM_SUPPORT_DXR", "D3DM_ENABLE_METALFX", "D3DM_MAX_FPS", "MTL_HUD_ENABLED", "D3DM_MTL4"]

    var assignments: [String] {
        var result = ["CX_ACTIVE_GRAPHICS_BACKEND=d3dmetal"]
        if let rayTracing { result.append("D3DM_SUPPORT_DXR=\(rayTracing ? 1 : 0)") }
        if let metalFX { result.append("D3DM_ENABLE_METALFX=\(metalFX ? 1 : 0)") }
        if let frameCap, frameCap > 0 { result.append("D3DM_MAX_FPS=\(frameCap)") }
        if let performanceHUD { result.append("MTL_HUD_ENABLED=\(performanceHUD ? 1 : 0)") }
        if let metal4 { result.append("D3DM_MTL4=\(metal4 ? 1 : 0)") }
        return result
    }

    /// Merges these settings into existing launch options: Tannin's variables are replaced, everything else stays.
    public func launchOptions(merging existing: String = "") -> String {
        var words = existing.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        words.removeAll { word in Self.ownedKeys.contains { word.hasPrefix("\($0)=") } }
        if !words.contains("%command%") { words.append("%command%") }
        return (assignments + words).joined(separator: " ")
    }
}
