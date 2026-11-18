import Foundation

public enum GPTKError: Error, CustomStringConvertible {
    case notAToolkit(String)
    case notApple(String)
    case notImported
    case runnerMissing

    public var description: String {
        switch self {
        case let .notAToolkit(path):
            return "\(path) does not contain Apple's evaluation environment (no redist/lib with D3DMetal.framework)."
        case let .notApple(detail):
            return "D3DMetal is not signed by Apple (\(detail)). Nothing was imported. Download the toolkit again from Apple."
        case .notImported: return "No Game Porting Toolkit has been imported. Run: tannin gptk import <disk image>"
        case .runnerMissing: return "The runner has not been built. Run: tannin runner build"
        }
    }
}

/// Apple's Game Porting Toolkit: imported from the user's own download, never bundled and never modified.
public struct GPTK: Sendable {
    public let paths: Paths

    public init(paths: Paths = .live) { self.paths = paths }

    /// Apple's own signing requirement for the framework. An ad-hoc or third-party signature fails it.
    static let requirement = "anchor apple generic and identifier \"com.apple.D3DMetal\""

    public struct Imported: Sendable, Equatable {
        public let version: String
        /// The copied `redist/lib` folder, holding `external/` and `wine/`.
        public let lib: URL
    }

    static func verifyApple(_ framework: URL) throws {
        let result = try Shell.run("/usr/bin/codesign", ["-v", "-R=\(requirement)", framework.path])
        guard result.ok else {
            throw GPTKError.notApple(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func version(of framework: URL) -> String {
        let plist = framework.appending(path: "Versions/A/Resources/Info.plist")
        guard
            let data = try? Data(contentsOf: plist),
            let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let version = info["CFBundleShortVersionString"] as? String
        else { return "unknown" }
        return version
    }

    /// Every imported toolkit, newest name last.
    public func imported() -> [Imported] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: paths.gptk, includingPropertiesForKeys: nil)) ?? []
        return folders
            .filter { $0.lastPathComponent.hasPrefix("D3DMetal-") }
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending }
            .map { Imported(version: String($0.lastPathComponent.dropFirst("D3DMetal-".count)), lib: $0.appending(path: "lib")) }
            .filter { FileManager.default.fileExists(atPath: $0.lib.appending(path: "external/libd3dshared.dylib").path) }
    }

    public func current() throws -> Imported {
        guard let newest = imported().last else { throw GPTKError.notImported }
        return newest
    }

    /// Imports from Apple's disk image (outer or inner) or from an already opened folder.
    @discardableResult
    public func importToolkit(from source: URL) throws -> Imported {
        var mounted: [URL] = []
        defer { for mount in mounted.reversed() { _ = try? Shell.run("/usr/bin/hdiutil", ["detach", mount.path]) } }

        func attach(_ image: URL) throws -> URL {
            let mountPoint = FileManager.default.temporaryDirectory.appending(path: "tannin-gptk-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
            try Shell.check("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-mountpoint", mountPoint.path, image.path])
            mounted.append(mountPoint)
            return mountPoint
        }

        func findLib(in folder: URL) -> URL? {
            for candidate in ["redist/lib", "lib", ""] {
                let lib = candidate.isEmpty ? folder : folder.appending(path: candidate)
                if FileManager.default.fileExists(atPath: lib.appending(path: "external/D3DMetal.framework").path) { return lib }
            }
            return nil
        }

        var root = source
        if source.pathExtension.lowercased() == "dmg" { root = try attach(source) }
        var lib = findLib(in: root)
        if lib == nil {
            // Apple's download is an outer image holding the evaluation environment as an inner image.
            let entries = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            if let inner = entries.first(where: { $0.pathExtension.lowercased() == "dmg" && $0.lastPathComponent.lowercased().contains("evaluation environment") }) {
                lib = findLib(in: try attach(inner))
            }
        }
        guard let lib else { throw GPTKError.notAToolkit(source.path) }

        let framework = lib.appending(path: "external/D3DMetal.framework")
        try Self.verifyApple(framework)
        let version = Self.version(of: framework)

        let fm = FileManager.default
        let destination = paths.gptk.appending(path: "D3DMetal-\(version)")
        let staging = paths.gptk.appending(path: ".import-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        // ditto keeps symlinks, extended attributes and the framework's signature intact.
        try Shell.check("/usr/bin/ditto", [lib.path, staging.appending(path: "lib").path])
        // Check the copy too: this is what will actually be loaded.
        try Self.verifyApple(staging.appending(path: "lib/external/D3DMetal.framework"))

        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: staging, to: destination)
        return Imported(version: version, lib: destination.appending(path: "lib"))
    }
}

/// Puts D3DMetal into the runner, following the layout in Apple's Read Me and the engine's own note:
/// the framework and libd3dshared as copies in `lib/external`, the Unix halves as symlinks to it,
/// and Apple's Windows DLLs in place of Wine's own. Wine's originals are kept so this can be undone.
public struct D3DMetalLink: Sendable {
    public let paths: Paths
    public let spec: EngineSpec

    public init(paths: Paths = .live, spec: EngineSpec = .newest) {
        self.paths = paths
        self.spec = spec
    }

    var runner: URL { Runner(paths: paths, spec: spec).root }
    var stock: URL { runner.appending(path: "lib/tannin-stock") }
    var marker: URL { runner.appending(path: "lib/external/.tannin-d3dmetal") }

    public func linkedVersion() -> String? {
        try? String(contentsOf: marker, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func link(_ toolkit: GPTK.Imported) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: runner.appending(path: "lib/wine").path) else { throw GPTKError.runnerMissing }
        try GPTK.verifyApple(toolkit.lib.appending(path: "external/D3DMetal.framework"))
        if linkedVersion() != nil { try takeOut() }

        // The runner's 64-bit side holds DXMT while no D3DMetal is linked. The two cannot share a game, so
        // Wine's own files go back first, and those are what is kept aside below.
        let layers = LayerStore(paths: paths, spec: spec)
        let hasEngine = Engine(paths: paths, spec: spec).isInstalled
        if hasEngine { try layers.putWineOwn(into: runner, arch: "x86_64") }

        // Keep Wine's own files that are about to be replaced.
        for arch in ["x86_64-windows", "x86_64-unix"] {
            let incoming = (try? fm.contentsOfDirectory(atPath: toolkit.lib.appending(path: "wine/\(arch)").path)) ?? []
            for name in incoming {
                let existing = runner.appending(path: "lib/wine/\(arch)/\(name)")
                guard fm.fileExists(atPath: existing.path) || (try? fm.destinationOfSymbolicLink(atPath: existing.path)) != nil else { continue }
                let kept = stock.appending(path: "\(arch)/\(name)")
                try fm.createDirectory(at: kept.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !fm.fileExists(atPath: kept.path) { try fm.moveItem(at: existing, to: kept) } else { try fm.removeItem(at: existing) }
            }
        }

        // Apple's procedure: copy redist/lib over the Wine lib folder.
        try Shell.check("/usr/bin/ditto", [toolkit.lib.path, runner.appending(path: "lib").path])

        // MetalFX bridge under the names games look for (Apple's Read Me, "Prepare your environment").
        for (folder, ext) in [("x86_64-unix", "so"), ("x86_64-windows", "dll")] {
            let from = runner.appending(path: "lib/wine/\(folder)/nvngx-on-metalfx.\(ext)")
            let to = runner.appending(path: "lib/wine/\(folder)/nvngx.\(ext)")
            guard fm.fileExists(atPath: from.path) || (try? fm.destinationOfSymbolicLink(atPath: from.path)) != nil else { continue }
            try? fm.removeItem(at: to)
            if let target = try? fm.destinationOfSymbolicLink(atPath: from.path) {
                try fm.createSymbolicLink(atPath: to.path, withDestinationPath: target)
            } else {
                try fm.copyItem(at: from, to: to)
            }
        }

        // Where the add-on's launch script looks, so it tells Wine where libd3dshared is.
        let lib64 = runner.appending(path: "lib64")
        try fm.createDirectory(at: lib64, withIntermediateDirectories: true)
        let appleGPTK = lib64.appending(path: "apple_gptk")
        try? fm.removeItem(at: appleGPTK)
        try fm.createSymbolicLink(atPath: appleGPTK.path, withDestinationPath: "../lib")

        try GPTK.verifyApple(runner.appending(path: "lib/external/D3DMetal.framework"))
        try toolkit.version.write(to: marker, atomically: true, encoding: .utf8)
        // Fresh layer files, so the add-on rebuilds its per-layer copies of the runner from the changed one.
        if hasEngine { try layers.prepare() }
    }

    /// Takes D3DMetal out again. Games then run on DXMT.
    public func unlink() throws {
        try takeOut()
        let layers = LayerStore(paths: paths, spec: spec)
        guard Engine(paths: paths, spec: spec).isInstalled, FileManager.default.fileExists(atPath: runner.appending(path: "lib/wine").path) else { return }
        try layers.putDXMT(into: runner, arch: "x86_64")
        try layers.prepare()
    }

    /// Removes D3DMetal's files and puts Wine's own back.
    private func takeOut() throws {
        let fm = FileManager.default
        for name in ["D3DMetal.framework", "libd3dshared.dylib"] {
            try? fm.removeItem(at: runner.appending(path: "lib/external/\(name)"))
        }
        try? fm.removeItem(at: runner.appending(path: "lib64/apple_gptk"))
        for arch in ["x86_64-windows", "x86_64-unix"] {
            let folder = runner.appending(path: "lib/wine/\(arch)")
            // Remove what the toolkit added: anything pointing at libd3dshared, and its Windows DLLs.
            for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] {
                let file = folder.appending(path: name)
                if let target = try? fm.destinationOfSymbolicLink(atPath: file.path), target.hasSuffix("libd3dshared.dylib") {
                    try? fm.removeItem(at: file)
                }
            }
            for name in ["nvapi64.dll", "nvngx.dll", "nvngx-on-metalfx.dll"] where arch == "x86_64-windows" {
                try? fm.removeItem(at: folder.appending(path: name))
            }
            let kept = stock.appending(path: arch)
            for name in (try? fm.contentsOfDirectory(atPath: kept.path)) ?? [] {
                let destination = folder.appending(path: name)
                try? fm.removeItem(at: destination)
                try fm.moveItem(at: kept.appending(path: name), to: destination)
            }
        }
        try? fm.removeItem(at: stock)
        try? fm.removeItem(at: marker)
    }
}
