import Foundation
import Testing
@testable import TanninCore

/// Writes a small `appinfo.vdf` in Steam's format 29, so the reader is tested against the real layout
/// without depending on the Steam installed on this Mac.
struct AppInfoFile {
    indirect enum Value {
        case text(String)
        case number(Int32)
        case object([(String, Value)])
    }

    private var keys: [String] = []

    private mutating func index(of key: String) -> UInt32 {
        if let found = keys.firstIndex(of: key) { return UInt32(found) }
        keys.append(key)
        return UInt32(keys.count - 1)
    }

    private func little<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }

    private mutating func encode(_ pairs: [(String, Value)]) -> [UInt8] {
        var out: [UInt8] = []
        for (key, value) in pairs {
            switch value {
            case let .object(children):
                out += [0x00] + little(index(of: key)) + encode(children)
            case let .text(string):
                out += [0x01] + little(index(of: key)) + Array(string.utf8) + [0]
            case let .number(number):
                out += [0x02] + little(index(of: key)) + little(number)
            }
        }
        return out + [0x08]
    }

    mutating func data(apps: [(UInt32, [(String, Value)])], magic: UInt32 = AppInfo.magic) -> Data {
        var body: [UInt8] = []
        for (appID, sections) in apps {
            let content = [UInt8](repeating: 0, count: AppInfo.entryHeaderSize) + encode([("appinfo", .object(sections))])
            body += little(appID) + little(UInt32(content.count)) + content
        }
        body += little(UInt32(0))
        var table = little(UInt32(keys.count))
        for key in keys { table += Array(key.utf8) + [0] }
        return Data(little(magic) + little(UInt32(1)) + little(Int64(16 + body.count)) + body + table)
    }

    static func game(name: String, type: String = "Game", platforms: String?, launches: [(String, String?, Int32?)]) -> [(String, Value)] {
        var common: [(String, Value)] = [("name", .text(name)), ("type", .text(type))]
        if let platforms { common.append(("oslist", .text(platforms))) }
        let launch = launches.enumerated().map { index, entry -> (String, Value) in
            var config: [(String, Value)] = []
            if let os = entry.1 { config.append(("oslist", .text(os))) }
            if let bits = entry.2 { config.append(("osarch", .number(bits))) }
            return (String(index), .object([("executable", .text(entry.0)), ("config", .object(config))]))
        }
        return [("common", .object(common)), ("config", .object([("launch", .object(launch))]))]
    }
}

@Suite struct AppInfoTests {
    @Test func readsNameTypePlatformsAndLaunches() {
        var file = AppInfoFile()
        let data = file.data(apps: [
            (1544360, AppInfoFile.game(name: "LEGO® Builder's Journey", platforms: "windows",
                                       launches: [("Builder's Journey.exe", "windows", nil)])),
            (50300, AppInfoFile.game(name: "Spec Ops: The Line", platforms: "windows,macos,linux",
                                     launches: [("Binaries\\Win32\\SpecOpsTheLine.exe", "windows", nil), ("SpecOps.app", "macos", nil)])),
            (15210, AppInfoFile.game(name: "Silent Hunter III", type: "game", platforms: nil, launches: [("sh3.exe", nil, 32)])),
        ])
        let apps = AppInfo.parse(data)
        #expect(apps.count == 3)

        let lego = apps["1544360"]
        #expect(lego?.name == "LEGO® Builder's Journey")
        #expect(lego?.isGame == true)
        #expect(lego?.hasMacBuild == false)
        #expect(lego?.launches.map(\.executable) == ["Builder's Journey.exe"])

        let specOps = apps["50300"]
        #expect(specOps?.hasMacBuild == true)
        #expect(specOps?.launches.first?.executable == "Binaries/Win32/SpecOpsTheLine.exe")
        #expect(specOps?.launches.map(\.isForWindows) == [true, false])

        let hunter = apps["15210"]
        #expect(hunter?.platforms.isEmpty == true)
        #expect(hunter?.launches.first?.bits == 32)
        #expect(hunter?.launches.first?.isForWindows == true)
    }

    @Test func anUnknownFormatOrADamagedFileGivesNothing() {
        var file = AppInfoFile()
        let apps = [(UInt32(10), AppInfoFile.game(name: "X", platforms: "windows", launches: []))]
        #expect(AppInfo.parse(file.data(apps: apps, magic: 0x0756_4428)).isEmpty)
        let good = file.data(apps: apps)
        #expect(AppInfo.parse(good).count == 1)
        #expect(AppInfo.parse(good.prefix(good.count / 2)).isEmpty)
        #expect(AppInfo.parse(Data()).isEmpty)
        #expect(AppInfo.parse(Data(repeating: 0xFF, count: 64)).isEmpty)
    }
}

@Suite struct PEHeaderTests {
    func program(machine: UInt16) -> Data {
        var bytes = [UInt8](repeating: 0, count: 0x80)
        bytes[0] = 0x4D
        bytes[1] = 0x5A
        bytes[60] = 0x40
        bytes[0x40] = 0x50
        bytes[0x41] = 0x45
        bytes[0x44] = UInt8(machine & 0xFF)
        bytes[0x45] = UInt8(machine >> 8)
        return Data(bytes)
    }

    @Test func tellsThirtyTwoFromSixtyFourBit() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "tannin-pe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let x86 = folder.appending(path: "a.exe")
        let x64 = folder.appending(path: "b.exe")
        let text = folder.appending(path: "c.exe")
        try program(machine: 0x014C).write(to: x86)
        try program(machine: 0x8664).write(to: x64)
        try Data("not a program".utf8).write(to: text)
        #expect(PEHeader.machine(of: x86) == .x86)
        #expect(PEHeader.machine(of: x86)?.is32Bit == true)
        #expect(PEHeader.machine(of: x64) == .x64)
        #expect(PEHeader.machine(of: x64)?.is32Bit == false)
        #expect(PEHeader.machine(of: text) == nil)
        #expect(PEHeader.machine(of: folder.appending(path: "missing.exe")) == nil)
    }
}

@Suite struct LibraryTests {
    /// A Steam folder with one installed Windows game, one installed Mac game, and a library of four more.
    func makeHome() throws -> Paths {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appending(path: "tannin-library-\(UUID().uuidString)")
        let paths = Paths(home: home, steamApp: home.appending(path: "Applications/Steam.app"))
        let steamapps = paths.steamData.appending(path: "steamapps")
        try fm.createDirectory(at: steamapps.appending(path: "compatdata/100"), withIntermediateDirectories: true)
        try fm.createDirectory(at: steamapps.appending(path: "common/Old Game/bin"), withIntermediateDirectories: true)
        try fm.createDirectory(at: paths.steamAppInfo.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: paths.steamData.appending(path: "userdata/1/config"), withIntermediateDirectories: true)
        try fm.createDirectory(at: paths.steamConfig.deletingLastPathComponent(), withIntermediateDirectories: true)

        func manifest(_ appID: String, _ name: String, _ dir: String, flags: String) throws {
            try "\"AppState\"\n{\n\t\"appid\"\t\t\"\(appID)\"\n\t\"name\"\t\t\"\(name)\"\n\t\"StateFlags\"\t\t\"\(flags)\"\n\t\"installdir\"\t\t\"\(dir)\"\n\t\"SizeOnDisk\"\t\t\"4322970119\"\n}\n"
                .write(to: steamapps.appending(path: "appmanifest_\(appID).acf"), atomically: true, encoding: .utf8)
        }
        try manifest("100", "Old Game", "Old Game", flags: "4")
        try manifest("200", "Mac Game", "Mac Game", flags: "4")
        try manifest("300", "Half Downloaded", "Half Downloaded", flags: "1026")

        try PEHeaderTests().program(machine: 0x014C).write(to: steamapps.appending(path: "common/Old Game/bin/old.exe"))

        var file = AppInfoFile()
        try file.data(apps: [
            (100, AppInfoFile.game(name: "Old Game", platforms: "windows", launches: [("bin\\old.exe", "windows", nil)])),
            (200, AppInfoFile.game(name: "Mac Game", platforms: "windows,macos", launches: [("Mac Game.app", "macos", nil)])),
            (300, AppInfoFile.game(name: "Half Downloaded", platforms: nil, launches: [("half.exe", nil, 64)])),
            (400, AppInfoFile.game(name: "Zebra", platforms: "windows", launches: [("z.exe", "windows", 64)])),
            (500, AppInfoFile.game(name: "apple", platforms: "windows,linux", launches: [("a.exe", "windows", nil)])),
            (600, AppInfoFile.game(name: "Has A Mac Version", platforms: "windows,macos", launches: [])),
            (700, AppInfoFile.game(name: "Not Owned", platforms: "windows", launches: [])),
            (800, AppInfoFile.game(name: "Soundtrack", type: "Music", platforms: nil, launches: [])),
        ]).write(to: paths.steamAppInfo)

        // App 400 keeps its image one folder down under a hash, as Steam does for newer games.
        for (appID, files) in [("100", ["library_hero.jpg", "library_600x900.jpg"]), ("400", ["0a1b2c/library_header.jpg"]), ("500", []), ("600", []), ("800", [])] {
            let folder = paths.steamLibraryCache.appending(path: appID)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            for name in files {
                let file = folder.appending(path: name)
                try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data().write(to: file)
            }
        }

        try """
        "UserLocalConfigStore"
        {
        \t"Software"
        \t{
        \t\t"Valve"
        \t\t{
        \t\t\t"Steam"
        \t\t\t{
        \t\t\t\t"apps"
        \t\t\t\t{
        \t\t\t\t\t"100"
        \t\t\t\t\t{
        \t\t\t\t\t\t"LastPlayed"\t\t"1795007059"
        \t\t\t\t\t\t"Playtime"\t\t"53"
        \t\t\t\t\t\t"LaunchOptions"\t\t"D3DM_MAX_FPS=30 %command%"
        \t\t\t\t\t}
        \t\t\t\t\t"400"
        \t\t\t\t\t{
        \t\t\t\t\t\t"Playtime"\t\t"1240"
        \t\t\t\t\t\t"LaunchOptions"\t\t"MTL_HUD_ENABLED=1 %command%"
        \t\t\t\t\t}
        \t\t\t\t\t"500"
        \t\t\t\t\t{
        \t\t\t\t\t\t"Playtime"\t\t"0"
        \t\t\t\t\t}
        \t\t\t\t}
        \t\t\t}
        \t\t}
        \t}
        }

        """.write(to: paths.steamData.appending(path: "userdata/1/config/localconfig.vdf"), atomically: true, encoding: .utf8)
        return paths
    }

    @Test func sortsTheLibraryIntoInstalledAndNotInstalled() throws {
        let paths = try makeHome()
        defer { try? FileManager.default.removeItem(at: paths.home) }
        let library = LibraryReader(paths: paths).read()

        // The Mac game is left out; the half-downloaded Windows game is in, marked as installing.
        #expect(library.installed.map(\.name) == ["Half Downloaded", "Old Game"])
        let old = try #require(library.game("100"))
        #expect(old.install == .installed)
        #expect(old.sizeOnDisk == 4_322_970_119)
        #expect(old.is32Bit == true)
        #expect(old.settings.frameCap == 30)
        #expect(old.art.banner?.lastPathComponent == "library_hero.jpg")
        #expect(old.art.thumbnail?.lastPathComponent == "library_600x900.jpg")
        #expect(library.game("300")?.install == .installing)
        #expect(library.game("300")?.is32Bit == false)

        // Not installed: games only, no Mac version, and only ones Steam keeps library artwork for.
        #expect(library.notInstalled.map(\.name) == ["apple", "Zebra"])
        let zebra = try #require(library.game("400"))
        #expect(zebra.install == .notInstalled)
        #expect(zebra.is32Bit == false)
        #expect(zebra.settings.performanceHUD == true)
        #expect(zebra.art.banner?.path.hasSuffix("400/0a1b2c/library_header.jpg") == true)
        #expect(library.game("500")?.is32Bit == nil)
        #expect(library.game("500")?.art == GameArt.none)
    }

    @Test func playTimeComesFromSteamsOwnRecord() throws {
        let paths = try makeHome()
        defer { try? FileManager.default.removeItem(at: paths.home) }
        #expect(SteamConfig(paths: paths).playtimes() == ["100": 53, "400": 1240])
        let library = LibraryReader(paths: paths).read()
        #expect(library.game("100")?.minutesPlayed == 53)
        #expect(library.game("400")?.minutesPlayed == 1240)
        #expect(library.game("500")?.minutesPlayed == 0)
        // Reading play time leaves the launch options as they were read before.
        #expect(SteamConfig(paths: paths).allLaunchOptions() == ["100": "D3DM_MAX_FPS=30 %command%", "400": "MTL_HUD_ENABLED=1 %command%"])
    }

    @Test func withoutAppInfoOnlyGamesWithAWindowsEnvironmentAreListed() throws {
        let paths = try makeHome()
        defer { try? FileManager.default.removeItem(at: paths.home) }
        try FileManager.default.removeItem(at: paths.steamAppInfo)
        let library = LibraryReader(paths: paths).read()
        #expect(library.installed.map(\.name) == ["Old Game"])
        #expect(library.notInstalled.isEmpty)
        #expect(library.game("100")?.is32Bit == nil)
    }
}

@Suite struct SteamLauncherTests {
    @Test func buildsSteamAddressesFromDigitsOnly() throws {
        #expect(try SteamLauncher.address(for: .play("1544360")) == "steam://rungameid/1544360")
        #expect(try SteamLauncher.address(for: .install("15210")) == "steam://install/15210")
        #expect(try SteamLauncher.address(for: .showInLibrary("50300")) == "steam://nav/games/details/50300")
        #expect(throws: SteamLauncherError.self) { try SteamLauncher.address(for: .play("12/../x")) }
        #expect(throws: SteamLauncherError.self) { try SteamLauncher.address(for: .install("")) }
        #expect(throws: SteamLauncherError.self) { try SteamLauncher.address(for: .play("١٢٣")) }
    }
}

@Suite struct ShowcaseTests {
    private func game(_ appID: String, minutes: Int = 0, cover: Bool = true, installed: Bool = false) -> LibraryGame {
        let art = cover ? GameArt(hero: nil, cover: URL(fileURLWithPath: "/covers/\(appID).jpg"), header: nil, logo: nil) : GameArt.none
        return LibraryGame(appID: appID, name: "Game \(appID)", install: installed ? .installed : .notInstalled, art: art, minutesPlayed: minutes)
    }

    @Test func theMostPlayedComeFirstAndGamesWithoutACoverAreLeftOut() {
        let library = Library(installed: [game("1", minutes: 40, installed: true)],
                              notInstalled: [game("2", minutes: 900), game("3", minutes: 5000, cover: false), game("4", minutes: 120), game("5")])
        #expect(library.showcase(count: 7).map(\.appID) == ["2", "4", "1", "5"])
        #expect(library.showcase(count: 2).map(\.appID) == ["2", "4"])
        #expect(library.showcase(count: 0).isEmpty)
    }

    @Test func gamesNeverPlayedComeInAMixedOrderThatIsTheSameEveryTime() {
        let ids = (1...40).map { String($0 * 1010) }
        let library = Library(installed: [], notInstalled: ids.map { game($0) })
        let first = library.showcase(count: 7).map(\.appID)
        #expect(first.count == 7)
        // Not simply the order they were listed in, and not sorted by number either.
        #expect(first != Array(ids.prefix(7)))
        #expect(first != ids.sorted().prefix(7).map { $0 })
        // The same from a library listed the other way round: the order depends on the games, not on the list.
        #expect(Library(installed: [], notInstalled: ids.reversed().map { game($0) }).showcase(count: 7).map(\.appID) == first)
        // Pinned to the published FNV-1a values, so a change to the scramble shows up here. Swift's own hashing
        // would differ at each launch.
        #expect(Library.mixKey("") == 14_695_981_039_346_656_037)
        #expect(Library.mixKey("a") == 0xAF63_DC4C_8601_EC8C)
    }

    @Test func theRowPutsTheFirstInTheMiddleAndTheLastAtTheEdges() {
        #expect(Library.centred([0, 1, 2, 3, 4, 5, 6]) == [5, 3, 1, 0, 2, 4, 6])
        #expect(Library.centred([0, 1, 2, 3, 4]) == [3, 1, 0, 2, 4])
        #expect(Library.centred([0, 1]) == [1, 0])
        #expect(Library.centred([Int]()).isEmpty)
    }
}
