import Foundation
import Testing
@testable import TanninCore

@Suite struct PinTests {
    @Test func everyPinIsHTTPSWithAFullHash() {
        for pin in Pins.all {
            #expect(pin.sha256.count == 64, "\(pin.name)")
            #expect(pin.sha256.allSatisfy { $0.isHexDigit && !$0.isUppercase }, "\(pin.name)")
            #expect(!pin.urls.isEmpty, "\(pin.name)")
            #expect(pin.urls.allSatisfy { $0.hasPrefix("https://") }, "\(pin.name)")
        }
    }

    @Test func valveFilesNameKnownPackagesAndFullHashes() {
        for file in Pins.valveFiles {
            #expect(["linux", "win64"].contains(file.package))
            #expect(file.sha256.count == 64)
            #expect(!file.destination.hasPrefix("/"))
            #expect(!file.destination.contains(".."))
        }
    }
}

@Suite struct HashingTests {
    @Test func sha256OfKnownContent() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "tannin-hash-\(UUID().uuidString)")
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try Hashing.sha256(of: url) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func verifyRejectsAndRemovesAWrongFile() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "tannin-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let downloader = Downloader(paths: Paths(home: home))
        try FileManager.default.createDirectory(at: downloader.paths.downloads, withIntermediateDirectories: true)
        let file = downloader.paths.downloads.appending(path: "x.bin")
        try Data("not the right bytes".utf8).write(to: file)
        let pin = Pin(name: "x.bin", urls: ["https://example.invalid/x.bin"], sha256: String(repeating: "0", count: 64))
        #expect(throws: DownloadError.self) { try downloader.verify(file, against: pin) }
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}

@Suite struct ShellTests {
    @Test func capturesOutputAndStatus() throws {
        let result = try Shell.run("/bin/echo", ["hello world"])
        #expect(result.ok)
        #expect(result.stdout == "hello world\n")
    }

    @Test func argumentsAreNeverShellInterpreted() throws {
        let result = try Shell.run("/bin/echo", ["$(whoami); `id`"])
        #expect(result.stdout == "$(whoami); `id`\n")
    }

    @Test func checkThrowsOnFailure() {
        #expect(throws: ShellError.self) { try Shell.check("/usr/bin/false") }
    }
}

@Suite struct SteamInstallTests {
    /// Builds a fake Steam layout in a temp folder.
    func makeHome() throws -> Paths {
        let home = FileManager.default.temporaryDirectory.appending(path: "tannin-steam-\(UUID().uuidString)")
        let paths = Paths(home: home, steamApp: home.appending(path: "Applications/Steam.app"))
        let fm = FileManager.default
        try fm.createDirectory(at: paths.steamData.appending(path: "steamapps"), withIntermediateDirectories: true)
        try fm.createDirectory(at: paths.steamClientManifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "\"osx\"\n{\n\t\"version\"\t\t\"1794536281\"\n}\n".write(to: paths.steamClientManifest, atomically: true, encoding: .utf8)
        try "\"libraryfolders\"\n{\n\t\"0\"\n\t{\n\t\t\"path\"\t\t\"\(paths.steamData.path)\"\n\t}\n}\n"
            .write(to: paths.steamLibraryFolders, atomically: true, encoding: .utf8)
        try "\"AppState\"\n{\n\t\"appid\"\t\t\"1544360\"\n\t\"name\"\t\t\"LEGO Builder's Journey\"\n\t\"installdir\"\t\t\"LEGO Builders Journey\"\n}\n"
            .write(to: paths.steamData.appending(path: "steamapps/appmanifest_1544360.acf"), atomically: true, encoding: .utf8)
        return paths
    }

    @Test func readsBuildLibrariesAndApps() throws {
        let paths = try makeHome()
        defer { try? FileManager.default.removeItem(at: paths.home) }
        let steam = SteamInstall(paths: paths)
        #expect(steam.clientBuild() == "1794536281")
        #expect(steam.libraries().count == 1)
        let apps = steam.installedApps()
        #expect(apps.map(\.appID) == ["1544360"])
        #expect(apps.first?.name == "LEGO Builder's Journey")
        #expect(steam.isInstalled == false)
        #expect(steam.injectedLibraries() == nil)
    }
}
