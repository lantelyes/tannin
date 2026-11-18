import Foundation

/// A Windows game in the user's Steam library, installed or not.
public struct LibraryGame: Sendable, Hashable, Identifiable {
    public enum Install: Sendable, Hashable {
        case notInstalled
        /// Steam has started installing or updating it and has not finished.
        case installing
        case installed
    }

    public let appID: String
    public let name: String
    public let install: Install
    public let sizeOnDisk: Int64?
    public let launchOptions: String
    /// True for a 32-bit game, false for 64-bit, nil when it cannot be told (not installed, or no program found).
    public let is32Bit: Bool?
    public let art: GameArt
    /// The game's own folder, once it is installed.
    public let installFolder: URL?
    /// How long this Steam account has played it, in minutes. Zero when never, or when Steam does not say.
    public let minutesPlayed: Int

    public init(appID: String, name: String, install: Install, sizeOnDisk: Int64? = nil, launchOptions: String = "",
                is32Bit: Bool? = nil, art: GameArt = .none, installFolder: URL? = nil, minutesPlayed: Int = 0) {
        self.appID = appID
        self.name = name
        self.install = install
        self.sizeOnDisk = sizeOnDisk
        self.launchOptions = launchOptions
        self.is32Bit = is32Bit
        self.art = art
        self.installFolder = installFolder
        self.minutesPlayed = minutesPlayed
    }

    public var id: String { appID }
    public var isInstalled: Bool { install != .notInstalled }
    public var settings: GameSettings { GameSettings(parsing: launchOptions) }
}

public struct Library: Sendable, Equatable {
    public var installed: [LibraryGame]
    public var notInstalled: [LibraryGame]

    public static let empty = Library(installed: [], notInstalled: [])

    public init(installed: [LibraryGame], notInstalled: [LibraryGame]) {
        self.installed = installed
        self.notInstalled = notInstalled
    }

    public var all: [LibraryGame] { installed + notInstalled }
    public func game(_ appID: String) -> LibraryGame? { all.first { $0.appID == appID } }

    /// The games to show someone as their own: those with a cover, the most played first. Games never played
    /// follow in a mixed order that is the same every time, so the same covers come up at each launch.
    public func showcase(count: Int) -> [LibraryGame] {
        let ranked = all.filter { $0.art.cover != nil }.sorted { a, b in
            if a.minutesPlayed != b.minutesPlayed { return a.minutesPlayed > b.minutesPlayed }
            let (x, y) = (Self.mixKey(a.appID), Self.mixKey(b.appID))
            return x != y ? x < y : a.appID < b.appID
        }
        return Array(ranked.prefix(max(0, count)))
    }

    /// A fixed scramble of an app ID (FNV-1a). Swift's own hashing changes from one launch to the next.
    static func mixKey(_ appID: String) -> UInt64 {
        appID.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }
}

/// Works out the Windows games in the Steam library from Steam's own files. Reading changes nothing.
public struct LibraryReader: Sendable {
    public let paths: Paths

    public init(paths: Paths = .live) { self.paths = paths }

    /// Changes whenever something the library is read from changes, so callers can skip reading it again.
    /// Cheap: it looks at dates only.
    public func fingerprint() -> String {
        let fm = FileManager.default
        func stamp(_ url: URL) -> String {
            let date = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
            return date.map { String($0.timeIntervalSince1970) } ?? "-"
        }
        var parts = [stamp(paths.steamAppInfo), stamp(paths.steamLibraryCache), stamp(paths.steamConfig)]
        if let local = try? SteamConfig(paths: paths).localConfig() { parts.append(stamp(local)) }
        for library in SteamInstall(paths: paths).libraries() {
            let steamapps = library.appending(path: "steamapps")
            parts.append(stamp(steamapps))
            parts.append(stamp(steamapps.appending(path: "compatdata")))
            let manifests = ((try? fm.contentsOfDirectory(atPath: steamapps.path)) ?? []).filter { $0.hasPrefix("appmanifest_") }.sorted()
            parts += manifests.map { "\($0)@\(stamp(steamapps.appending(path: $0)))" }
        }
        return parts.joined(separator: "|")
    }

    public func read() -> Library {
        let fm = FileManager.default
        let steam = SteamInstall(paths: paths)
        let config = SteamConfig(paths: paths)
        let info = AppInfo.load(paths.steamAppInfo)
        let (options, minutes) = config.appSettings()
        let mapped = config.compatToolAppIDs()
        let apps = steam.installedApps()

        // Installed and meant for Windows: it has a Windows environment beside it, the user chose a compatibility
        // tool for it, or Steam says it has no Mac version.
        let installed = apps.filter { app in
            if fm.fileExists(atPath: app.library.appending(path: "steamapps/compatdata/\(app.appID)").path) { return true }
            if mapped.contains(app.appID) { return true }
            if let entry = info[app.appID] { return entry.isGame && !entry.hasMacBuild }
            return false
        }.map { app in
            LibraryGame(
                appID: app.appID,
                name: app.name,
                install: app.isFullyInstalled ? .installed : .installing,
                sizeOnDisk: app.sizeOnDisk,
                launchOptions: options[app.appID] ?? "",
                is32Bit: is32Bit(app, entry: info[app.appID]),
                art: GameArt(appID: app.appID, paths: paths),
                installFolder: app.library.appending(path: "steamapps/common/\(app.installDir)"),
                minutesPlayed: minutes[app.appID] ?? 0
            )
        }

        // Owned but not installed: Steam keeps library artwork for the games in the library, so a game with
        // an artwork folder, no Mac version and no install is one the user could install through Steam Play.
        let installedIDs = Set(apps.map(\.appID))
        let cached = Set((try? fm.contentsOfDirectory(atPath: paths.steamLibraryCache.path)) ?? [])
        let notInstalled = info.values
            .filter { $0.isGame && !$0.hasMacBuild && !installedIDs.contains($0.appID) && cached.contains($0.appID) }
            .map { entry in
                LibraryGame(
                    appID: entry.appID,
                    name: entry.name,
                    install: .notInstalled,
                    launchOptions: options[entry.appID] ?? "",
                    is32Bit: entry.launches.first(where: \.isForWindows)?.bits.map { $0 == 32 },
                    art: GameArt(appID: entry.appID, paths: paths),
                    minutesPlayed: minutes[entry.appID] ?? 0
                )
            }

        func byName(_ a: LibraryGame, _ b: LibraryGame) -> Bool {
            a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return Library(installed: installed.sorted(by: byName), notInstalled: notInstalled.sorted(by: byName))
    }

    /// Looks at the game's own Windows program. Steam's stated value is used only when the file is not there.
    func is32Bit(_ app: SteamApp, entry: AppInfoEntry?) -> Bool? {
        guard let entry else { return nil }
        let folder = app.library.appending(path: "steamapps/common/\(app.installDir)")
        let launches = entry.launches.filter(\.isForWindows)
        for launch in launches {
            if let machine = PEHeader.machine(of: folder.appending(path: launch.executable)) { return machine.is32Bit }
        }
        return launches.first?.bits.map { $0 == 32 }
    }
}
