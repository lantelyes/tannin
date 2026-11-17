import Foundation

public enum RunnerError: Error, CustomStringConvertible {
    case engineMissing
    case kitIncomplete([String])

    public var description: String {
        switch self {
        case .engineMissing: return "The Wine engine is not installed. Run: tannin engine install"
        case let .kitIncomplete(missing):
            return "The Steam Play kit is incomplete (\(missing.joined(separator: ", "))). Run: tannin kit install"
        }
    }
}

/// The runner is the copy of the engine the Steam add-on launches games with.
/// The add-on's launch script is fixed, so the runner is laid out exactly where and how that script looks for it.
public struct Runner: Sendable {
    public let paths: Paths

    /// Identity the add-on knows this runner by. The tool name must start with "notproton".
    public static let build = "tannin-1"
    public static let toolName = "notproton-tannin"
    public static let flavor = "rosetta"
    public static let display = "Tannin (Wine \(Pins.engineWine))"

    public init(paths: Paths = .live) { self.paths = paths }

    public var root: URL { paths.notproton.appending(path: "runners/crossover-\(Self.build)/CrossOver") }
    public var toolsFile: URL { paths.notproton.appending(path: "tools") }
    public var defaultsFile: URL { paths.notproton.appending(path: "defaults-override-\(Self.build)-\(Self.flavor)") }
    var stagedNtdll: URL { paths.notproton.appending(path: "bridge/wine/\(Self.build)") }

    /// Which ntdll files get the Steam bridge detour.
    ///
    /// Only the 64-bit one. The 32-bit detour crashes 32-bit programs on this engine: it calls ntdll functions at
    /// fixed addresses for image base 0x7bc00000, and this engine loads 32-bit ntdll elsewhere (the crash was 0xb2
    /// into the detour with ntdll at 0x7bf10000). That broke Wine's own Mono setup step, which is a 32-bit helper,
    /// and made Wine show its "Wine Mono Installer" download dialog. Found 2026-11-17; see FINDINGS.md.
    /// Cost: 32-bit games start, but do not get the Steam bridge until this is solved.
    public static let patchedArchitectures = ["x86_64"]

    public static var toolsLine: String { "\(toolName)\t\(build)\t\(flavor)\t\(display)" }

    /// Settings every game starts with unless its own launch options say otherwise.
    public static let defaults = ["WINEMSYNC=1", "ROSETTA_ADVERTISE_AVX=1"]

    /// Builds the runner from the installed engine, the patched ntdll and the staged bridge.
    public func build(patch: NtdllPatch) throws {
        let fm = FileManager.default
        let engine = Engine(paths: paths)
        guard engine.isInstalled else { throw RunnerError.engineMissing }
        let missing = NotProtonKit(paths: paths).missingStagedFiles()
        guard missing.isEmpty else { throw RunnerError.kitIncomplete(missing) }

        // Patched ntdll first: if this fails nothing has been changed yet.
        var patched: [String: URL] = [:]
        for arch in Self.patchedArchitectures { patched[arch] = try patch.patched(arch: arch) }

        // A fresh APFS clone of the engine: instant, and it shares disk space with the original.
        try fm.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: root.path) { try fm.removeItem(at: root) }
        try Shell.check("/bin/cp", ["-c", "-R", engine.wine.path, root.path])

        func replace(_ source: URL, _ destination: URL) throws {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.copyItem(at: source, to: destination)
        }

        let bridge = paths.notproton.appending(path: "bridge")
        // Start from nothing staged, so an architecture that is no longer patched leaves no stale copy behind.
        try? fm.removeItem(at: stagedNtdll)
        for (arch, file) in patched {
            try replace(file, root.appending(path: "lib/wine/\(arch)-windows/ntdll.dll"))
            // The launch script compares the runner's ntdll with this staged copy.
            try replace(file, stagedNtdll.appending(path: "\(arch)-windows/ntdll.dll"))
        }
        for arch in ["x86_64", "i386"] {
            try replace(bridge.appending(path: "\(arch)-windows/lsteamclient.dll"),
                        root.appending(path: "lib/wine/\(arch)-windows/lsteamclient.dll"))
        }
        try replace(bridge.appending(path: "x86_64-unix/lsteamclient.so"),
                    root.appending(path: "lib/wine/x86_64-unix/lsteamclient.so"))

        try writeToolsLine()
        try (Self.defaults.joined(separator: "\n") + "\n").write(to: defaultsFile, atomically: true, encoding: .utf8)
    }

    /// Lists this runner in the file the add-on reads at Steam start, keeping any other lines.
    func writeToolsLine() throws {
        var lines: [String] = []
        if let existing = try? String(contentsOf: toolsFile, encoding: .utf8) {
            lines = existing.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("\(Self.toolName)\t") }
        }
        lines.insert(Self.toolsLine, at: 0)
        try (lines.joined(separator: "\n") + "\n").write(to: toolsFile, atomically: true, encoding: .utf8)
    }

    /// Checks everything the launch script will look for. Changes nothing.
    public func verify() -> [Check] {
        let fm = FileManager.default
        var checks: [Check] = []
        func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }
        func same(_ a: URL, _ b: URL) -> Bool { fm.contentsEqual(atPath: a.path, andPath: b.path) }

        let required = [
            "bin/wineserver", "lib/wine/x86_64-unix/wine", "lib/wine/x86_64-unix/ntdll.so",
            "lib/wine/x86_64-unix/lsteamclient.so", "lib/wine/x86_64-windows/ntdll.dll",
            "lib/wine/i386-windows/ntdll.dll", "lib/wine/x86_64-windows/lsteamclient.dll",
            "lib/wine/i386-windows/lsteamclient.dll", "share/wine/wine.inf",
        ]
        let missing = required.filter { !exists(root.appending(path: $0)) }
        checks.append(missing.isEmpty
            ? Check("Runner files", .ok, "All \(required.count) present in \(root.path)")
            : Check("Runner files", .broken, "Missing: \(missing.joined(separator: ", "))"))

        for pin in NtdllPatch.pins {
            let live = root.appending(path: "lib/wine/\(pin.arch)-windows/ntdll.dll")
            let staged = stagedNtdll.appending(path: "\(pin.arch)-windows/ntdll.dll")
            let hash = try? Hashing.sha256(of: live)
            if Self.patchedArchitectures.contains(pin.arch) {
                if hash == pin.patchedSHA256, same(live, staged) {
                    checks.append(Check("ntdll \(pin.arch)", .ok, "Patched copy in place and matches the staged copy."))
                } else {
                    checks.append(Check("ntdll \(pin.arch)", .broken, "Not the patched copy (\(hash ?? "missing"))."))
                }
            } else if hash == pin.cleanSHA256, !exists(staged) {
                checks.append(Check("ntdll \(pin.arch)", .ok, "Left as the engine ships it (not patched on this engine)."))
            } else {
                checks.append(Check("ntdll \(pin.arch)", .broken, "Should be the engine's own file (\(hash ?? "missing"))."))
            }
        }

        let bridge = paths.notproton.appending(path: "bridge")
        let bridgePairs = [
            ("x86_64-windows/lsteamclient.dll", "lib/wine/x86_64-windows/lsteamclient.dll"),
            ("i386-windows/lsteamclient.dll", "lib/wine/i386-windows/lsteamclient.dll"),
            ("x86_64-unix/lsteamclient.so", "lib/wine/x86_64-unix/lsteamclient.so"),
        ]
        let wrong = bridgePairs.filter { !same(bridge.appending(path: $0.0), root.appending(path: $0.1)) }.map(\.1)
        checks.append(wrong.isEmpty
            ? Check("Steam bridge", .ok, "The runner uses the bridge from the kit.")
            : Check("Steam bridge", .broken, "Not the kit's bridge: \(wrong.joined(separator: ", "))"))

        let kitMissing = NotProtonKit(paths: paths).missingStagedFiles()
        checks.append(kitMissing.isEmpty
            ? Check("Kit", .ok, "Signatures, bridge, Valve files and helpers are staged.")
            : Check("Kit", .broken, "Missing: \(kitMissing.joined(separator: ", "))"))

        let tools = (try? String(contentsOf: toolsFile, encoding: .utf8)) ?? ""
        checks.append(tools.split(separator: "\n").first.map(String.init) == Self.toolsLine
            ? Check("Tool listing", .ok, Self.toolsLine.replacingOccurrences(of: "\t", with: " | "))
            : Check("Tool listing", .broken, "\(toolsFile.path) does not list \(Self.toolName) first."))

        let gptk = root.appending(path: "lib64/apple_gptk/external/libd3dshared.dylib")
        checks.append(exists(gptk)
            ? Check("D3DMetal", .ok, "Linked into the runner.")
            : Check("D3DMetal", .attention, "Not linked yet. Import the Game Porting Toolkit: tannin gptk import <dmg>"))
        return checks
    }
}
