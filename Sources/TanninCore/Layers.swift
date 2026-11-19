import Foundation

/// A renderer: what turns a game's Direct3D calls into Metal. The app calls it a renderer; the code and the
/// launch options keep the older name, since the launch options are in people's Steam settings.
public enum GraphicsLayer: String, Sendable, CaseIterable, Identifiable {
    /// Tannin's own pick: D3DMetal for a 64-bit game when D3DMetal has been added, DXMT otherwise.
    case automatic
    /// Apple's renderer, from the user's own Game Porting Toolkit. Direct3D 11 and 12, 64-bit games only.
    case d3dMetal
    /// Direct3D 10 and 11 straight to Metal. Comes with the Wine engine.
    case dxmt
    /// Direct3D 11 through Vulkan (MoltenVK). Comes with the Wine engine. 64-bit games only.
    case dxvk

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .d3dMetal: "D3DMetal"
        case .dxmt: "DXMT"
        case .dxvk: "DXVK"
        }
    }

    /// One line on what the layer covers, for the place it is chosen.
    public var summary: String {
        switch self {
        case .automatic: "Tannin picks for each game"
        case .d3dMetal: "Direct3D 11 and 12"
        case .dxmt: "Direct3D 10 and 11"
        case .dxvk: "Direct3D 11, through Vulkan"
        }
    }

    /// The layers a game can be given by name. D3DMetal and DXVK have no 32-bit half on this engine.
    public func isOffered(is32Bit: Bool, toolkitAdded: Bool) -> Bool {
        switch self {
        case .automatic, .dxmt: true
        case .d3dMetal: !is32Bit && toolkitAdded
        case .dxvk: !is32Bit
        }
    }

    /// What Automatic comes to for a game. Nil while the game's bit width is not known (it is not installed).
    public static func automaticChoice(is32Bit: Bool?, toolkitAdded: Bool) -> GraphicsLayer? {
        guard let is32Bit else { return toolkitAdded ? nil : .dxmt }
        return (!is32Bit && toolkitAdded) ? .d3dMetal : .dxmt
    }

    /// The renderer whose settings a game's page shows: the one chosen by name, or what Automatic comes to.
    /// Nil when that is not known yet, and for a Direct3D 9 game, which Wine draws itself.
    public static func inEffect(chosen: GraphicsLayer, is32Bit: Bool?, toolkitAdded: Bool, lastRan: LayerUsage?) -> GraphicsLayer? {
        guard chosen == .automatic else { return chosen }
        if lastRan == .wineOwn { return nil }
        return automaticChoice(is32Bit: is32Bit, toolkitAdded: toolkitAdded)
    }

    /// The renderer that really draws a game. It differs from `inEffect` in one case: D3DMetal chosen by name
    /// while it is not on the Mac, where the runner has DXMT in D3DMetal's place.
    public static func drawing(chosen: GraphicsLayer, is32Bit: Bool?, toolkitAdded: Bool, lastRan: LayerUsage?) -> GraphicsLayer? {
        let wanted = inEffect(chosen: chosen, is32Bit: is32Bit, toolkitAdded: toolkitAdded, lastRan: lastRan)
        return wanted == .d3dMetal && !toolkitAdded ? .dxmt : wanted
    }
}

public enum LayerError: Error, CustomStringConvertible {
    case engineMissing
    case missingFile(String)
    case unexpectedHeader(String)

    public var description: String {
        switch self {
        case .engineMissing: return "Wine isn’t installed, so there are no renderers to prepare."
        case let .missingFile(path): return "Wine is missing \(path)."
        case let .unexpectedHeader(path): return "\(path) isn’t the file this Wine version ships, so Tannin left it unchanged."
        }
    }
}

/// Marks a Windows DLL as one Wine may load from its own folders.
///
/// Wine only loads a file from `lib/wine` when the 16 bytes at offset 0x40 read "Wine builtin DLL". The engine
/// ships DXMT's files with that text replaced by the usual DOS stub bytes, so they load only from a game's
/// Windows folders. Writing the text back makes them usable straight from the runner. Found 2026-11-18.
enum BuiltinMark {
    static let offset = 0x40
    static let text = Data("Wine builtin DLL".utf8)
    /// What stands there in the engine's copies: the start of the DOS stub program.
    static let dosStub = Data([0x0e, 0x1f, 0xba, 0x0e, 0x00, 0xb4, 0x09, 0xcd, 0x21, 0xb8, 0x01, 0x4c, 0xcd, 0x21, 0x90, 0x90])

    static func isMarked(_ data: Data) -> Bool {
        data.count >= offset + text.count && data.subdata(in: offset..<(offset + text.count)) == text
    }

    static func isMarked(_ file: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: UInt64(offset))) != nil, let bytes = try? handle.read(upToCount: text.count) else { return false }
        return bytes == text
    }

    /// The same file with the mark written in. Refuses anything that is not a DLL with the bytes it expects there.
    static func marked(_ data: Data, name: String) throws -> Data {
        guard data.count >= offset + text.count, data.prefix(2) == Data("MZ".utf8) else { throw LayerError.unexpectedHeader(name) }
        let range = offset..<(offset + text.count)
        let present = data.subdata(in: range)
        if present == text { return data }
        guard present == dosStub else { throw LayerError.unexpectedHeader(name) }
        var result = data
        result.replaceSubrange(range, with: text)
        return result
    }
}

/// The files that let a game be given a graphics layer other than the runner's own.
///
/// The Steam add-on's launch script does the per-game part itself: a launch option names a "variant", the script
/// lays that variant's files over a copy of the runner and starts the game from the copy; another names a
/// "plugin", which puts files into the game's Windows folder and sets DLL overrides. Tannin only has to keep the
/// files and the two descriptors in place. Nothing is copied into a game's Windows environment by Tannin, and
/// Tannin does not need to be running when a game starts.
public struct LayerStore: Sendable {
    public let paths: Paths
    public let spec: EngineSpec

    public init(paths: Paths = .live, spec: EngineSpec = .newest) {
        self.paths = paths
        self.spec = spec
    }

    /// Names the launch options use for the newest engine. Another engine's carry its own ending.
    public static let dxmtVariant = EngineSpec.newest.dxmtVariant
    public static let plainVariant = EngineSpec.newest.plainVariant
    public static let dxvkPlugin = EngineSpec.newest.dxvkPlugin

    public static let dxmtVersion = "0.80"
    public static let dxvkVersion = "1.10.3"

    /// DXMT's Direct3D files, which the engine keeps outside Wine's folders.
    static let dxmtFiles = ["d3d10core.dll", "d3d11.dll", "dxgi.dll"]
    /// Every Direct3D file that D3DMetal or DXMT takes the place of in the runner's 64-bit side.
    static let wineFiles = ["d3d10.dll", "d3d10core.dll", "d3d11.dll", "d3d12.dll", "d3d12core.dll", "dxgi.dll"]
    /// DXVK's files. It has no usable Direct3D 9 or 32-bit half on this engine.
    static let dxvkFiles = ["d3d10core.dll", "d3d11.dll"]

    public var root: URL { paths.layers.appending(path: "winecx-\(spec.version)") }
    var dxmtTree: URL { root.appending(path: "dxmt") }
    var plainTree: URL { root.appending(path: "plain") }
    var dxvkStage: URL { root.appending(path: "dxvk") }
    var variantsFile: URL { paths.notproton.appending(path: "variants/tannin\(spec.layerSuffix).conf") }
    var pluginsFile: URL { paths.notproton.appending(path: "plugins/tannin\(spec.layerSuffix).conf") }

    private var engine: Engine { Engine(paths: paths, spec: spec) }
    private func engineDXMT(_ arch: String) -> URL { engine.root.appending(path: "DXMT/\(arch == "i386" ? "x32" : "x64")") }
    private func engineWine(_ arch: String) -> URL { engine.wine.appending(path: "lib/wine/\(arch)-windows") }

    /// DXMT's files for one bit width, marked so Wine loads them from the runner.
    func dxmtBuiltins(arch: String) throws -> [(name: String, data: Data)] {
        try Self.dxmtFiles.map { name in
            let file = engineDXMT(arch).appending(path: name)
            guard let data = try? Data(contentsOf: file) else { throw LayerError.missingFile("DXMT/\(file.deletingLastPathComponent().lastPathComponent)/\(name)") }
            return (name, try BuiltinMark.marked(data, name: name))
        }
    }

    // MARK: The runner's own Direct3D files

    /// Puts DXMT into a runner for one bit width, in place of Wine's own Direct3D 10 and 11.
    ///
    /// Wine's own Direct3D 11 on this engine only reaches feature level 9_3 and its Direct3D 10 fails, so a
    /// runner without D3DMetal needs DXMT to be of any use, and the 32-bit side (which D3DMetal does not have)
    /// always does.
    func putDXMT(into runner: URL, arch: String) throws {
        let folder = runner.appending(path: "lib/wine/\(arch)-windows")
        for file in try dxmtBuiltins(arch: arch) { try file.data.write(to: folder.appending(path: file.name)) }
    }

    /// Puts Wine's own Direct3D 10 and 11 files back for one bit width.
    func putWineOwn(into runner: URL, arch: String) throws {
        let folder = runner.appending(path: "lib/wine/\(arch)-windows")
        for name in Self.dxmtFiles { try read(engineWine(arch).appending(path: name)).write(to: folder.appending(path: name)) }
    }

    /// Whether a runner's Direct3D 11 for one bit width is DXMT's.
    public func runnerHasDXMT(_ runner: URL, arch: String) -> Bool {
        guard let marked = try? dxmtBuiltins(arch: arch).first(where: { $0.name == "d3d11.dll" })?.data else { return false }
        return (try? Data(contentsOf: runner.appending(path: "lib/wine/\(arch)-windows/d3d11.dll"))) == marked
    }

    /// Brings a runner that an earlier Tannin built up to date: DXMT into its 32-bit side, into its 64-bit side
    /// when no D3DMetal is linked, and the files for choosing a layer per game. Nothing is downloaded.
    public func addToRunner() throws {
        let runner = Runner(paths: paths, spec: spec).root
        try putDXMT(into: runner, arch: "i386")
        if D3DMetalLink(paths: paths, spec: spec).linkedVersion() == nil { try putDXMT(into: runner, arch: "x86_64") }
        try prepare()
    }

    /// True when the trees and both descriptors are in place.
    public var isPrepared: Bool {
        let fm = FileManager.default
        let files = Self.dxmtFiles.flatMap { [dxmtTree.appending(path: "x86_64-windows/\($0)"), dxmtTree.appending(path: "i386-windows/\($0)")] }
            + Self.wineFiles.map { plainTree.appending(path: "x86_64-windows/\($0)") }
            + Self.dxvkFiles.map { dxvkStage.appending(path: $0) }
            + [variantsFile, pluginsFile]
        return files.allSatisfy { fm.fileExists(atPath: $0.path) }
    }

    /// Builds the layer files from the installed engine and writes the descriptors. Safe to run again.
    ///
    /// Every file is written afresh each time on purpose. The launch script decides whether its per-game copy of
    /// the runner is still good from the names, sizes and dates of these files, and it does not look at whether
    /// D3DMetal is in the runner. Fresh dates after the runner changes make it build its copies again.
    public func prepare() throws {
        let fm = FileManager.default
        guard engine.isInstalled else { throw LayerError.engineMissing }

        // Gather everything first: if a file is missing or unexpected nothing is changed.
        var trees: [(folder: URL, files: [(name: String, data: Data)])] = []
        for arch in ["x86_64", "i386"] {
            var files = try dxmtBuiltins(arch: arch)
            if arch == "x86_64" {
                // 64-bit Direct3D 10 goes through Wine's own d3d10.dll, which D3DMetal replaces in the runner.
                files.append(("d3d10.dll", try read(engineWine(arch).appending(path: "d3d10.dll"))))
            }
            trees.append((dxmtTree.appending(path: "\(arch)-windows"), files))
        }
        trees.append((plainTree.appending(path: "x86_64-windows"),
                      try Self.wineFiles.map { ($0, try read(engineWine("x86_64").appending(path: $0))) }))
        trees.append((dxvkStage, try Self.dxvkFiles.map { ($0, try read(engine.root.appending(path: "DXVK/x64/\($0)"))) }))

        let staging = paths.layers.appending(path: ".prepare-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }
        for tree in trees {
            let relative = String(tree.folder.path.dropFirst(root.path.count + 1))
            let folder = staging.appending(path: relative)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            for file in tree.files { try file.data.write(to: folder.appending(path: file.name)) }
        }
        if fm.fileExists(atPath: root.path) { try fm.removeItem(at: root) }
        try fm.moveItem(at: staging, to: root)

        try write(variantsText, to: variantsFile)
        try write(pluginsText, to: pluginsFile)
    }

    /// Takes the layer files and descriptors away again.
    public func remove() throws {
        let fm = FileManager.default
        for url in [variantsFile, pluginsFile, root] where fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
    }

    /// Descriptors in the launch script's own format. A variant that replaces Wine's files has to name its build.
    ///
    /// DXMT has no Direct3D 12, and D3DMetal's Direct3D 12 beside DXMT's dxgi crashes a game that tries it first
    /// (LEGO Builder's Journey did, 2026-11-18). With the two files gone from the DXMT copy the attempt fails
    /// cleanly and the game goes on to Direct3D 11.
    var variantsText: String {
        """
        [\(spec.dxmtVariant)]
        label = DXMT (Tannin, Wine \(spec.wine))
        src = \(dxmtTree.path)
        dst = lib/wine
        remove = x86_64-windows/d3d12.dll
        remove = x86_64-windows/d3d12core.dll
        build = \(spec.build)

        [\(spec.plainVariant)]
        label = Wine Direct3D for DXVK (Tannin, Wine \(spec.wine))
        src = \(plainTree.path)
        dst = lib/wine
        build = \(spec.build)

        """
    }

    var pluginsText: String {
        """
        [\(spec.dxvkPlugin)]
        label = DXVK (Tannin, Wine \(spec.wine))
        stage = \(dxvkStage.path)
        overrides = d3d11,d3d10core=n,b
        tools = \(spec.toolName)

        """
    }

    private func read(_ file: URL) throws -> Data {
        guard let data = try? Data(contentsOf: file) else {
            throw LayerError.missingFile(String(file.path.dropFirst(engine.root.path.count + 1)))
        }
        return data
    }

    private func write(_ text: String, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }
}
