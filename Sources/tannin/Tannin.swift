import ArgumentParser
import Foundation
import TanninCore

@main
struct Tannin: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tannin",
        abstract: "Free Steam Play for Mac: Windows games from the native Steam client.",
        version: TanninVersion.current,
        subcommands: [DoctorCommand.self, SetupCommand.self, EngineCommand.self, GPTKCommand.self, KitCommand.self, RunnerCommand.self, LayersCommand.self, UpkeepCommand.self, SteamCommand.self, GameCommand.self]
    )
}

struct GPTKCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gptk",
        abstract: "Apple's Game Porting Toolkit (D3DMetal), from your own download.",
        subcommands: [Import.self, Skip.self, Link.self, Unlink.self, Status.self]
    )

    struct Import: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Import D3DMetal from Apple's disk image after checking Apple's signature, then link it into the runner.")

        @Argument(help: "Apple's Game Porting Toolkit disk image, or an opened folder.")
        var source: String

        func run() throws {
            let toolkit = try GPTK().importToolkit(from: URL(fileURLWithPath: (source as NSString).expandingTildeInPath))
            print("Imported D3DMetal \(toolkit.version). Apple's signature verified.")
            try? FileManager.default.removeItem(at: Paths.live.toolkitSkipped)
            if FileManager.default.fileExists(atPath: Runner().root.appending(path: "lib/wine").path) {
                try D3DMetalLink().link(toolkit)
                try? InstallRecord.write()
                print("Linked into the runner.")
            }
        }
    }

    struct Skip: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Go without Apple's toolkit for now. Games then run on DXMT; Direct3D 12 games need the toolkit.")
        func run() throws {
            try Setup().skipToolkit()
            print("Skipped. Import it any time with: tannin gptk import <disk image>")
        }
    }

    struct Link: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Link the newest imported D3DMetal into the runner.")
        func run() throws {
            let toolkit = try GPTK().current()
            try D3DMetalLink().link(toolkit)
            try? InstallRecord.write()
            print("D3DMetal \(toolkit.version) linked into the runner.")
        }
    }

    struct Unlink: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Take D3DMetal out of the runner and put Wine's own files back.")
        func run() throws {
            try D3DMetalLink().unlink()
            try? InstallRecord.write()
            print("D3DMetal removed from the runner. Games now run on DXMT.")
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show imported and linked versions.")
        func run() throws {
            let imported = GPTK().imported().map(\.version)
            print("Imported: \(imported.isEmpty ? "none" : imported.joined(separator: ", "))")
            print("Linked:   \(D3DMetalLink().linkedVersion() ?? "none")")
        }
    }
}

struct SteamCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "steam",
        abstract: "Steam Play inside Steam.app.",
        subcommands: [Status.self, Enable.self, Disable.self, Freeze.self]
    )

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show whether Steam Play is in Steam. Changes nothing.")

        func run() throws {
            let steam = SteamInstall()
            let signature = steam.signature()
            switch SteamAddon().state() {
            case .off: print("Steam Play:    off")
            case .on: print("Steam Play:    on")
            case let .foreign(value): print("Steam Play:    another tool's library is loaded (\(value))")
            }
            print("Steam.app:     \(signature.isValve ? "signed by Valve" : "not Valve-signed (team \(signature.teamID ?? "none"), valid \(signature.valid))")")
            print("Steam build:   \(steam.clientBuild() ?? "unknown")")
            print("Steam running: \(steam.isRunning() ? "yes" : "no")")
            print("Update freeze: \(UpdateFreeze().isOn ? "on" : "off")")
        }
    }

    struct Enable: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Add Steam Play to Steam.app. Shows what will change; needs --yes to do it.")

        @Flag(name: .long, help: "Make the changes. Without this, only the list of changes is printed.")
        var yes = false

        func run() throws {
            let addon = SteamAddon()
            print("This will:")
            for (index, step) in addon.enablePlan().enumerated() { print("  \(index + 1). \(step)") }
            print("Your games, saves and Steam account are not touched. Valve does not support this.")
            print("To undo: tannin steam disable --yes")
            guard yes else {
                print("\nNothing was changed. Run again with --yes to proceed.")
                return
            }
            try addon.enable()
            print("\nDone.")
            try Status().run()
        }
    }

    struct Disable: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Put back Steam.app as Valve ships it. Shows what will change; needs --yes to do it.")

        @Flag(name: .long, help: "Make the changes. Without this, only the list of changes is printed.")
        var yes = false

        func run() throws {
            let addon = SteamAddon()
            print("This will:")
            for (index, step) in addon.disablePlan().enumerated() { print("  \(index + 1). \(step)") }
            guard yes else {
                print("\nNothing was changed. Run again with --yes to proceed.")
                return
            }
            try addon.disable()
            print("\nDone.")
            try Status().run()
        }
    }

    struct Freeze: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Stop or allow Steam updating itself at launch.")

        @Argument(help: "on or off")
        var state: String

        func run() throws {
            guard ["on", "off"].contains(state) else { throw ValidationError("Use: tannin steam freeze on|off") }
            try UpdateFreeze().set(state == "on")
            print("Update freeze: \(UpdateFreeze().isOn ? "on" : "off")")
        }
    }
}

struct GameCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "game",
        abstract: "How individual games run.",
        subcommands: [List.self, Use.self, Set.self, Options.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List installed Steam games and which ones run with Tannin.")

        @Flag(name: .long, help: "List the Windows games in the library instead, installed or not, as the app shows them.")
        var all = false

        func run() throws {
            guard all else {
                let config = SteamConfig()
                for app in SteamInstall().installedApps() {
                    let tool = config.compatTool(appID: app.appID)
                    let options = config.launchOptions(appID: app.appID)
                    print("\(app.appID)\t\(app.name)\t\(tool ?? "native")\(options.map { "\t\($0)" } ?? "")")
                }
                return
            }
            let library = LibraryReader().read()
            func line(_ game: LibraryGame) -> String {
                let bits = game.is32Bit.map { $0 ? "32-bit" : "64-bit" } ?? "unknown"
                let art = game.art.banner == nil ? "no art" : "art"
                return "\(game.appID)\t\(game.name)\t\(bits)\t\(art)\(game.launchOptions.isEmpty ? "" : "\t\(game.launchOptions)")"
            }
            print("Installed (\(library.installed.count)):")
            library.installed.forEach { print("  " + line($0) + ($0.install == .installing ? "\tinstalling" : "")) }
            print("Not installed (\(library.notInstalled.count)):")
            library.notInstalled.forEach { print("  " + line($0)) }
        }
    }

    struct Use: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Run a game with Tannin's runner (Steam must be closed).")

        @Argument(help: "The game's Steam app ID.")
        var appID: String

        @Flag(name: .long, help: "Clear the choice instead, so Steam treats the game as before.")
        var clear = false

        func run() throws {
            guard appID.allSatisfy(\.isNumber) else { throw ValidationError("The app ID is a number, for example 1544360.") }
            try SteamConfig().setCompatTool(appID: appID, enabled: !clear)
            print(clear ? "Cleared for \(appID)." : "\(appID) will run with \(Runner.display).")
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Set how a game runs. Writes its Steam launch options (Steam must be closed). Anything not named stays as it is.")

        @Argument(help: "The game's Steam app ID.")
        var appID: String

        @Option(name: .long, help: "Graphics layer: automatic, d3dmetal, dxmt or dxvk.") var layer: String?
        @Option(name: .long, help: "Ray tracing (D3DMetal): on or off.") var dxr: String?
        @Option(name: .long, help: "MetalFX upscaling (D3DMetal): on or off.") var metalfx: String?
        @Option(name: .long, help: "Metal 4 renderer (D3DMetal): on or off.") var metal4: String?
        @Option(name: .long, help: "Upscaling (DXMT): off, 1.5, 2 or 3.") var upscale: String?
        @Option(name: .customLong("async"), help: "Prepare effects in the background (DXVK): on or off.") var background: String?
        @Option(name: .long, help: "Frame cap in frames per second. 0 for none.") var cap: Int?
        @Option(name: .long, help: "Performance overlay: on or off.") var hud: String?
        @Flag(name: .long, help: "Start from nothing set instead of from the game's present settings.") var reset = false

        func toggle(_ value: String?, _ name: String) throws -> Bool? {
            guard let value else { return nil }
            guard ["on", "off"].contains(value) else { throw ValidationError("--\(name) takes on or off.") }
            return value == "on"
        }

        func run() throws {
            guard appID.allSatisfy(\.isNumber) else { throw ValidationError("The app ID is a number, for example 1544360.") }
            let config = SteamConfig()
            let existing = config.launchOptions(appID: appID) ?? ""
            var settings = reset ? GameSettings() : GameSettings(parsing: existing)
            if let layer {
                let names: [String: GraphicsLayer] = ["automatic": .automatic, "d3dmetal": .d3dMetal, "dxmt": .dxmt, "dxvk": .dxvk]
                guard let chosen = names[layer.lowercased()] else { throw ValidationError("--layer takes automatic, d3dmetal, dxmt or dxvk.") }
                settings.layer = chosen
            }
            if let value = try toggle(dxr, "dxr") { settings.rayTracing = value }
            if let value = try toggle(metalfx, "metalfx") { settings.metalFX = value }
            if let value = try toggle(metal4, "metal4") { settings.metal4 = value }
            if let value = try toggle(background, "async") { settings.backgroundEffects = value }
            if let value = try toggle(hud, "hud") { settings.performanceHUD = value }
            if let cap { settings.frameCap = cap > 0 ? cap : nil }
            if let upscale {
                guard let factor = upscale == "off" ? 0 : Double(upscale), GameSettings.upscalingFactors.contains(factor) else {
                    throw ValidationError("--upscale takes off, 1.5, 2 or 3.")
                }
                settings.upscaling = factor > 0 ? factor : nil
            }
            let options = settings.launchOptions(merging: existing)
            try config.setLaunchOptions(appID: appID, options)
            print("Launch options for \(appID): \(options.isEmpty ? "(none)" : options)")
        }
    }

    struct Options: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show a game's Steam launch options, or replace them word for word (Steam must be closed).")

        @Argument(help: "The game's Steam app ID.")
        var appID: String

        @Option(name: .customLong("set"), help: "The launch options to write, exactly as given. An empty text clears them.")
        var text: String?

        func run() throws {
            guard appID.allSatisfy(\.isNumber) else { throw ValidationError("The app ID is a number, for example 1544360.") }
            let config = SteamConfig()
            if let text { try config.setLaunchOptions(appID: appID, text) }
            let options = config.launchOptions(appID: appID) ?? ""
            print(options.isEmpty ? "(none)" : options)
        }
    }
}

struct UpkeepCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "upkeep",
        abstract: "After a Tannin update: bring what an earlier version installed up to date.",
        subcommands: [Status.self, Run.self]
    )

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show what is behind. Changes nothing.")
        func run() {
            let plan = Upkeep().plan()
            if plan.isEmpty { print("Everything is up to date.") }
            for item in plan { print("\(item.rawValue): \(item.title). \(item.detail)") }
            if let record = InstallRecord.read() {
                for runner in record.runners {
                    print("Recorded: \(runner.tool), Wine \(runner.wineVersion), D3DMetal \(runner.d3dMetalVersion ?? "none"), built by Tannin \(runner.tannin)")
                }
            } else {
                print("No install record (an install made by Tannin 0.2, or nothing installed).")
            }
        }
    }

    struct Run: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Do everything that is behind. Does not touch Steam.app.")
        func run() throws {
            let upkeep = Upkeep()
            let plan = upkeep.plan()
            if plan.isEmpty { print("Everything is up to date."); return }
            for item in plan {
                try upkeep.run(item)
                print("Done: \(item.title)")
            }
        }
    }
}

struct LayersCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "layers",
        abstract: "The graphics layers a game can be given: D3DMetal, DXMT, DXVK.",
        subcommands: [Status.self, Prepare.self]
    )

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show which layers are in place.")
        func run() {
            let layers = LayerStore()
            let runner = Runner().root
            print("D3DMetal:  \(D3DMetalLink().linkedVersion().map { "\($0), in the runner" } ?? "not added")")
            print("DXMT:      \(LayerStore.dxmtVersion), runner 64-bit: \(layers.runnerHasDXMT(runner, arch: "x86_64") ? "yes" : "no"), 32-bit: \(layers.runnerHasDXMT(runner, arch: "i386") ? "yes" : "no")")
            print("DXVK:      \(LayerStore.dxvkVersion)")
            print("Per game:  \(layers.isPrepared ? "ready (\(layers.root.path))" : "not prepared")")
        }
    }

    struct Prepare: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Put DXMT into the runner and write the files for choosing a layer per game. Downloads nothing and does not touch Steam.")
        func run() throws {
            try LayerStore().addToRunner()
            Status().run()
        }
    }
}

/// Prints checks the same way everywhere; returns false if anything is broken.
@discardableResult
func printChecks(_ checks: [Check]) -> Bool {
    let width = checks.map(\.name.count).max() ?? 0
    for check in checks {
        let label = "[\(check.state.rawValue)]".padding(toLength: 12, withPad: " ", startingAt: 0)
        let name = check.name.padding(toLength: width + 2, withPad: " ", startingAt: 0)
        print("\(label)\(name)\(check.detail)")
    }
    return !checks.contains { $0.state == .broken }
}

struct RunnerCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "runner",
        abstract: "The copy of the engine that Steam launches games with.",
        subcommands: [Build.self, Verify.self]
    )

    struct Build: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Assemble the runner from the engine, the patched ntdll and the bridge. Does not touch Steam.")

        func run() throws {
            try Runner().build(patch: NtdllPatch())
            // A rebuild starts from a fresh copy of the engine, so put the imported D3DMetal back in.
            if let toolkit = try? GPTK().current() {
                try D3DMetalLink().link(toolkit)
            }
            try Verify().run()
        }
    }

    struct Verify: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Check everything the Steam add-on's launch script will look for.")

        func run() throws {
            if !printChecks(Runner().verify()) { throw ExitCode(1) }
        }
    }
}

struct KitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "kit",
        abstract: "The Steam Play kit: Steam add-on, Steam bridge and Valve's client files.",
        subcommands: [Install.self, Status.self]
    )

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Download, verify and stage the kit. Does not touch Steam.")

        func run() throws {
            let kit = NotProtonKit()
            print("NotProton \(Pins.notProtonVersion) release…")
            try kit.unpack()
            try kit.stage()
            print("Valve client files…")
            try kit.installValveFiles()
            try Status().run()
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show what is staged.")

        func run() throws {
            let kit = NotProtonKit()
            guard kit.isUnpacked else {
                print("Not installed. Run: tannin kit install")
                return
            }
            let missing = kit.missingStagedFiles()
            print("Add-on:   \(kit.addonDylib.path)")
            print("Staged:   \(kit.paths.notproton.path)")
            print(missing.isEmpty ? "Complete: every expected file is in place." : "Missing:  \(missing.joined(separator: ", "))")
        }
    }
}

struct EngineCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "engine",
        abstract: "The Wine engine.",
        subcommands: [Install.self, Status.self]
    )

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Download, verify and unpack the Wine engine (479 MB).")

        func run() throws {
            let engine = Engine()
            if engine.isInstalled {
                print("Already installed at \(engine.root.path)")
            } else {
                print("Downloading Wine engine \(Pins.engineVersion) (Wine \(Pins.engineWine))…")
                try engine.install()
                print("Installed at \(engine.root.path)")
            }
            try Status().run()
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show the installed engine.")

        func run() throws {
            let engine = Engine()
            guard engine.isInstalled else {
                print("Not installed. Run: tannin engine install")
                return
            }
            print("Engine:        winecx-gptk \(Pins.engineVersion)")
            print("Reports:       \(try engine.reportedVersion())")
            print("ntdll x86_64:  \(try engine.cleanNtdllHash(arch: "x86_64"))")
            print("ntdll i386:    \(try engine.cleanNtdllHash(arch: "i386"))")
        }
    }
}

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check whether this Mac is ready. Changes nothing unless --probe-steam is given."
    )

    @Flag(name: .long, help: "Also test whether macOS lets Tannin change Steam.app (creates and removes one empty file inside it).")
    var probeSteam = false

    func run() throws {
        if !printChecks(Doctor().run(probeSteam: probeSteam)) { throw ExitCode(1) }
    }
}

struct SetupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Show the setup steps the app walks through and which are done. Changes nothing."
    )

    func run() throws {
        for (step, state) in Setup().states() {
            let text = switch state {
            case let .done(detail): "done     \(detail)"
            case .ready: "to do"
            case let .waiting(reason): "waiting  \(reason)"
            case let .skipped(detail): "skipped  \(detail)"
            }
            print("\(step.rawValue.padding(toLength: 11, withPad: " ", startingAt: 0))\(text)")
        }
    }
}
