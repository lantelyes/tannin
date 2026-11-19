import Foundation

public enum FixedWindowError: Error, CustomStringConvertible {
    case noEnvironment
    case gameRunning
    case engineMissing

    public var description: String {
        switch self {
        case .noEnvironment: return "This game doesn’t have a Windows environment yet. Steam creates one the first time you play it."
        case .gameRunning: return "Quit the game, then try again."
        case .engineMissing: return "The Wine version this game uses isn’t installed."
        }
    }
}

/// Runs a game in a window of a fixed size that the game takes for the whole screen (Wine's "virtual desktop").
///
/// Some old games insist on a screen shape the Mac's display does not have: Silent Hunter III asks for 1024 × 768,
/// a MacBook's screen offers no 4:3 mode at all, Wine refuses, and the game stops with "Can not initialize 3D
/// engine". Inside a virtual desktop the size is offered and accepted (found 2026-11-18; see FINDINGS.md).
///
/// Wine reads this from the game's own Windows environment and from nowhere else, so unlike the other settings
/// it is not kept in Steam's launch options. A game that has never been started has no environment to keep it in.
public struct FixedWindow: Sendable {
    public struct Size: Sendable, Hashable, Identifiable, CustomStringConvertible {
        public let width: Int
        public let height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }

        public var id: String { registryValue }
        /// "1024 × 768", for people.
        public var description: String { "\(width) × \(height)" }
        /// "1024x768", as Wine writes it.
        var registryValue: String { "\(width)x\(height)" }

        /// Reads "1024x768".
        init?(registryValue: String) {
            let parts = registryValue.lowercased().split(separator: "x")
            guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]), width > 0, height > 0 else { return nil }
            self.init(width: width, height: height)
        }

        /// The size most old games ask for.
        public static let usual = Size(width: 1024, height: 768)
    }

    /// The 4:3 sizes old games were written for, smallest first.
    public static let sizes = [
        Size(width: 800, height: 600), .usual, Size(width: 1152, height: 864),
        Size(width: 1280, height: 960), Size(width: 1400, height: 1050), Size(width: 1600, height: 1200),
    ]

    /// The sizes whose window fits on a screen with this much room, title bar included. A size that is already
    /// set is always among them, so the pop-up can show it.
    public static func sizes(fittingWidth width: Double, height: Double, including current: Size? = nil) -> [Size] {
        let titleBar = 28.0
        var result = sizes.filter { Double($0.width) <= width && Double($0.height) + titleBar <= height }
        if let current, !result.contains(current) { result.append(current) }
        return result.sorted { ($0.width, $0.height) < ($1.width, $1.height) }
    }

    public let paths: Paths
    let gameIsRunning: @Sendable (String) -> Bool
    let runWine: @Sendable (_ engine: EngineSpec, _ prefix: URL, _ arguments: [String]) throws -> Void

    public init(paths: Paths = .live) {
        self.init(paths: paths, gameIsRunning: { Self.isRunning(appID: $0, paths: paths) }, runWine: { engine, prefix, arguments in
            try Self.wine(engine: engine, prefix: prefix, arguments: arguments, paths: paths)
        })
    }

    init(paths: Paths, gameIsRunning: @escaping @Sendable (String) -> Bool,
         runWine: @escaping @Sendable (EngineSpec, URL, [String]) throws -> Void) {
        self.paths = paths
        self.gameIsRunning = gameIsRunning
        self.runWine = runWine
    }

    // MARK: Reading

    /// The game's Windows environment, once it has one.
    func prefix(appID: String) -> URL? {
        EnvironmentCopy(paths: paths).environment(appID: appID).map { $0.appending(path: "pfx") }
            .flatMap { FileManager.default.fileExists(atPath: $0.appending(path: "user.reg").path) ? $0 : nil }
    }

    /// Whether the setting can be kept for this game yet.
    public func hasEnvironment(appID: String) -> Bool { prefix(appID: appID) != nil }

    /// A game runs from the add-on's own folder for it, so its processes carry that folder in their command line.
    public func isRunning(appID: String) -> Bool { gameIsRunning(appID) }

    static func isRunning(appID: String, paths: Paths) -> Bool {
        let folder = paths.notproton.appending(path: "launchers/\(appID)/").path
        return (try? Shell.run("/usr/bin/pgrep", ["-f", folder]))?.ok ?? false
    }

    /// The size the game is set to, or nil when it runs the ordinary way. Reading changes nothing.
    public func size(appID: String) -> Size? {
        guard let prefix = prefix(appID: appID) else { return nil }
        let file = prefix.appending(path: "user.reg")
        // Wine writes the file as plain text; a name with other bytes in it must not hide the setting.
        guard let text = (try? String(contentsOf: file, encoding: .utf8))
                ?? (try? String(contentsOf: file, encoding: .isoLatin1)) else { return nil }
        return Self.size(inRegistry: text)
    }

    /// Reads it out of the text of Wine's `user.reg`: the desktop named under Explorer, and that desktop's size.
    static func size(inRegistry text: String) -> Size? {
        func values(_ section: String) -> [String: String] {
            var result: [String: String] = [:]
            var inside = false
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                if line.hasPrefix("[") {
                    // A section line reads: [Software\\Wine\\Explorer] 1794994802
                    inside = line.lowercased().hasPrefix("[\(section.lowercased())]")
                    continue
                }
                guard inside, line.hasPrefix("\"") else { continue }
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" \r")) }
                if parts.count == 2 { result[parts[0].lowercased()] = parts[1] }
            }
            return result
        }
        guard let name = values(#"Software\\Wine\\Explorer"#)["desktop"], !name.isEmpty,
              let value = values(#"Software\\Wine\\Explorer\\Desktops"#)[name.lowercased()] else { return nil }
        return Size(registryValue: value)
    }

    // MARK: Writing

    static let explorerKey = #"HKCU\Software\Wine\Explorer"#
    static let desktopsKey = #"HKCU\Software\Wine\Explorer\Desktops"#
    /// The name Wine's own settings window gives the desktop it makes.
    static let desktopName = "Default"

    /// What Wine's `reg` is asked to do for a size, or for none.
    static func commands(for size: Size?) -> [[String]] {
        if let size {
            return [
                ["reg", "add", explorerKey, "/v", "Desktop", "/d", desktopName, "/f"],
                ["reg", "add", desktopsKey, "/v", desktopName, "/d", size.registryValue, "/f"],
            ]
        }
        return [
            ["reg", "delete", explorerKey, "/v", "Desktop", "/f"],
            ["reg", "delete", desktopsKey, "/v", desktopName, "/f"],
        ]
    }

    /// Sets the size, or with nil goes back to the ordinary way. The game has to exist as a Windows environment
    /// and must not be running. Steam can stay open: nothing of Steam's is touched.
    public func set(_ size: Size?, appID: String) throws {
        guard let prefix = prefix(appID: appID) else { throw FixedWindowError.noEnvironment }
        guard !gameIsRunning(appID) else { throw FixedWindowError.gameRunning }
        guard self.size(appID: appID) != size else { return }
        // The engine the game runs on, so Wine does not take the environment for one of another version.
        guard let engine = EngineStore(paths: paths).engine(for: appID) else { throw FixedWindowError.engineMissing }
        for command in Self.commands(for: size) {
            // Taking away a value that is not there is not a failure.
            do { try runWine(engine, prefix, command) } catch { if size != nil { throw error } }
        }
    }

    /// Runs one Wine program in a game's Windows environment and waits until Wine has written its registry.
    static func wine(engine: EngineSpec, prefix: URL, arguments: [String], paths: Paths) throws {
        let root = Runner(paths: paths, spec: engine).root
        let loader = root.appending(path: "lib/wine/x86_64-unix/wine")
        let server = root.appending(path: "bin/wineserver")
        guard FileManager.default.fileExists(atPath: loader.path) else { throw FixedWindowError.engineMissing }
        var environment = ProcessInfo.processInfo.environment
        environment["WINEPREFIX"] = prefix.path
        environment["WINELOADER"] = loader.path
        environment["WINESERVER"] = server.path
        environment["WINEDLLPATH"] = "\(root.path)/lib/wine/x86_64-windows:\(root.path)/lib/wine/x86_64-unix"
        environment["WINEDEBUG"] = "-all"
        // Wine's own first-run helpers stay out of this; they belong to the game's start.
        environment["WINEDLLOVERRIDES"] = "mscoree=;mshtml=;winedbg.exe=d"
        for setting in Runner.defaults {
            let parts = setting.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { environment[parts[0]] = parts[1] }
        }
        try Shell.check(loader.path, arguments, environment: environment)
        // Wine keeps the registry in memory; this waits for its server to finish and write it out.
        _ = try? Shell.run(server.path, ["-w"], environment: environment)
    }
}

/// Signs in a game's log of what went wrong the last time it started.
public enum GameLogSigns {
    /// True when the game asked Wine for a screen size and was refused, which is what a fixed window is for.
    public static func refusedScreenSize(wineLog: String) -> Bool {
        wineLog.contains("NtUserChangeDisplaySettings") && wineLog.contains("display settings returned -2")
    }

    public static func refusedScreenSize(appID: String, paths: Paths = .live) -> Bool {
        let log = paths.notproton.appending(path: "launchers/\(appID)/notproton-wine.log")
        guard let handle = try? FileHandle(forReadingFrom: log) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 2_000_000),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return false }
        return refusedScreenSize(wineLog: text)
    }
}
