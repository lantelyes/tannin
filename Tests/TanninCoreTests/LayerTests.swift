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
        #expect(plugins.contains("tools = notproton-tannin\n"))

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

@Suite struct RendererInEffectTests {
    @Test func aRendererChosenByNameIsTheOneInEffect() {
        for chosen in [GraphicsLayer.d3dMetal, .dxmt, .dxvk] {
            #expect(GraphicsLayer.inEffect(chosen: chosen, is32Bit: false, toolkitAdded: true, lastRan: .wineOwn) == chosen)
        }
    }

    @Test func automaticComesToWhatTheGameGets() {
        #expect(GraphicsLayer.inEffect(chosen: .automatic, is32Bit: false, toolkitAdded: true, lastRan: nil) == .d3dMetal)
        #expect(GraphicsLayer.inEffect(chosen: .automatic, is32Bit: false, toolkitAdded: false, lastRan: .dxmt) == .dxmt)
        #expect(GraphicsLayer.inEffect(chosen: .automatic, is32Bit: true, toolkitAdded: true, lastRan: nil) == .dxmt)
        // Not installed yet, so its bit width is not known.
        #expect(GraphicsLayer.inEffect(chosen: .automatic, is32Bit: nil, toolkitAdded: true, lastRan: nil) == nil)
        // A Direct3D 9 game is drawn by Wine itself.
        #expect(GraphicsLayer.inEffect(chosen: .automatic, is32Bit: true, toolkitAdded: true, lastRan: .wineOwn) == nil)
    }

    @Test func d3dMetalChosenButNotOnTheMacIsDrawnByDXMT() {
        #expect(GraphicsLayer.inEffect(chosen: .d3dMetal, is32Bit: false, toolkitAdded: false, lastRan: nil) == .d3dMetal)
        #expect(GraphicsLayer.drawing(chosen: .d3dMetal, is32Bit: false, toolkitAdded: false, lastRan: nil) == .dxmt)
        #expect(GraphicsLayer.drawing(chosen: .d3dMetal, is32Bit: false, toolkitAdded: true, lastRan: nil) == .d3dMetal)
        #expect(GraphicsLayer.drawing(chosen: .automatic, is32Bit: false, toolkitAdded: true, lastRan: nil) == .d3dMetal)
        #expect(GraphicsLayer.drawing(chosen: .dxvk, is32Bit: false, toolkitAdded: false, lastRan: nil) == .dxvk)
        #expect(GraphicsLayer.drawing(chosen: .automatic, is32Bit: true, toolkitAdded: false, lastRan: .wineOwn) == nil)
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
    @Test func d3dMetalIsNoSetupStepAndAnOldSkipMarkChangesNothing() throws {
        let paths = try makeEngine()
        defer { try? FileManager.default.removeItem(at: paths.home) }
        let setup = Setup(paths: paths, rosetta: paths.home.appending(path: "rosetta"))
        #expect(Setup.Step.allCases == [.rosetta, .steam, .engine, .bridge, .steamPlay])
        #expect(Setup.required == [.rosetta, .steam, .engine, .bridge])
        let before = setup.states().map(\.state)

        // What Tannin 0.3 to 0.5 left behind when the toolkit step was skipped.
        try Data().write(to: paths.tannin.appending(path: "toolkit-skipped"))
        #expect(setup.states().map(\.state) == before)
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

/// A home with made-up engines, runners and Steam settings, enough for the engine store.
private func makeEngines(_ specs: [EngineSpec]) throws -> Paths {
    let fm = FileManager.default
    let home = fm.temporaryDirectory.appending(path: "tannin-engines-\(UUID().uuidString)")
    let paths = Paths(home: home, steamApp: home.appending(path: "Applications/Steam.app"))
    for spec in specs {
        for file in Engine.requiredFiles {
            let url = Engine(paths: paths, spec: spec).wine.appending(path: file)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(spec.wine.utf8).write(to: url)
        }
        let runner = Runner(paths: paths, spec: spec)
        try fm.createDirectory(at: runner.root.appending(path: "lib/wine"), withIntermediateDirectories: true)
        try runner.writeToolsLine()
    }
    try fm.createDirectory(at: paths.steamConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "\"InstallConfigStore\"\n{\n\t\"Software\"\n\t{\n\t\t\"Valve\"\n\t\t{\n\t\t\t\"Steam\"\n\t\t\t{\n\t\t\t}\n\t\t}\n\t}\n}\n"
        .write(to: paths.steamConfig, atomically: true, encoding: .utf8)
    let local = paths.steamData.appending(path: "userdata/1/config/localconfig.vdf")
    try fm.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "\"UserLocalConfigStore\"\n{\n\t\"Software\"\n\t{\n\t\t\"Valve\"\n\t\t{\n\t\t\t\"Steam\"\n\t\t\t{\n\t\t\t\t\"apps\"\n\t\t\t\t{\n\t\t\t\t}\n\t\t\t}\n\t\t}\n\t}\n}\n"
        .write(to: local, atomically: true, encoding: .utf8)
    return paths
}

@Suite struct EngineSpecTests {
    @Test func everyEngineHasItsOwnNamesAndTheNewestKeepsTheOldOnes() {
        #expect(EngineSpec.newest.toolName == "notproton-tannin")
        #expect(EngineSpec.newest.build == "tannin-1")
        #expect(EngineSpec.newest.dxmtVariant == "tannin-dxmt")
        #expect(EngineSpec.newest.dxvkPlugin == "NOTPROTON_TANNIN_DXVK")
        #expect(EngineSpec.wine1117.dxmtVariant == "tannin-dxmt-1117")
        #expect(EngineSpec.wine1117.dxvkPlugin == "NOTPROTON_TANNIN_DXVK_1117")
        for keyPath: KeyPath<EngineSpec, String> in [\.version, \.wine, \.build, \.toolName, \.dxmtVariant, \.plainVariant, \.dxvkPlugin] {
            #expect(Set(EngineSpec.all.map { $0[keyPath: keyPath] }).count == EngineSpec.all.count)
        }
        #expect(EngineSpec.all.allSatisfy { $0.toolName.hasPrefix("notproton") })
    }

    @Test func everyEngineHasAPatchForBothBitWidths() {
        for spec in EngineSpec.all {
            for arch in Runner.patchedArchitectures {
                let pin = NtdllPatch.pins(for: spec).first { $0.arch == arch }
                let recipe = NtdllRecipe.all.first { $0.arch == arch && $0.cleanSHA256 == pin?.cleanSHA256 }
                #expect(recipe != nil, "\(spec.wine) \(arch)")
                #expect(recipe?.patchedSHA256 == pin?.patchedSHA256, "\(spec.wine) \(arch)")
                #expect(recipe?.runs.allSatisfy { $0.bytes != nil } == true, "\(spec.wine) \(arch)")
            }
        }
    }

    @Test func launchOptionsNameTheGamesOwnEnginesFiles() {
        let dxmt = GameSettings(layer: .dxmt, frameCap: 60)
        #expect(dxmt.launchOptions(engine: .wine1117) == "NOTPROTON_RUNNER_VARIANT=tannin-dxmt-1117 DXMT_CONFIG=d3d11.preferredMaxFrameRate=60 %command%")
        let dxvk = GameSettings(layer: .dxvk, backgroundEffects: true)
        let on1117 = dxvk.launchOptions(engine: .wine1117)
        #expect(on1117 == "NOTPROTON_RUNNER_VARIANT=tannin-plain-1117 NOTPROTON_TANNIN_DXVK_1117=1 DXVK_ASYNC=1 %command%")
        // Read back as the same layer whichever engine wrote it, and rewritten cleanly for another engine.
        #expect(GameSettings(parsing: on1117) == dxvk)
        #expect(GameSettings(parsing: on1117).launchOptions(merging: on1117, engine: .newest)
            == "NOTPROTON_RUNNER_VARIANT=tannin-plain NOTPROTON_TANNIN_DXVK=1 DXVK_ASYNC=1 %command%")
    }
}

@Suite struct EngineStoreTests {
    @Test func theFirstListedEngineIsTheDefaultAndCanBeChanged() throws {
        let paths = try makeEngines([.wine1119, .wine1117])
        defer { try? FileManager.default.removeItem(at: paths.home) }
        let store = EngineStore(paths: paths)
        #expect(store.installed() == [.wine1119, .wine1117])
        #expect(store.defaultEngine() == .wine1119)
        try store.makeDefault(.wine1117)
        #expect(store.defaultEngine() == .wine1117)
        #expect(Runner.listedTools(paths: paths) == ["notproton-tannin-1117", "notproton-tannin"])
        // Building a runner again keeps its place in the list.
        try Runner(paths: paths, spec: .wine1119).writeToolsLine()
        #expect(store.defaultEngine() == .wine1117)
    }

    @Test func aGameFollowsTheDefaultUntilItIsPinned() throws {
        let paths = try makeEngines([.wine1119, .wine1117])
        defer { try? FileManager.default.removeItem(at: paths.home) }
        let store = EngineStore(paths: paths)
        let config = SteamConfig(paths: paths, steamIsRunning: { false })
        #expect(store.pin(appID: "10") == nil)
        #expect(store.engine(for: "10") == .wine1119)
        try config.setCompatTool(appID: "10", tool: EngineSpec.wine1117.toolName)
        #expect(store.pin(appID: "10") == .wine1117)
        #expect(store.engine(for: "10") == .wine1117)
        #expect(store.pinnedGames(.wine1117) == ["10"])
        try config.setCompatTool(appID: "10", tool: nil)
        #expect(store.pin(appID: "10") == nil)
    }

    @Test func aPinToAnEngineThatIsGoneFallsBackToTheDefault() throws {
        let paths = try makeEngines([.wine1119])
        defer { try? FileManager.default.removeItem(at: paths.home) }
        try SteamConfig(paths: paths, steamIsRunning: { false }).setCompatTool(appID: "10", tool: EngineSpec.wine1117.toolName)
        let store = EngineStore(paths: paths)
        #expect(store.pin(appID: "10") == .wine1117)
        #expect(store.engine(for: "10") == .wine1119)
    }

    @Test func theDefaultTheNewestAndTheOnlyEngineCannotBeRemoved() throws {
        let paths = try makeEngines([.wine1119, .wine1117])
        defer { try? FileManager.default.removeItem(at: paths.home) }
        let store = EngineStore(paths: paths)
        #expect(throws: EngineStoreError.self) { try store.remove(.wine1119) }
        try store.makeDefault(.wine1117)
        #expect(throws: EngineStoreError.self) { try store.remove(.wine1117) }
        #expect(store.installed().count == 2)
    }
}

@Suite struct D3DMetalTests {
    /// A made-up imported copy; adding a real one needs Apple's signature, which SetupFromScratchTests covers.
    private func importCopy(_ version: String, into paths: Paths) throws -> GPTK.Imported {
        let lib = paths.gptk.appending(path: "D3DMetal-\(version)/lib")
        try FileManager.default.createDirectory(at: lib.appending(path: "external"), withIntermediateDirectories: true)
        try Data().write(to: lib.appending(path: "external/libd3dshared.dylib"))
        return GPTK.Imported(version: version, lib: lib)
    }

    @Test func oneVersionAtATime() throws {
        let paths = try makeEngines([.wine1119])
        defer { try? FileManager.default.removeItem(at: paths.home) }
        let newer = try importCopy("4.0b3", into: paths)
        let older = try importCopy("3.0", into: paths)
        let toolkit = GPTK(paths: paths)
        // The newer name would be picked up again by anything that rebuilds a runner.
        #expect(try toolkit.current().version == newer.version)

        try toolkit.retireOthers(keeping: older, disposal: .delete)
        #expect(toolkit.imported().map(\.version) == ["3.0"])
        #expect(try toolkit.current().version == older.version)
    }

    @Test func removingLeavesNoCopyBehindAndPutsDXMTBack() throws {
        let paths = try makeEngine()
        defer { try? FileManager.default.removeItem(at: paths.home) }
        // A runner as it is with D3DMetal in it: Wine's own files on the 64-bit side, and the mark.
        let runner = Runner(paths: paths).root
        try Shell.check("/bin/mkdir", ["-p", runner.deletingLastPathComponent().path])
        try Shell.check("/bin/cp", ["-R", Engine(paths: paths).wine.path, runner.path])
        _ = try importCopy("4.0b3", into: paths)
        let marker = runner.appending(path: "lib/external/.tannin-d3dmetal")
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "4.0b3".write(to: marker, atomically: true, encoding: .utf8)
        let store = EngineStore(paths: paths, gameIsRunning: { false }, disposal: .delete)
        #expect(store.installed() == [.newest])
        #expect(store.d3dMetal()?.version == "4.0b3")
        #expect(D3DMetalLink(paths: paths).linkedVersion() == "4.0b3")

        try store.removeD3DMetal()
        #expect(store.d3dMetal() == nil)
        #expect(D3DMetalLink(paths: paths).linkedVersion() == nil)
        #expect(GPTK(paths: paths).imported().isEmpty)
        // Without D3DMetal the 64-bit side needs DXMT to be of any use.
        #expect(LayerStore(paths: paths).runnerHasDXMT(runner, arch: "x86_64"))
    }

    @Test func nothingChangesWhileAGameIsRunning() throws {
        let paths = try makeEngines([.wine1119])
        defer { try? FileManager.default.removeItem(at: paths.home) }
        _ = try importCopy("4.0b3", into: paths)
        let store = EngineStore(paths: paths, gameIsRunning: { true }, disposal: .delete)
        #expect(throws: EngineStoreError.self) { try store.removeD3DMetal() }
        #expect(throws: EngineStoreError.self) { try store.addD3DMetal(from: paths.home.appending(path: "none.dmg")) }
        #expect(store.d3dMetal()?.version == "4.0b3")
    }

    @Test func theBugReportListsEnginesAndRenderersInThePagesOrder() {
        #expect(LogReader.enginesLine(installed: [.wine1119, .wine1117], fallback: .wine1119) == "11.19 (default), 11.17")
        #expect(LogReader.enginesLine(installed: [.wine1119], fallback: .wine1119) == "11.19")
        #expect(LogReader.enginesLine(installed: [], fallback: nil) == "none installed")
        #expect(LogReader.renderersLine(d3dMetal: "4.0b3") == "D3DMetal 4.0b3, DXMT 0.80, DXVK 1.10.3")
        #expect(LogReader.renderersLine(d3dMetal: nil) == "D3DMetal not added, DXMT 0.80, DXVK 1.10.3")
    }
}

@Suite struct EnvironmentCopyTests {
    private func makeEnvironment(_ paths: Paths, appID: String, save: String) throws -> URL {
        let prefix = paths.steamData.appending(path: "steamapps/compatdata/\(appID)/pfx")
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        try save.write(to: prefix.appending(path: "save.txt"), atomically: true, encoding: .utf8)
        return prefix.appending(path: "save.txt")
    }

    @Test func keepsTheNewestCopyAndPutsItBack() throws {
        let paths = try makeEngines([.wine1119, .wine1117])
        defer { try? FileManager.default.removeItem(at: paths.home) }
        let copies = EnvironmentCopy(paths: paths)
        #expect(copies.info(appID: "10") == nil)
        #expect(throws: EnvironmentCopyError.self) { try copies.restore(appID: "10") }
        // A game never started has nothing to copy, and that is not an error.
        #expect(try copies.make(appID: "10", from: .wine1119, to: .wine1117) == nil)

        let save = try makeEnvironment(paths, appID: "10", save: "first")
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        try copies.make(appID: "10", from: .wine1119, to: .wine1117, now: when)
        #expect(copies.info(appID: "10") == EnvironmentCopy.Info(made: when, fromWine: "11.19", toWine: "11.17"))
        try "second".write(to: save, atomically: true, encoding: .utf8)
        try copies.restore(appID: "10")
        #expect(try String(contentsOf: save, encoding: .utf8) == "first")
        // The copy is still there after it has been put back, and a later copy replaces it.
        try "third".write(to: save, atomically: true, encoding: .utf8)
        try copies.make(appID: "10", from: .wine1117, to: .wine1119, now: when.addingTimeInterval(60))
        #expect(copies.info(appID: "10")?.fromWine == "11.17")
        try copies.restore(appID: "10")
        #expect(try String(contentsOf: save, encoding: .utf8) == "third")
    }
}

@Suite struct GameMoveTests {
    @Test func movingCopiesTheEnvironmentPinsTheGameAndRenamesItsLayerFiles() throws {
        let paths = try makeEngines([.wine1119, .wine1117])
        defer { try? FileManager.default.removeItem(at: paths.home) }
        let prefix = paths.steamData.appending(path: "steamapps/compatdata/10/pfx")
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        try "before".write(to: prefix.appending(path: "save.txt"), atomically: true, encoding: .utf8)
        let config = SteamConfig(paths: paths, steamIsRunning: { false })
        try config.setLaunchOptions(appID: "10", "NOTPROTON_RUNNER_VARIANT=tannin-dxmt MY_FLAG=1 %command%")
        let store = EngineStore(paths: paths)
        let mover = GameMove(paths: paths, steamIsRunning: { false })

        // Refused while Steam runs, with nothing changed.
        #expect(throws: SteamConfigError.self) { try GameMove(paths: paths, steamIsRunning: { true }).move(appID: "10", to: .wine1117) }
        #expect(store.pin(appID: "10") == nil)
        #expect(EnvironmentCopy(paths: paths).info(appID: "10") == nil)

        try mover.move(appID: "10", to: .wine1117)
        #expect(store.pin(appID: "10") == .wine1117)
        #expect(config.launchOptions(appID: "10") == "NOTPROTON_RUNNER_VARIANT=tannin-dxmt-1117 MY_FLAG=1 %command%")
        #expect(EnvironmentCopy(paths: paths).info(appID: "10")?.fromWine == "11.19")

        // The game saves something on 11.17, then the copy is put back: the save and the Wine version return.
        try "after".write(to: prefix.appending(path: "save.txt"), atomically: true, encoding: .utf8)
        try mover.restore(appID: "10")
        #expect(try String(contentsOf: prefix.appending(path: "save.txt"), encoding: .utf8) == "before")
        #expect(store.pin(appID: "10") == nil)
        #expect(config.launchOptions(appID: "10") == "NOTPROTON_RUNNER_VARIANT=tannin-dxmt MY_FLAG=1 %command%")
    }

    @Test func aGameCannotBeMovedToAnEngineThatIsNotInstalled() throws {
        let paths = try makeEngines([.wine1119])
        defer { try? FileManager.default.removeItem(at: paths.home) }
        #expect(throws: EngineStoreError.self) { try GameMove(paths: paths, steamIsRunning: { false }).move(appID: "10", to: .wine1117) }
    }
}

@Suite struct FixedWindowTests {
    private static let registry = """
        WINE REGISTRY Version 2
        ;; All keys relative to \\\\User\\\\S-1-5-21-0-0-0-1000

        [Software\\\\Wine\\\\Explorer] 1794994802
        #time=1dd7740c9445ede
        "Desktop"="Default"

        [Software\\\\Wine\\\\Explorer\\\\Desktops] 1794994802
        #time=1dd7740c9445f7e
        "Default"="1024x768"

        [Software\\\\Wine\\\\Fonts] 1794994800
        "Codepages"="1252,437"
        """

    @Test func readsTheSizeFromWinesRegistryText() {
        #expect(FixedWindow.size(inRegistry: Self.registry) == FixedWindow.Size(width: 1024, height: 768))
        #expect(FixedWindow.size(inRegistry: Self.registry.replacingOccurrences(of: "1024x768", with: "800x600"))?.description == "800 × 600")
        // No desktop named, a desktop named that has no size, or nonsense for a size: the game runs the ordinary way.
        #expect(FixedWindow.size(inRegistry: Self.registry.replacingOccurrences(of: "\"Desktop\"=\"Default\"", with: "")) == nil)
        #expect(FixedWindow.size(inRegistry: Self.registry.replacingOccurrences(of: "\"Default\"=\"1024x768\"", with: "")) == nil)
        #expect(FixedWindow.size(inRegistry: Self.registry.replacingOccurrences(of: "1024x768", with: "wide")) == nil)
        #expect(FixedWindow.size(inRegistry: "") == nil)
    }

    @Test func offersTheSizesThatFitTheScreen() {
        // A 14-inch MacBook Pro at its usual setting, less the menu bar.
        let macBook = FixedWindow.sizes(fittingWidth: 1512, height: 945)
        #expect(macBook.map(\.description) == ["800 × 600", "1024 × 768", "1152 × 864"])
        #expect(FixedWindow.sizes(fittingWidth: 2560, height: 1400).count == FixedWindow.sizes.count)
        // A size that is already set stays in the list even when it no longer fits.
        let odd = FixedWindow.Size(width: 1600, height: 1200)
        #expect(FixedWindow.sizes(fittingWidth: 1512, height: 945, including: odd).last == odd)
        #expect(FixedWindow.sizes(fittingWidth: 1512, height: 945, including: .usual) == macBook)
    }

    @Test func asksWineForExactlyTheseRegistryChanges() {
        #expect(FixedWindow.commands(for: .usual) == [
            ["reg", "add", #"HKCU\Software\Wine\Explorer"#, "/v", "Desktop", "/d", "Default", "/f"],
            ["reg", "add", #"HKCU\Software\Wine\Explorer\Desktops"#, "/v", "Default", "/d", "1024x768", "/f"],
        ])
        #expect(FixedWindow.commands(for: nil).allSatisfy { $0[1] == "delete" && $0.last == "/f" })
    }

    @Test func setsItOnlyForAGameThatExistsAndIsNotRunning() throws {
        let paths = try makeEngines([.wine1119, .wine1117])
        defer { try? FileManager.default.removeItem(at: paths.home) }
        let calls = Calls()
        func window(running: Bool = false) -> FixedWindow {
            FixedWindow(paths: paths, gameIsRunning: { _ in running }, runWine: { engine, prefix, arguments in
                calls.add("\(engine.wine) \(prefix.lastPathComponent) \(arguments.prefix(2).joined(separator: " "))")
            })
        }
        // Never started: there is nowhere to keep it.
        #expect(!window().hasEnvironment(appID: "10"))
        #expect(throws: FixedWindowError.self) { try window().set(.usual, appID: "10") }

        let prefix = paths.steamData.appending(path: "steamapps/compatdata/10/pfx")
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        try "WINE REGISTRY Version 2\n".write(to: prefix.appending(path: "user.reg"), atomically: true, encoding: .utf8)
        #expect(window().hasEnvironment(appID: "10"))
        #expect(window().size(appID: "10") == nil)
        #expect(throws: FixedWindowError.self) { try window(running: true).set(.usual, appID: "10") }
        #expect(calls.all.isEmpty)

        // Wine is run from the engine the game is on, in the game's own environment.
        try SteamConfig(paths: paths, steamIsRunning: { false }).setCompatTool(appID: "10", tool: EngineSpec.wine1117.toolName)
        try window().set(.usual, appID: "10")
        #expect(calls.all == ["11.17 pfx reg add", "11.17 pfx reg add"])

        // Already as asked: nothing is run.
        try Self.registry.replacingOccurrences(of: "\\\\\\\\", with: "\\\\").write(to: prefix.appending(path: "user.reg"), atomically: true, encoding: .utf8)
        #expect(window().size(appID: "10") == .usual)
        try window().set(.usual, appID: "10")
        #expect(calls.all.count == 2)
        try window().set(nil, appID: "10")
        #expect(calls.all.suffix(2) == ["11.17 pfx reg delete", "11.17 pfx reg delete"])

        // A byte elsewhere in the file that is not UTF-8 does not hide the setting.
        var bytes = Data(Self.registry.replacingOccurrences(of: "\\\\\\\\", with: "\\\\").utf8)
        bytes.append(contentsOf: [0x22, 0xE9, 0x22, 0x3D, 0x22, 0x31, 0x22, 0x0A])
        try bytes.write(to: prefix.appending(path: "user.reg"))
        #expect(window().size(appID: "10") == .usual)
    }

    @Test func knowsAStartThatWasRefusedItsScreenSize() {
        let refused = "012c:err:system:NtUserChangeDisplaySettings Changing L\"\\\\\\\\.\\\\DISPLAY1\" display settings returned -2.\n"
        #expect(GameLogSigns.refusedScreenSize(wineLog: "msync: up and running.\n" + refused))
        #expect(!GameLogSigns.refusedScreenSize(wineLog: "msync: up and running.\ninfo:  Using feature level D3D_FEATURE_LEVEL_11_0\n"))
        #expect(!GameLogSigns.refusedScreenSize(appID: "none", paths: Paths(home: FileManager.default.temporaryDirectory.appending(path: "tannin-none"))))
    }
}

/// Collects what a test's stand-in for Wine was asked to do.
private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ item: String) { lock.withLock { items.append(item) } }
    var all: [String] { lock.withLock { items } }
}
