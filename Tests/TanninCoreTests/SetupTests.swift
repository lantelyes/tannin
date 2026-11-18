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
        #expect(setup.state(of: .bridge) == .waiting("Needs the Wine engine first"))
        #expect(setup.state(of: .steamPlay) == .waiting("Needs the steps above first"))
        #expect(!setup.isReadyForSteamPlay)

        // Rosetta, Steam and the engine appear; the bridge can now be done. D3DMetal on the Mac is no step.
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
        #expect(Setup.Step.allCases == [.rosetta, .steam, .engine, .bridge, .steamPlay])
        #expect(setup.state(of: .bridge) == .ready)
        #expect(setup.state(of: .steamPlay) == .waiting("Needs the steps above first"))
    }
}

@Suite struct SetupPhaseTests {
    private typealias States = [Setup.Step: Setup.State]

    private let bare: States = [.rosetta: .ready, .steam: .done("In Applications"), .engine: .ready,
                                .bridge: .waiting("Needs the Wine engine first"), .steamPlay: .waiting("Needs the steps above first")]
    private let usual: States = [.rosetta: .done("Installed"), .steam: .done("In Applications"), .engine: .ready,
                                 .bridge: .waiting("Needs the Wine engine first"), .steamPlay: .waiting("Needs the steps above first")]
    private let ready: States = [.rosetta: .done("Installed"), .steam: .done("In Applications"), .engine: .done("Wine 11.19"),
                                 .bridge: .done("NotProton 1.2.6"), .steamPlay: .ready]

    private func phase(_ states: States, _ progress: SetupProgress? = nil, failure: SetupFailure? = nil, steamPlay: SteamPlayAdd = .idle) -> SetupPhase {
        SetupPhase(states: states, progress: progress, failure: failure, steamPlay: steamPlay)
    }

    private func download(_ pin: Pin, _ received: Int64, verifying: Bool = false) -> DownloadProgress {
        DownloadProgress(name: pin.name, received: received, total: pin.size, isVerifying: verifying)
    }

    private let engine = Pins.engine.size ?? 0
    private var bridge: Int64 { Setup.downloads(for: .bridge).reduce(0) { $0 + ($1.size ?? 0) } }

    @Test func everyDownloadHasASizeSoTheWholeJobCanBeMeasured() {
        let pins = Setup.Step.allCases.flatMap(Setup.downloads(for:))
        #expect(pins.map(\.name) == [Pins.engine.name, Pins.notProton.name, Pins.valveLinux.name, Pins.valveWin64.name])
        #expect(pins.allSatisfy { ($0.size ?? 0) > 0 })
        #expect(Setup.downloadBytes == engine + bridge)
        #expect(Setup.downloadBytes == 653_952_951)
    }

    @Test func beforeAnythingIsReadAndBeforeAnythingIsStarted() {
        #expect(phase([:]) == .checking)
        #expect(phase(bare) == .before(needsRosetta: true, bytesLeft: Setup.downloadBytes, fraction: 0))
        #expect(phase(usual) == .before(needsRosetta: false, bytesLeft: Setup.downloadBytes, fraction: 0))

        var noSteam = usual
        noSteam[.steam] = .ready
        #expect(phase(noSteam) == .steamMissing)

        // Left part-way: the engine is here, the bridge is not.
        var partWay = usual
        partWay[.engine] = .done("Wine 11.19")
        partWay[.bridge] = .ready
        guard case let .before(needsRosetta, left, fraction) = phase(partWay) else {
            Issue.record("not before")
            return
        }
        #expect(!needsRosetta)
        #expect(left == bridge)
        #expect(abs(fraction - Setup.downloadShare * Double(engine) / Double(Setup.downloadBytes)) < 1e-9)
    }

    @Test func theBarCoversTheWholeJobAndTheAmountIsThePartInHand() {
        let total = Double(Setup.downloadBytes)
        func work(_ progress: SetupProgress) -> SetupWork? {
            if case let .working(work) = phase(usual, progress) { return work }
            return nil
        }

        #expect(work(SetupProgress(step: .rosetta)) == SetupWork(stage: .rosetta, fraction: nil, received: nil, total: nil))
        #expect(work(SetupProgress(step: .engine)) == SetupWork(stage: .engineDownload, fraction: 0, received: nil, total: nil))

        let half = work(SetupProgress(step: .engine, download: download(Pins.engine, 312_000_000)))
        #expect(half?.stage == .engineDownload)
        #expect(half?.received == 312_000_000)
        #expect(half?.total == engine)
        #expect(abs((half?.fraction ?? 0) - Setup.downloadShare * 312_000_000 / total) < 1e-9)

        let unpacking = work(SetupProgress(step: .engine, download: download(Pins.engine, engine, verifying: true)))
        #expect(unpacking?.stage == .engineUnpack)
        #expect(unpacking?.received == nil)
        let engineShare = Setup.downloadShare * Double(engine) / total
        #expect(abs((unpacking?.fraction ?? 0) - engineShare) < 1e-9)

        // The bridge starts where the engine ended, and its three files count as one amount.
        #expect(abs((work(SetupProgress(step: .bridge))?.fraction ?? 0) - engineShare) < 1e-9)
        #expect(work(SetupProgress(step: .bridge))?.stage == .bridgePrepare)

        let first = work(SetupProgress(step: .bridge, download: download(Pins.notProton, 10_000_000)))
        #expect(first?.stage == .bridgeDownload)
        #expect(first?.received == 10_000_000)
        #expect(first?.total == bridge)

        // A file that has just been checked is not the end unless it is the last one.
        let between = work(SetupProgress(step: .bridge, download: download(Pins.notProton, Pins.notProton.size ?? 0, verifying: true)))
        #expect(between?.stage == .bridgeDownload)

        let second = work(SetupProgress(step: .bridge, download: download(Pins.valveLinux, 1_000_000)))
        #expect(second?.received == (Pins.notProton.size ?? 0) + 1_000_000)

        let building = work(SetupProgress(step: .bridge, download: download(Pins.valveWin64, Pins.valveWin64.size ?? 0, verifying: true)))
        #expect(building?.stage == .bridgeBuild)
        #expect(abs((building?.fraction ?? 0) - Setup.downloadShare) < 1e-9)
        #expect(building?.canPause == false)
        #expect(half?.canPause == true)
        #expect(unpacking?.canPause == false)
        #expect(work(SetupProgress(step: .rosetta))?.canPause == false)
    }

    @Test func pausedAndFailedKeepWhereItHadGotTo() {
        let running = SetupProgress(step: .engine, download: download(Pins.engine, 312_000_000))
        var paused = running
        paused.isPaused = true
        guard case let .paused(work) = phase(usual, paused) else {
            Issue.record("not paused")
            return
        }
        #expect(work.received == 312_000_000)

        let stopped = SetupFailure(DownloadError.allSourcesFailed(name: "x", lastError: "curl: (6)"), during: paused)
        #expect(stopped.message == "The download stopped. Check your connection.")
        #expect(phase(usual, failure: stopped) == .failed(stopped.message, work))

        // A damaged file was removed, so nothing of it is left to count.
        let damaged = SetupFailure(DownloadError.wrongHash(name: "x", expected: "a", actual: "b"), during: running)
        #expect(damaged.message == "The download did not arrive whole, so it was removed.")
        #expect(phase(usual, failure: damaged) == .failed(damaged.message, SetupWork(stage: .engineDownload, fraction: 0, received: nil, total: nil)))

        let rosetta = SetupFailure(Cancelled(), during: SetupProgress(step: .rosetta))
        #expect(rosetta.message == "macOS could not install Rosetta. Check your connection.")

        let other = SetupFailure(SteamAddonError.steamMissing, during: SetupProgress(step: .bridge))
        #expect(other.message == SteamAddonError.steamMissing.description)

        // Something running wins over an old failure.
        #expect(phase(usual, running, failure: stopped) == .working(work))
    }

    @Test func theSteamPlayStepInEachState() {
        #expect(phase(ready) == .readyForSteamPlay)
        #expect(phase(ready, steamPlay: .adding) == .addingSteamPlay)
        #expect(phase(ready, steamPlay: SteamPlayAdd(SteamAddonError.notPermitted)) == .steamPlayRefused)
        #expect(phase(ready, steamPlay: SteamPlayAdd(SteamAddonError.steamStillRunning)) == .steamPlayFailed("Steam did not quit. Quit Steam and try again."))

        var foreign = ready
        foreign[.steamPlay] = .waiting("Another tool is loaded into Steam")
        #expect(phase(foreign) == .foreignTool)

        var done = ready
        done[.steamPlay] = .done("On")
        #expect(phase(done) == .done)
        // Once it is on, an earlier refusal no longer matters.
        #expect(phase(done, steamPlay: .refused) == .done)
    }

    @Test func coversComeIntoColourWithTheDownloadsAndTheLastWithSteamPlay() {
        #expect(phase(usual).lit(of: 7) == 0)
        let half = SetupProgress(step: .engine, download: download(Pins.engine, engine / 2))
        let lit = phase(usual, half).lit(of: 7)
        #expect(abs(lit - 6 * Setup.downloadShare * Double(engine / 2) / Double(Setup.downloadBytes)) < 1e-9)
        #expect(phase(usual, SetupProgress(step: .rosetta)).lit(of: 7) == 0)
        #expect(phase(ready).lit(of: 7) == 6)
        #expect(phase(ready, steamPlay: .adding).lit(of: 7) == 6)
        #expect(phase(ready, steamPlay: .refused).lit(of: 7) == 6)
        var done = ready
        done[.steamPlay] = .done("On")
        #expect(phase(done).lit(of: 7) == 7)
        #expect(phase(done).lit(of: 5) == 5)
        #expect(phase(ready).lit(of: 0) == 0)
    }
}
