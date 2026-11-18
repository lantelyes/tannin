import Foundation
import Testing
@testable import TanninCore

/// The whole of setup short of touching Steam, run for real into a throwaway home folder: engine unpacked,
/// kit downloaded and staged, Valve files placed, ntdll patched from the recipe, runner built, D3DMetal linked.
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

        // D3DMetal, from this Mac's already imported copy when there is one. Apple's signature is checked again.
        if let toolkit = GPTK(paths: live).imported().last {
            let imported = try setup.importToolkit(from: toolkit.lib.deletingLastPathComponent())
            #expect(imported.version == toolkit.version)
            #expect(D3DMetalLink(paths: paths).linkedVersion() == toolkit.version)
            #expect(setup.state(of: .toolkit) == .done("D3DMetal \(toolkit.version)"))
            #expect(setup.state(of: .bridge) == .done("NotProton \(Pins.notProtonVersion)"))
            #expect(Runner(paths: paths).verify().allSatisfy { $0.state != .broken && $0.state != .attention })
        }

        // Nothing here went near Steam: it is not installed in this home, so the last step still waits.
        #expect(setup.state(of: .steamPlay) == .waiting("Needs the steps above first"))
    }
}
