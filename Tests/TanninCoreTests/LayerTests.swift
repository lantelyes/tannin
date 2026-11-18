import Foundation
import Testing
@testable import TanninCore

/// A made-up engine with just the files the layer code reads.
private func makeEngine() throws -> Paths {
    let fm = FileManager.default
    let home = fm.temporaryDirectory.appending(path: "tannin-layers-\(UUID().uuidString)")
    let paths = Paths(home: home, steamApp: home.appending(path: "Applications/Steam.app"))
    let engine = Engine(paths: paths)
    func write(_ url: URL, _ data: Data) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
    for file in Engine.requiredFiles { try write(engine.wine.appending(path: file), Data()) }
    for (folder, arch) in [("x64", "x86_64"), ("x32", "i386")] {
        for name in LayerStore.dxmtFiles { try write(engine.root.appending(path: "DXMT/\(folder)/\(name)"), dll("dxmt \(arch) \(name)", builtin: false)) }
        for name in LayerStore.wineFiles { try write(engine.wine.appending(path: "lib/wine/\(arch)-windows/\(name)"), dll("wine \(arch) \(name)", builtin: true)) }
    }
    for name in LayerStore.dxvkFiles { try write(engine.root.appending(path: "DXVK/x64/\(name)"), dll("dxvk \(name)", builtin: false)) }
    return paths
}

/// The first bytes of a Windows DLL: "MZ", padding to 0x40, then either Wine's mark or the usual DOS stub.
private func dll(_ label: String, builtin: Bool) -> Data {
    var data = Data("MZ".utf8) + Data(repeating: 0, count: BuiltinMark.offset - 2)
    data += builtin ? BuiltinMark.text : BuiltinMark.dosStub
    return data + Data(label.utf8)
}

@Suite struct BuiltinMarkTests {
    @Test func writesTheMarkOverTheDosStubOnly() throws {
        let marked = try BuiltinMark.marked(dll("x", builtin: false), name: "x.dll")
        #expect(BuiltinMark.isMarked(marked))
        #expect(marked.count == dll("x", builtin: false).count)
        #expect(marked.suffix(1) == Data("x".utf8))
        #expect(try BuiltinMark.marked(marked, name: "x.dll") == marked)
    }

    @Test func refusesAFileItDoesNotRecognise() {
        #expect(throws: LayerError.self) { try BuiltinMark.marked(Data(repeating: 7, count: 200), name: "x.dll") }
        var odd = dll("x", builtin: false)
        odd[BuiltinMark.offset] = 0x55
        #expect(throws: LayerError.self) { try BuiltinMark.marked(odd, name: "x.dll") }
        #expect(throws: LayerError.self) { try BuiltinMark.marked(Data("MZ".utf8), name: "x.dll") }
    }
}

@Suite struct LayerStoreTests {
    @Test func buildsTheTreesAndBothDescriptors() throws {
        let paths = try makeEngine()
        defer { try? FileManager.default.removeItem(at: paths.home) }
        let layers = LayerStore(paths: paths)
        #expect(!layers.isPrepared)
        try layers.prepare()
        #expect(layers.isPrepared)

        // DXMT's files are marked for Wine; DXVK's stay as they are; "plain" holds Wine's own.
        for arch in ["x86_64", "i386"] {
            for name in LayerStore.dxmtFiles {
                #expect(BuiltinMark.isMarked(layers.root.appending(path: "dxmt/\(arch)-windows/\(name)")), "\(arch) \(name)")
            }
        }
        let d3d10 = try Data(contentsOf: layers.root.appending(path: "dxmt/x86_64-windows/d3d10.dll"))
        #expect(d3d10 == dll("wine x86_64 d3d10.dll", builtin: true))
        #expect(!FileManager.default.fileExists(atPath: layers.root.appending(path: "dxmt/i386-windows/d3d10.dll").path))
        #expect(try Data(contentsOf: layers.root.appending(path: "plain/x86_64-windows/dxgi.dll")) == dll("wine x86_64 dxgi.dll", builtin: true))
        #expect(!BuiltinMark.isMarked(layers.root.appending(path: "dxvk/d3d11.dll")))

        let variants = try String(contentsOf: paths.notproton.appending(path: "variants/tannin.conf"), encoding: .utf8)
        #expect(variants.contains("[tannin-dxmt]"))
        #expect(variants.contains("[tannin-plain]"))
        #expect(variants.contains("src = \(layers.root.path)/dxmt"))
        #expect(variants.contains("remove = x86_64-windows/d3d12.dll"))
        #expect(variants.components(separatedBy: "build = \(Runner.build)").count == 3)
        let plugins = try String(contentsOf: paths.notproton.appending(path: "plugins/tannin.conf"), encoding: .utf8)
        #expect(plugins.contains("[NOTPROTON_TANNIN_DXVK]"))
        #expect(plugins.contains("overrides = d3d11,d3d10core=n,b"))
        #expect(plugins.contains("tools = notproton-tannin*"))

        try layers.remove()
        #expect(!layers.isPrepared)
        #expect(!FileManager.default.fileExists(atPath: layers.root.path))
    }

    @Test func aMissingOrUnexpectedEngineFileChangesNothing() throws {
        let paths = try makeEngine()
        defer { try? FileManager.default.removeItem(at: paths.home) }
        try FileManager.default.removeItem(at: Engine(paths: paths).root.appending(path: "DXVK/x64/d3d11.dll"))
        #expect(throws: LayerError.self) { try LayerStore(paths: paths).prepare() }
        #expect(!FileManager.default.fileExists(atPath: paths.notproton.appending(path: "variants/tannin.conf").path))
        #expect(!FileManager.default.fileExists(atPath: LayerStore(paths: paths).root.path))
    }

    @Test func putsDXMTIntoARunnerAndTakesItOutAgain() throws {
        let paths = try makeEngine()
        defer { try? FileManager.default.removeItem(at: paths.home) }
        let layers = LayerStore(paths: paths)
        let runner = Runner(paths: paths).root
        try Shell.check("/bin/mkdir", ["-p", runner.deletingLastPathComponent().path])
        try Shell.check("/bin/cp", ["-R", Engine(paths: paths).wine.path, runner.path])

        #expect(!layers.runnerHasDXMT(runner, arch: "i386"))
        try layers.putDXMT(into: runner, arch: "i386")
        #expect(layers.runnerHasDXMT(runner, arch: "i386"))
        #expect(!layers.runnerHasDXMT(runner, arch: "x86_64"))
        #expect(BuiltinMark.isMarked(runner.appending(path: "lib/wine/i386-windows/dxgi.dll")))

        try layers.putWineOwn(into: runner, arch: "i386")
        #expect(!layers.runnerHasDXMT(runner, arch: "i386"))
        #expect(try Data(contentsOf: runner.appending(path: "lib/wine/i386-windows/d3d11.dll")) == dll("wine i386 d3d11.dll", builtin: true))
    }
}

@Suite struct GraphicsLayerTests {
    @Test func automaticGoesByBitsAndWhetherTheToolkitIsThere() {
        #expect(GraphicsLayer.automaticChoice(is32Bit: false, toolkitAdded: true) == .d3dMetal)
        #expect(GraphicsLayer.automaticChoice(is32Bit: true, toolkitAdded: true) == .dxmt)
        #expect(GraphicsLayer.automaticChoice(is32Bit: false, toolkitAdded: false) == .dxmt)
        #expect(GraphicsLayer.automaticChoice(is32Bit: nil, toolkitAdded: false) == .dxmt)
        #expect(GraphicsLayer.automaticChoice(is32Bit: nil, toolkitAdded: true) == nil)
    }

    @Test func onlyDXMTIsOfferedToA32BitGame() {
        #expect(GraphicsLayer.allCases.filter { $0.isOffered(is32Bit: true, toolkitAdded: true) } == [.automatic, .dxmt])
        #expect(GraphicsLayer.allCases.filter { $0.isOffered(is32Bit: false, toolkitAdded: false) } == [.automatic, .dxmt, .dxvk])
        #expect(GraphicsLayer.allCases.filter { $0.isOffered(is32Bit: false, toolkitAdded: true) } == GraphicsLayer.allCases)
    }
}

@Suite struct LayerSettingsTests {
    @Test func eachLayerWritesItsOwnWords() {
        let user = "MY_FLAG=1 %command% -windowed"
        #expect(GameSettings(layer: .d3dMetal, metalFX: true, frameCap: 60).launchOptions()
            == "NOTPROTON_ENV_TANNIN_LAYER=d3dmetal D3DM_ENABLE_METALFX=1 D3DM_MAX_FPS=60 %command%")
        #expect(GameSettings(layer: .dxmt, frameCap: 60).launchOptions()
            == "NOTPROTON_RUNNER_VARIANT=tannin-dxmt DXMT_CONFIG=d3d11.preferredMaxFrameRate=60 %command%")
        #expect(GameSettings(layer: .dxvk, frameCap: 60, backgroundEffects: true).launchOptions(merging: user)
            == "NOTPROTON_RUNNER_VARIANT=tannin-plain NOTPROTON_TANNIN_DXVK=1 DXVK_ASYNC=1 DXVK_FRAME_RATE=60 MY_FLAG=1 %command% -windowed")
        // Two DXMT settings share one variable, quoted because Steam hands the options to a shell.
        #expect(GameSettings(layer: .dxmt, frameCap: 30, performanceHUD: true, upscaling: 2).launchOptions()
            == "NOTPROTON_RUNNER_VARIANT=tannin-dxmt DXMT_METALFX_SPATIAL_SWAPCHAIN=1 DXMT_CONFIG=\"d3d11.preferredMaxFrameRate=30;d3d11.metalSpatialUpscaleFactor=2.0\" MTL_HUD_ENABLED=1 %command%")
    }

    @Test func aLayerLeavesOutWhatBelongsToAnother() {
        let everything = GameSettings(layer: .dxvk, rayTracing: true, metalFX: true, frameCap: 0, metal4: false, upscaling: 1.5, backgroundEffects: false)
        #expect(everything.launchOptions() == "NOTPROTON_RUNNER_VARIANT=tannin-plain NOTPROTON_TANNIN_DXVK=1 DXVK_ASYNC=0 %command%")
        #expect(everything.keeping(onlyWhatAppliesTo: .dxmt) == GameSettings(layer: .dxvk, frameCap: 0, upscaling: 1.5))
        #expect(everything.keeping(onlyWhatAppliesTo: nil) == GameSettings(layer: .dxvk, frameCap: 0))
    }

    @Test func everyLayerSurvivesBeingWrittenAndReadBack() {
        let cases = [
            GameSettings(layer: .automatic, rayTracing: true, frameCap: 120, upscaling: 3),
            GameSettings(layer: .d3dMetal, metalFX: true, frameCap: 60, performanceHUD: true, metal4: false),
            GameSettings(layer: .dxmt, frameCap: 30, performanceHUD: true, upscaling: 1.5),
            GameSettings(layer: .dxmt, upscaling: 2),
            GameSettings(layer: .dxvk, frameCap: 60, backgroundEffects: true),
        ]
        for settings in cases {
            #expect(GameSettings(parsing: settings.launchOptions(merging: "MY_FLAG=1 %command%")) == settings, "\(settings.layer)")
        }
    }

    @Test func changingLayerClearsTheOldLayersWordsAndKeepsTheUsers() {
        let dxvk = GameSettings(layer: .dxvk, frameCap: 60, backgroundEffects: true).launchOptions(merging: "MY_FLAG=1 %command%")
        #expect(GameSettings(layer: .automatic).launchOptions(merging: dxvk) == "MY_FLAG=1 %command%")
        #expect(GameSettings().launchOptions(merging: GameSettings(layer: .dxmt, upscaling: 2).launchOptions()) == "")
    }

    @Test func theUsersOwnVariantAndDXMTClausesAreKept() {
        // A variant of the user's own stays until a layer needs the place.
        #expect(GameSettings(frameCap: 60).launchOptions(merging: "NOTPROTON_RUNNER_VARIANT=mine %command%")
            == "D3DM_MAX_FPS=60 DXMT_CONFIG=d3d11.preferredMaxFrameRate=60 NOTPROTON_RUNNER_VARIANT=mine %command%")
        #expect(GameSettings(layer: .dxmt).launchOptions(merging: "NOTPROTON_RUNNER_VARIANT=mine %command%")
            == "NOTPROTON_RUNNER_VARIANT=tannin-dxmt %command%")
        // A DXMT setting Tannin does not manage is carried along.
        #expect(GameSettings(layer: .dxmt, frameCap: 60).launchOptions(merging: "DXMT_CONFIG=\"d3d11.other=1;d3d11.preferredMaxFrameRate=30\" %command%")
            == "NOTPROTON_RUNNER_VARIANT=tannin-dxmt DXMT_CONFIG=\"d3d11.other=1;d3d11.preferredMaxFrameRate=60\" %command%")
    }

    @Test func presetsFollowTheLayerAndNeverChangeIt() {
        #expect(GamePreset.bestSpeed.settings(layer: .automatic, effective: .d3dMetal) == GameSettings(metalFX: true))
        // Best speed belongs to D3DMetal alone; the other layers have nothing that buys speed.
        #expect(GamePreset.bestSpeed.settings(layer: .dxvk, effective: .dxvk) == nil)
        #expect(GamePreset.bestSpeed.settings(layer: .dxmt, effective: .dxmt) == nil)
        #expect(GamePreset.offered(effective: .dxmt) == [.recommended, .bestBattery, .custom])
        #expect(GamePreset.offered(effective: .dxvk) == [.recommended, .bestBattery, .custom])
        #expect(GamePreset(matching: GameSettings(layer: .dxvk, backgroundEffects: true), effective: .dxvk) == .custom)
        #expect(GamePreset.offered(effective: .d3dMetal) == GamePreset.allCases)
        #expect(GamePreset(matching: GameSettings(layer: .dxmt, frameCap: 30), effective: .dxmt) == .bestBattery)
        #expect(GamePreset(matching: GameSettings(layer: .dxmt), effective: .dxmt) == .recommended)
        #expect(GamePreset(matching: GameSettings(layer: .dxmt, upscaling: 2), effective: .dxmt) == .custom)
        for preset in GamePreset.allCases {
            #expect(preset.settings(layer: .dxvk, effective: .dxvk).map(\.layer) ?? .dxvk == .dxvk)
        }
    }
}

@Suite struct LayerUsageTests {
    @Test func readsTheLayerFromItsOwnLinesInAGamesLog() {
        let dxmt = "msync: up and running.\ninfo:  Found config env: d3d11.preferredMaxFrameRate=60\ninfo:  Maximum supported feature level: D3D_FEATURE_LEVEL_11_1\ninfo:  Using feature level D3D_FEATURE_LEVEL_10_1\n"
        let dxvk = "warn:  D3D11CoreCreateDevice: Adapter is not a DXVK adapter\ninfo:  DXVK: v1.10.3-20230507-async (macOS)\ninfo:  D3D11CoreCreateDevice: Maximum supported feature level: D3D_FEATURE_LEVEL_11_1\n"
        let d3dMetal = "msync: up and running.\n Error Domain=com.apple.appleneuralengine Code=26\n"
        let quiet = "msync: up and running.\n[mvk-info] MoltenVK version 1.4.2\n"
        #expect(LayerUsage.reading(wineLog: dxmt, d3dMetalPossible: true) == .dxmt)
        #expect(LayerUsage.reading(wineLog: dxvk, d3dMetalPossible: true) == .dxvk)
        #expect(LayerUsage.reading(wineLog: d3dMetal, d3dMetalPossible: true) == .d3dMetal)
        #expect(LayerUsage.reading(wineLog: d3dMetal, d3dMetalPossible: false) == nil)
        // Nothing to go on: say nothing rather than guess.
        #expect(LayerUsage.reading(wineLog: quiet, d3dMetalPossible: true) == nil)
    }

    @Test func aListOfLoadedLibrariesSettlesIt() {
        let nine = #"012c:trace:loaddll:build_module Loaded L"C:\\windows\\system32\\d3d9.dll" at 7BB30000: builtin"# + "\n"
        let eleven = #"0130:trace:loaddll:build_module Loaded L"C:\\windows\\system32\\d3d11.dll" at 00006FFFFC5A0000: builtin"# + "\n"
        #expect(LayerUsage.reading(wineLog: nine, d3dMetalPossible: false) == .wineOwn)
        #expect(LayerUsage.reading(wineLog: nine + eleven, d3dMetalPossible: true) == .d3dMetal)
        #expect(LayerUsage.reading(wineLog: nine + eleven, d3dMetalPossible: false) == nil)
    }

    @Test func aGameThatNeverRanHasNoAnswer() throws {
        let paths = try makeEngine()
        defer { try? FileManager.default.removeItem(at: paths.home) }
        #expect(LayerUsage.lastRun(appID: "1", is32Bit: false, paths: paths) == nil)
    }
}

@Suite struct OptionalToolkitTests {
    @Test func skippingTheToolkitIsRememberedAndUndoneByImporting() throws {
        let paths = try makeEngine()
        defer { try? FileManager.default.removeItem(at: paths.home) }
        let setup = Setup(paths: paths, rosetta: paths.home.appending(path: "rosetta"))
        #expect(setup.state(of: .toolkit) == .ready)
        try setup.skipToolkit()
        #expect(setup.toolkitIsSkipped)
        guard case .skipped = setup.state(of: .toolkit) else { Issue.record("not skipped"); return }
        #expect(setup.state(of: .toolkit).isSettled)
        #expect(!setup.state(of: .toolkit).isDone)

        // An imported toolkit wins over the mark.
        let lib = paths.gptk.appending(path: "D3DMetal-4.0b3/lib/external")
        try FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
        try Data().write(to: lib.appending(path: "libd3dshared.dylib"))
        #expect(setup.state(of: .toolkit) == .done("D3DMetal 4.0b3"))
    }

    @Test func steamPlayDoesNotWaitForTheToolkit() {
        #expect(!Setup.required.contains(.toolkit))
        #expect(Setup.required == [.rosetta, .steam, .engine, .bridge])
    }

    @Test func aMissingToolkitIsNotAnUnfinishedSetup() {
        let status = TanninStatus(
            steamInstalled: true, steamPlay: .on, steamBuild: "1", steamRunning: false, steamIsValveSigned: false,
            addonLoaded: true, updateFreeze: true, engineInstalled: true, engineWine: "11.19", d3dMetalVersion: nil,
            bridgeVersion: "1.2.6", runnerProblems: []
        )
        #expect(status.headline == .ready)
    }
}

@Suite struct InstallRecordTests {
    @Test func theVersionInCodeIsTheOneInTheVersionFile() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appending(path: "VERSION"), encoding: .utf8)
        #expect(text.trimmingCharacters(in: .whitespacesAndNewlines) == TanninVersion.current)
    }

    @Test func nothingInstalledHasNoRecordAndNothingToBringUpToDate() throws {
        let paths = try makeEngine()
        defer { try? FileManager.default.removeItem(at: paths.home) }
        #expect(InstallRecord.read(paths: paths) == nil)
        #expect(InstallRecord.current(paths: paths) == nil)
        try InstallRecord.write(paths: paths)
        #expect(!FileManager.default.fileExists(atPath: paths.installRecord.path))
        #expect(Upkeep(paths: paths, gameIsRunning: { false }).plan().isEmpty)
    }

    @Test func aBuiltRunnerIsRecordedAndReadBack() throws {
        let paths = try makeEngine()
        defer { try? FileManager.default.removeItem(at: paths.home) }
        let runner = Runner(paths: paths).root
        try Shell.check("/bin/mkdir", ["-p", runner.deletingLastPathComponent().path])
        try Shell.check("/bin/cp", ["-R", Engine(paths: paths).wine.path, runner.path])
        try InstallRecord.write(paths: paths)
        let record = try #require(InstallRecord.read(paths: paths))
        #expect(record == InstallRecord.current(paths: paths))
        #expect(record.shared.bridgeVersion == Pins.notProtonVersion)
        #expect(record.runners.map(\.tool) == [Runner.toolName])
        #expect(record.runners.first?.d3dMetalVersion == nil)
        #expect(record.runners.first?.tannin == TanninVersion.current)
        #expect(record.runners.first?.ntdll.keys.sorted() == ["i386", "x86_64"])
    }
}
