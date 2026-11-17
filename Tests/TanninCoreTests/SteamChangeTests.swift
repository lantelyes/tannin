import Foundation
import Testing
@testable import TanninCore

@Suite struct SteamAddonPlistTests {
    let original = Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>com.valvesoftware.steam</string>
    <key>LSEnvironment</key><dict><key>LC_ALL</key><string>en_US.UTF-8</string></dict>
    </dict></plist>
    """.utf8)

    func dictionary(_ data: Data) throws -> [String: Any] {
        try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func addsTheInsertAndKeepsEverythingElse() throws {
        let edited = try dictionary(try SteamAddon.plist(original, loading: "/Applications/Steam.app/Contents/MacOS/notproton.dylib"))
        let environment = try #require(edited["LSEnvironment"] as? [String: String])
        #expect(environment["DYLD_INSERT_LIBRARIES"] == "/Applications/Steam.app/Contents/MacOS/notproton.dylib")
        #expect(environment["SDL_JOYSTICK_BLACKLIST_DEVICES"] == "0x05ac/0x0004")
        #expect(environment["LC_ALL"] == "en_US.UTF-8")
        #expect(edited["CFBundleIdentifier"] as? String == "com.valvesoftware.steam")
    }

    @Test func removingRestoresTheOriginalMeaning() throws {
        let added = try SteamAddon.plist(original, loading: "/x/notproton.dylib")
        let removed = try dictionary(try SteamAddon.plistWithoutAddon(added))
        let before = try dictionary(original)
        #expect(NSDictionary(dictionary: removed).isEqual(to: before))
    }
}

@Suite struct UpdateFreezeTests {
    @Test func togglesOneLineAndKeepsOthers() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "tannin-freeze-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths(home: home)
        try FileManager.default.createDirectory(at: paths.steamData, withIntermediateDirectories: true)
        try "SomethingElse=1\n".write(to: paths.steamCfg, atomically: true, encoding: .utf8)
        let freeze = UpdateFreeze(paths: paths)

        #expect(!freeze.isOn)
        try freeze.set(true)
        #expect(freeze.isOn)
        #expect(try String(contentsOf: paths.steamCfg, encoding: .utf8) == "SomethingElse=1\nBootStrapperInhibitUpdateOnLaunch=enable\n")
        try freeze.set(true)
        #expect(try String(contentsOf: paths.steamCfg, encoding: .utf8).components(separatedBy: "Inhibit").count == 2)
        try freeze.set(false)
        #expect(try String(contentsOf: paths.steamCfg, encoding: .utf8) == "SomethingElse=1\n")
    }

    @Test func removesTheFileWhenNothingElseIsInIt() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "tannin-freeze-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths(home: home)
        try FileManager.default.createDirectory(at: paths.steamData, withIntermediateDirectories: true)
        let freeze = UpdateFreeze(paths: paths)
        try freeze.set(true)
        try freeze.set(false)
        #expect(!FileManager.default.fileExists(atPath: paths.steamCfg.path))
    }
}

@Suite struct SteamConfigTests {
    func makeHome() throws -> Paths {
        let home = FileManager.default.temporaryDirectory.appending(path: "tannin-config-\(UUID().uuidString)")
        let paths = Paths(home: home, steamApp: home.appending(path: "Applications/Steam.app"))
        let fm = FileManager.default
        try fm.createDirectory(at: paths.steamConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        "InstallConfigStore"
        {
        \t"Software"
        \t{
        \t\t"Valve"
        \t\t{
        \t\t\t"Steam"
        \t\t\t{
        \t\t\t\t"AutoUpdateWindowEnabled"\t\t"0"
        \t\t\t}
        \t\t}
        \t}
        \t"SteamID"\t\t"12345"
        }

        """.write(to: paths.steamConfig, atomically: true, encoding: .utf8)
        let local = paths.steamData.appending(path: "userdata/42/config/localconfig.vdf")
        try fm.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "\"UserLocalConfigStore\"\n{\n\t\"friends\"\n\t{\n\t\t\"x\"\t\t\"y\"\n\t}\n}\n".write(to: local, atomically: true, encoding: .utf8)
        return paths
    }

    @Test func compatToolIsSetAndClearedWithoutDisturbingOtherKeys() throws {
        let paths = try makeHome()
        defer { try? FileManager.default.removeItem(at: paths.home) }
        let config = SteamConfig(paths: paths, steamIsRunning: { false })
        let before = try VDF.load(paths.steamConfig)

        try config.setCompatTool(appID: "1544360", enabled: true)
        #expect(config.compatTool(appID: "1544360") == "notproton-tannin")
        let after = try VDF.load(paths.steamConfig)
        #expect(after.value(at: ["InstallConfigStore", "SteamID"])?.string == "12345")
        #expect(after.value(at: ["InstallConfigStore", "Software", "Valve", "Steam", "AutoUpdateWindowEnabled"])?.string == "0")
        #expect(after.value(at: ["InstallConfigStore", "Software", "Valve", "Steam", "CompatToolMapping", "1544360", "priority"])?.string == "250")

        try config.setCompatTool(appID: "1544360", enabled: false)
        #expect(config.compatTool(appID: "1544360") == nil)
        var cleared = try VDF.load(paths.steamConfig)
        cleared.remove(at: ["InstallConfigStore", "Software", "Valve", "Steam", "CompatToolMapping"])
        #expect(cleared == before)

        let backups = try FileManager.default.contentsOfDirectory(atPath: paths.backups.path)
        #expect(backups.filter { $0.hasPrefix("config.vdf.") }.count >= 1)
    }

    @Test func launchOptionsAreWrittenForTheSignedInUser() throws {
        let paths = try makeHome()
        defer { try? FileManager.default.removeItem(at: paths.home) }
        let config = SteamConfig(paths: paths, steamIsRunning: { false })
        try config.setLaunchOptions(appID: "1544360", "D3DM_SUPPORT_DXR=1 %command%")
        #expect(config.launchOptions(appID: "1544360") == "D3DM_SUPPORT_DXR=1 %command%")
        let file = try VDF.load(paths.steamData.appending(path: "userdata/42/config/localconfig.vdf"))
        #expect(file.value(at: ["UserLocalConfigStore", "friends", "x"])?.string == "y")
    }
}

@Suite struct GameSettingsTests {
    @Test func rendersOnlyWhatIsSet() {
        let settings = GameSettings(rayTracing: true, frameCap: 60)
        #expect(settings.launchOptions() == "CX_ACTIVE_GRAPHICS_BACKEND=d3dmetal D3DM_SUPPORT_DXR=1 D3DM_MAX_FPS=60 %command%")
    }

    @Test func keepsTheUsersOwnOptionsAndReplacesTannins() {
        let existing = "D3DM_SUPPORT_DXR=0 MY_FLAG=1 %command% -windowed"
        let merged = GameSettings(rayTracing: true).launchOptions(merging: existing)
        #expect(merged == "CX_ACTIVE_GRAPHICS_BACKEND=d3dmetal D3DM_SUPPORT_DXR=1 MY_FLAG=1 %command% -windowed")
    }

    @Test func runnerToolsLineIsWhatTheAddonAccepts() {
        let fields = Runner.toolsLine.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        #expect(fields.count == 4)
        #expect(fields[0].hasPrefix("notproton"))
        #expect(fields[0].lowercased().contains("proton"))
        #expect(fields[1].allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" })
        #expect(["rosetta", "fex"].contains(fields[2]))
        #expect(!fields[3].contains("\"") && !fields[3].contains("\\") && fields[3].count < 96)
    }

    @Test func ntdllPinsAreFullHashes() {
        for pin in NtdllPatch.pins {
            #expect(pin.cleanSHA256.count == 64 && pin.patchedSHA256.count == 64 && pin.detourSHA256.count == 64)
            #expect(pin.cleanSHA256 != pin.patchedSHA256)
        }
    }
}

@Suite struct SteamRunningGuardTests {
    @Test func editsAreRefusedWhileSteamRuns() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "tannin-guard-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = Paths(home: home)
        try FileManager.default.createDirectory(at: paths.steamConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = "\"InstallConfigStore\"\n{\n\t\"SteamID\"\t\t\"1\"\n}\n"
        try original.write(to: paths.steamConfig, atomically: true, encoding: .utf8)
        let config = SteamConfig(paths: paths, steamIsRunning: { true })
        #expect(throws: SteamConfigError.self) { try config.setCompatTool(appID: "1544360", enabled: true) }
        #expect(try String(contentsOf: paths.steamConfig, encoding: .utf8) == original)
    }
}
