import Foundation
import Testing
@testable import TanninCore

@Suite struct NtdllRecipeTests {
    @Test func writesItsRunsAndNothingElse() throws {
        let recipe = NtdllRecipe(arch: "x86_64", cleanSHA256: "", patchedSHA256: "", size: 16, runs: [
            .init(offset: 2, hex: "e9ff"),
            .init(offset: 10, hex: "0a0b\n   0c"),
        ])
        let patched = try recipe.apply(to: Data(repeating: 0x11, count: 16))
        #expect([UInt8](patched) == [0x11, 0x11, 0xE9, 0xFF, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x0B, 0x0C, 0x11, 0x11, 0x11])
    }

    @Test func refusesAFileOfTheWrongSizeOrDamagedData() {
        let recipe = NtdllRecipe(arch: "x86_64", cleanSHA256: "", patchedSHA256: "", size: 16, runs: [.init(offset: 2, hex: "e9ff")])
        #expect(throws: NtdllRecipe.Failure.self) { try recipe.apply(to: Data(repeating: 0, count: 15)) }
        for hex in ["e9f", "zz", "E9FF"] {
            let damaged = NtdllRecipe(arch: "x86_64", cleanSHA256: "", patchedSHA256: "", size: 16, runs: [.init(offset: 2, hex: hex)])
            #expect(throws: NtdllRecipe.Failure.self) { try damaged.apply(to: Data(repeating: 0, count: 16)) }
        }
        let outside = NtdllRecipe(arch: "x86_64", cleanSHA256: "", patchedSHA256: "", size: 16, runs: [.init(offset: 15, hex: "e9ff")])
        #expect(throws: NtdllRecipe.Failure.self) { try outside.apply(to: Data(repeating: 0, count: 16)) }
    }

    @Test func everyPatchedArchitectureHasARecipeMatchingItsPin() {
        for arch in Runner.patchedArchitectures {
            let pin = NtdllPatch.pins.first { $0.arch == arch }
            let recipe = NtdllRecipe.all.first { $0.arch == arch && $0.cleanSHA256 == pin?.cleanSHA256 }
            #expect(recipe != nil, "\(arch)")
            #expect(recipe?.patchedSHA256 == pin?.patchedSHA256, "\(arch)")
            #expect(recipe?.runs.allSatisfy { $0.bytes != nil } == true, "\(arch)")
        }
    }

    /// The real thing, when the engine is installed on this Mac: the engine's own file in, the pinned patched file out.
    @Test(.enabled(if: Engine().isInstalled))
    func theRecipeTurnsTheInstalledEngineFileIntoThePinnedPatchedFile() throws {
        let clean = Engine().wine.appending(path: "lib/wine/x86_64-windows/ntdll.dll")
        let recipe = try #require(NtdllRecipe.all.first { $0.arch == "x86_64" })
        try #require(try Hashing.sha256(of: clean) == recipe.cleanSHA256)
        let out = FileManager.default.temporaryDirectory.appending(path: "tannin-ntdll-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        try recipe.apply(to: try Data(contentsOf: clean)).write(to: out)
        #expect(try Hashing.sha256(of: out) == recipe.patchedSHA256)
    }
}

/// Collects progress reports from the download thread.
final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [DownloadProgress] = []
    func add(_ item: DownloadProgress) { lock.withLock { items.append(item) } }
    var all: [DownloadProgress] { lock.withLock { items } }
}

@Suite struct DownloadTests {
    func makeSource(bytes: Int) throws -> (home: URL, source: URL, pin: Pin) {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appending(path: "tannin-download-\(UUID().uuidString)")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        let source = home.appending(path: "source.bin")
        var data = Data(count: bytes)
        for index in stride(from: 0, to: bytes, by: 997) { data[index] = UInt8(index % 251) }
        try data.write(to: source)
        let pin = Pin(name: "thing.bin", urls: [source.absoluteString], sha256: try Hashing.sha256(of: source), size: Int64(bytes))
        return (home, source, pin)
    }

    @Test func reportsProgressAndEndsWithAVerifiedFile() throws {
        let (home, _, pin) = try makeSource(bytes: 2_000_000)
        defer { try? FileManager.default.removeItem(at: home) }
        let log = ProgressLog()
        let file = try Downloader(paths: Paths(home: home)).fetch(pin, WorkContext(progress: { log.add($0) }))
        #expect(try Hashing.sha256(of: file) == pin.sha256)
        let last = try #require(log.all.last)
        #expect(last.isVerifying)
        #expect(last.received == 2_000_000)
        #expect(last.fraction == 1)
    }

    @Test func theSizeOfAGrowingFileIsReadFreshEachTime() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "tannin-size-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(count: 10).write(to: file)
        #expect(Hashing.fileSize(file) == 10)
        // The same URL value is asked again after the file has grown, as the download watcher does.
        try Data(count: 5000).write(to: file)
        #expect(Hashing.fileSize(file) == 5000)
        #expect(Hashing.fileSize(file.appendingPathExtension("missing")) == nil)
    }

    @Test func picksUpAPartialFileWhereItStopped() throws {
        let (home, source, pin) = try makeSource(bytes: 2_000_000)
        defer { try? FileManager.default.removeItem(at: home) }
        let downloader = Downloader(paths: Paths(home: home))
        try FileManager.default.createDirectory(at: downloader.paths.downloads, withIntermediateDirectories: true)
        let partial = downloader.destination(for: pin).appendingPathExtension("part")
        try Data(contentsOf: source).prefix(700_000).write(to: partial)
        let file = try downloader.fetch(pin, WorkContext(quiet: true))
        #expect(try Hashing.sha256(of: file) == pin.sha256)
    }

    @Test func aCancelledDownloadThrowsAndLeavesNoFinishedFile() throws {
        let (home, _, pin) = try makeSource(bytes: 100_000)
        defer { try? FileManager.default.removeItem(at: home) }
        let downloader = Downloader(paths: Paths(home: home))
        let cancellation = Cancellation()
        cancellation.cancel()
        #expect(throws: Cancelled.self) { try downloader.fetch(pin, WorkContext(quiet: true, cancellation: cancellation)) }
        #expect(!FileManager.default.fileExists(atPath: downloader.destination(for: pin).path))
    }
}

@Suite struct CancellationTests {
    @Test func stopsARunningProgram() throws {
        let cancellation = Cancellation()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { cancellation.cancel() }
        let started = Date()
        #expect(throws: Cancelled.self) { try Shell.run("/bin/sleep", ["30"], cancellation: cancellation) }
        #expect(Date().timeIntervalSince(started) < 10)
    }
}

@Suite struct SetupStateTests {
    @Test func aBareMacHasEverythingToDoAndLaterStepsWait() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appending(path: "tannin-setup-\(UUID().uuidString)")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        let paths = Paths(home: home, steamApp: home.appending(path: "Applications/Steam.app"))
        let setup = Setup(paths: paths, rosetta: home.appending(path: "rosetta"))

        #expect(setup.state(of: .rosetta) == .ready)
        #expect(setup.state(of: .steam) == .ready)
        #expect(setup.state(of: .engine) == .ready)
        #expect(setup.state(of: .toolkit) == .ready)
        #expect(setup.state(of: .bridge) == .waiting("Needs the Wine engine first"))
        #expect(setup.state(of: .steamPlay) == .waiting("Needs the steps above first"))
        #expect(!setup.isReadyForSteamPlay)

        // Rosetta, Steam, the engine and an imported toolkit appear; the bridge can now be done.
        try Data().write(to: home.appending(path: "rosetta"))
        try fm.createDirectory(at: paths.steamMacOS, withIntermediateDirectories: true)
        try Data().write(to: paths.steamMacOS.appending(path: "steam_osx"))
        for file in Engine.requiredFiles {
            let url = Engine(paths: paths).wine.appending(path: file)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        let lib = paths.gptk.appending(path: "D3DMetal-4.0b3/lib/external")
        try fm.createDirectory(at: lib, withIntermediateDirectories: true)
        try Data().write(to: lib.appending(path: "libd3dshared.dylib"))

        #expect(setup.state(of: .rosetta) == .done("Installed"))
        #expect(setup.state(of: .steam) == .done("In Applications"))
        #expect(setup.state(of: .engine) == .done("Wine \(Pins.engineWine)"))
        #expect(setup.state(of: .toolkit) == .done("D3DMetal 4.0b3"))
        #expect(setup.state(of: .bridge) == .ready)
        #expect(setup.state(of: .steamPlay) == .waiting("Needs the steps above first"))
    }
}
