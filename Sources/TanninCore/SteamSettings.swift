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
    /// How to tell whether Steam is running. Replaceable so tests on a fixture folder don't depend on the real Steam.
    let steamIsRunning: @Sendable () -> Bool

    public init(paths: Paths = .live) {
        self.paths = paths
        self.steamIsRunning = { SteamInstall(paths: paths).isRunning() }
    }

    init(paths: Paths, steamIsRunning: @escaping @Sendable () -> Bool) {
        self.paths = paths
        self.steamIsRunning = steamIsRunning
    }

    static let mappingPath = ["InstallConfigStore", "Software", "Valve", "Steam", "CompatToolMapping"]

    /// Applies `change` to a VDF file with the safety checks described above.
    func edit(_ file: URL, _ change: (inout VDFValue) -> Void) throws {
        guard !steamIsRunning() else { throw SteamConfigError.steamRunning }
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
        try setCompatTool(appID: appID, tool: enabled ? Runner.toolName : nil)
    }

    /// Tells Steam which compatibility tool runs this game. Nil clears the choice, so the game uses the default.
    public func setCompatTool(appID: String, tool: String?) throws {
        try edit(paths.steamConfig) { vdf in
            let path = Self.mappingPath + [appID]
            if let tool {
                vdf.set(.object([
                    VDFPair("name", .string(tool)),
                    VDFPair("config", .string("")),
                    VDFPair("priority", .string("250")),
                ]), at: path)
            } else {
                vdf.remove(at: path)
            }
        }
    }

    /// The tool chosen for each app that has one.
    public func compatTools() -> [String: String] {
        var result: [String: String] = [:]
        for pair in (try? VDF.load(paths.steamConfig))?.value(at: Self.mappingPath)?.pairs ?? [] {
            if let name = pair.value["name"]?.string, !name.isEmpty { result[pair.key] = name }
        }
        return result
    }

    public func compatTool(appID: String) -> String? {
        (try? VDF.load(paths.steamConfig))?.value(at: Self.mappingPath + [appID, "name"])?.string
    }

    /// Every app the user has chosen a compatibility tool for.
    public func compatToolAppIDs() -> Set<String> {
        Set((try? VDF.load(paths.steamConfig))?.value(at: Self.mappingPath)?.pairs.map(\.key) ?? [])
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

    /// Launch options for every app that has any, read in one pass.
    public func allLaunchOptions() -> [String: String] { appSettings().launchOptions }

    /// Minutes played, as Steam counts them, for every app that has been played.
    public func playtimes() -> [String: Int] { appSettings().minutesPlayed }

    /// What the signed-in user's settings file says about each app, read in one pass over the file.
    func appSettings() -> (launchOptions: [String: String], minutesPlayed: [String: Int]) {
        guard let file = try? localConfig(), let vdf = try? VDF.load(file) else { return ([:], [:]) }
        let apps = vdf.value(at: Array(Self.launchOptionsPath("").dropLast(2)))?.pairs ?? []
        var options: [String: String] = [:]
        var minutes: [String: Int] = [:]
        for app in apps {
            if let text = app.value["LaunchOptions"]?.string, !text.isEmpty { options[app.key] = text }
            if let played = app.value["Playtime"]?.string.flatMap(Int.init), played > 0 { minutes[app.key] = played }
        }
        return (options, minutes)
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
