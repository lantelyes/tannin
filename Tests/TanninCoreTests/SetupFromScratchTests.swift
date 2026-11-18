import Foundation
import Testing
@testable import TanninCore

/// The whole of setup short of touching Steam, run for real into a throwaway home folder: engine unpacked,
/// kit downloaded and staged, Valve files placed, ntdll patched from the recipe, runner built with DXMT in it,
/// first without Apple's toolkit, then as Tannin 0.2 left it and brought up to date, then with D3DMetal linked.
///
/// Opt-in, because it downloads and uses about 2 GB of disk for a minute:
///   TANNIN_E2E_SETUP=1 swift test --filter SetupFromScratch
/// The big engine archive and Valve's packages are borrowed from this Mac's own Tannin downloads when they are
/// there; the NotProton release is always fetched from the network, so a real download with progress is covered.
@Suite struct SetupFromScratchTests {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["TANNIN_E2E_SETUP"] == "1" }

    @Test(.enabled(if: isEnabled), .timeLimit(.minutes(15)))
    func aBareHomeEndsWithAVerifiedRunner() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appending(path: "tannin-e2e-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        let paths = Paths(home: home, steamApp: home.appending(path: "Applications/Steam.app"))
        try fm.createDirectory(at: paths.downloads, withIntermediateDirectories: true)

        let live = Paths.live
        for pin in [Pins.engine, Pins.valveLinux, Pins.valveWin64] {
            let cached = live.downloads.appending(path: pin.name)
            if fm.fileExists(atPath: cached.path) {
                try Shell.check("/bin/cp", ["-c", cached.path, paths.downloads.appending(path: pin.name).path])
            }
        }

        let setup = Setup(paths: paths, rosetta: home.appending(path: "no-rosetta"))
        #expect(setup.state(of: .engine) == .ready)
        #expect(setup.state(of: .bridge) == .waiting("Needs the Wine engine first"))

        let log = ProgressLog()
        let context = WorkContext(quiet: true, progress: { log.add($0) })

        try setup.installEngine(context)
        #expect(setup.state(of: .engine) == .done("Wine \(Pins.engineWine)"))
        #expect(setup.state(of: .bridge) == .ready)

        try setup.installBridge(context)
        let broken = Runner(paths: paths).verify().filter { $0.state == .broken }
        #expect(broken.isEmpty, "\(broken)")
        #expect(setup.state(of: .bridge) == .done("NotProton \(Pins.notProtonVersion)"))

        // The NotProton release came over the network: progress was reported along the way and ended in a check.
        let kit = log.all.filter { $0.name == Pins.notProton.name }
        #expect(kit.count > 1)
        #expect(kit.last?.isVerifying == true)
        #expect(kit.last?.received == Pins.notProton.size)

        // Without Apple's toolkit the runner is complete: DXMT answers for both bit widths and nothing is behind.
        let layers = LayerStore(paths: paths)
        let runner = Runner(paths: paths)
        #expect(runner.verify().allSatisfy { $0.state != .broken && $0.state != .attention })
        #expect(layers.isPrepared)
        #expect(layers.runnerHasDXMT(runner.root, arch: "x86_64"))
        #expect(layers.runnerHasDXMT(runner.root, arch: "i386"))
        #expect(InstallRecord.read(paths: paths)?.runners.first?.d3dMetalVersion == nil)
        #expect(InstallRecord.read(paths: paths)?.runners.first?.tannin == TanninVersion.current)
        let upkeep = Upkeep(paths: paths, gameIsRunning: { false })
        #expect(upkeep.plan().isEmpty)
        try setup.skipToolkit()
        #expect(setup.state(of: .toolkit).isSettled)

        // A runner as Tannin 0.2 built it: Wine's own 32-bit ntdll, no DXMT, no layer files. The after-update
        // step finds it, and one run brings it up to date.
        let engine = Engine(paths: paths)
        for arch in ["x86_64", "i386"] { try layers.putWineOwn(into: runner.root, arch: arch) }
        let oldNtdll = runner.root.appending(path: "lib/wine/i386-windows/ntdll.dll")
        try fm.removeItem(at: oldNtdll)
        try fm.copyItem(at: engine.wine.appending(path: "lib/wine/i386-windows/ntdll.dll"), to: oldNtdll)
        try fm.removeItem(at: paths.notproton.appending(path: "bridge/wine/\(Runner.build)/i386-windows"))
        try layers.remove()
        try fm.removeItem(at: paths.installRecord)
        #expect(!runner.verify().contains { $0.state == .broken })
        #expect(setup.state(of: .bridge) == .done("NotProton \(Pins.notProtonVersion)"))
        #expect(upkeep.plan() == [.graphicsLayers])
        #expect(throws: UpkeepError.self) { try Upkeep(paths: paths, gameIsRunning: { true }).run(.graphicsLayers) }
        #expect(upkeep.plan() == [.graphicsLayers])
        try upkeep.run(.graphicsLayers)
        #expect(upkeep.plan().isEmpty)
        #expect(runner.verify().allSatisfy { $0.state != .broken && $0.state != .attention })
        #expect(InstallRecord.read(paths: paths) != nil)

        // D3DMetal, from this Mac's already imported copy when there is one. Apple's signature is checked again.
        if let toolkit = GPTK(paths: live).imported().last {
            let imported = try setup.importToolkit(from: toolkit.lib.deletingLastPathComponent())
            #expect(imported.version == toolkit.version)
            #expect(!setup.toolkitIsSkipped)
            #expect(D3DMetalLink(paths: paths).linkedVersion() == toolkit.version)
            #expect(setup.state(of: .toolkit) == .done("D3DMetal \(toolkit.version)"))
            #expect(setup.state(of: .bridge) == .done("NotProton \(Pins.notProtonVersion)"))
            #expect(runner.verify().allSatisfy { $0.state != .broken && $0.state != .attention })
            // D3DMetal takes the 64-bit side; DXMT keeps the 32-bit side.
            #expect(!layers.runnerHasDXMT(runner.root, arch: "x86_64"))
            #expect(layers.runnerHasDXMT(runner.root, arch: "i386"))
            #expect(InstallRecord.read(paths: paths)?.runners.first?.d3dMetalVersion == toolkit.version)
            #expect(upkeep.plan().isEmpty)

            // Taking it out again leaves a runner that works without it.
            try D3DMetalLink(paths: paths).unlink()
            #expect(layers.runnerHasDXMT(runner.root, arch: "x86_64"))
            #expect(runner.verify().allSatisfy { $0.state != .broken && $0.state != .attention })
        }

        // Nothing here went near Steam: it is not installed in this home, so the last step still waits.
        #expect(setup.state(of: .steamPlay) == .waiting("Needs the steps above first"))
    }
}
