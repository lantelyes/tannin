import Foundation

/// The exact bytes involved in patching one engine's ntdll: nothing is applied or accepted unless every hash matches.
public struct NtdllPin: Sendable, Equatable {
    public let arch: String
    public let cleanSHA256: String
    public let detourFile: String
    public let detourSHA256: String
    public let patchedSHA256: String
}

public enum NtdllPatchError: Error, CustomStringConvertible {
    case toolsNotFound
    case unknownEngine(arch: String, sha256: String)
    case detourMismatch(String)
    case resultMismatch(arch: String, expected: String, actual: String)

    public var description: String {
        switch self {
        case .toolsNotFound:
            return "Could not find Tools/ntdll-patch and .venv. Run tannin from the repository, or set TANNIN_REPO."
        case let .unknownEngine(arch, sha256):
            return "The engine's \(arch) ntdll (\(sha256)) is not a build Tannin has a patch for."
        case let .detourMismatch(file): return "\(file) does not match its pinned SHA-256."
        case let .resultMismatch(arch, expected, actual):
            return "The patched \(arch) ntdll is \(actual), expected \(expected). Nothing was installed."
        }
    }
}

/// Makes the copy of ntdll that hands a game's Steam client calls to the Steam bridge.
/// The detours were derived on 2026-11-17 with NotProton's tools (see Tools/ntdll-patch/UPSTREAM.md)
/// and Homebrew mingw-w64 (GCC 16.2.0).
public struct NtdllPatch: Sendable {
    public let paths: Paths
    public let repository: URL

    public static let pins: [NtdllPin] = [
        NtdllPin(arch: "x86_64",
                 cleanSHA256: "53692da95fb6fac94f320ba11378c07dad37ea9dc3a99237a36882c885ae1ed8",
                 detourFile: "detour2-winecx-4.8.3.bin",
                 detourSHA256: "6a897274f0eba3768cc91fb36a89b65ffa58058ff59c0f0150dff9c1dc409bf6",
                 patchedSHA256: "77ab70fe288d96d3f505912b9275ad798a649b5df9321193fafdb5da17daefaa"),
        NtdllPin(arch: "i386",
                 cleanSHA256: "404264bcb910ca81fd4832e14c2bb8a8a808742fad562ff18df7476575e26473",
                 detourFile: "detour32-winecx-4.8.3.bin",
                 detourSHA256: "2fe96f4b7d6a3f6e25bae62337d5a2431d803fb945488b12e6c61af98f44ba57",
                 patchedSHA256: "712c793eee2671fa63634d027dfe76017ab8ef3290aa14bebf67477b4cc76475"),
    ]

    public init(paths: Paths = .live, repository: URL) {
        self.paths = paths
        self.repository = repository
    }

    /// Finds the repository holding the patch tools: TANNIN_REPO, then upward from the working folder and the executable.
    public static func locateRepository() throws -> URL {
        let fm = FileManager.default
        var starts: [URL] = []
        if let env = ProcessInfo.processInfo.environment["TANNIN_REPO"] { starts.append(URL(fileURLWithPath: env)) }
        starts.append(URL(fileURLWithPath: fm.currentDirectoryPath))
        if let exe = Bundle.main.executableURL { starts.append(exe.deletingLastPathComponent()) }
        for start in starts {
            var dir = start.standardizedFileURL
            for _ in 0..<8 {
                if fm.fileExists(atPath: dir.appending(path: "Tools/ntdll-patch/apply.py").path) { return dir }
                dir = dir.deletingLastPathComponent()
            }
        }
        throw NtdllPatchError.toolsNotFound
    }

    var tools: URL { repository.appending(path: "Tools/ntdll-patch") }
    var python: URL { repository.appending(path: ".venv/bin/python") }

    public func output(arch: String) -> URL {
        paths.engines.appending(path: "patched-\(Pins.engineVersion)/\(arch)-windows/ntdll.dll")
    }

    /// Returns a verified patched ntdll for this architecture, building it if needed.
    public func patched(arch: String) throws -> URL {
        let fm = FileManager.default
        let engine = Engine(paths: paths)
        let clean = engine.wine.appending(path: "lib/wine/\(arch)-windows/ntdll.dll")
        let cleanHash = try Hashing.sha256(of: clean)
        guard let pin = Self.pins.first(where: { $0.arch == arch && $0.cleanSHA256 == cleanHash }) else {
            throw NtdllPatchError.unknownEngine(arch: arch, sha256: cleanHash)
        }

        let out = output(arch: arch)
        if fm.fileExists(atPath: out.path), try Hashing.sha256(of: out) == pin.patchedSHA256 { return out }

        let detour = tools.appending(path: "prebuilt/\(pin.detourFile)")
        guard fm.fileExists(atPath: detour.path), fm.fileExists(atPath: python.path) else {
            throw NtdllPatchError.toolsNotFound
        }
        guard try Hashing.sha256(of: detour) == pin.detourSHA256 else {
            throw NtdllPatchError.detourMismatch(pin.detourFile)
        }

        try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = out.appendingPathExtension("tmp")
        try? fm.removeItem(at: temporary)
        // -I: isolated mode, so nothing in the environment or the working folder can change what Python loads.
        try Shell.check(python.path, ["-I", tools.appending(path: "apply.py").path, clean.path, temporary.path, detour.path])

        let actual = try Hashing.sha256(of: temporary)
        guard actual == pin.patchedSHA256 else {
            try? fm.removeItem(at: temporary)
            throw NtdllPatchError.resultMismatch(arch: arch, expected: pin.patchedSHA256, actual: actual)
        }
        try? fm.removeItem(at: out)
        try fm.moveItem(at: temporary, to: out)
        return out
    }
}
