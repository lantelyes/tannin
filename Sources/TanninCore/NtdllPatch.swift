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
    case unknownEngine(arch: String, sha256: String)
    case resultMismatch(arch: String, expected: String, actual: String)

    public var description: String {
        switch self {
        case let .unknownEngine(arch, sha256):
            return "The engine's \(arch) ntdll (\(sha256)) is not a build Tannin has a patch for."
        case let .resultMismatch(arch, expected, actual):
            return "The patched \(arch) ntdll is \(actual), expected \(expected). Nothing was installed."
        }
    }
}

/// Makes the copy of ntdll that hands a game's Steam client calls to the Steam bridge.
/// The detours were derived on 2026-11-17 with NotProton's tools (see Tools/ntdll-patch/UPSTREAM.md)
/// and Homebrew mingw-w64 (GCC 16.2.0); the 32-bit one again on 2026-11-18 from the corrected `shim32.S`. At run time the patch is applied from `NtdllRecipe`, in Swift.
public struct NtdllPatch: Sendable {
    public let paths: Paths
    public let spec: EngineSpec

    /// The pins of the newest engine.
    public static var pins: [NtdllPin] { pins(for: .newest) }

    public static func pins(for spec: EngineSpec) -> [NtdllPin] {
        spec == .wine1117 ? pins1117 : pins1119
    }

    /// winecx 4.7.3 (Wine 11.17). The 64-bit detour is byte for byte the one Bridgeplay publishes for this engine.
    static let pins1117: [NtdllPin] = [
        NtdllPin(arch: "x86_64",
                 cleanSHA256: "8b32c9f6f71b4f15fcaccb19b0f2adab9391ae73ad539cae9e136f8ee7d24128",
                 detourFile: "detour2-winecx-4.7.3.bin",
                 detourSHA256: "e1bbd185b19de3e23d627ae3a8bf25ed1b767bff5690102c5312a5ed3813e736",
                 patchedSHA256: "4573d521671a48212670e7543aa9ebf0921e383dada69477f677f435df2bef5a"),
        NtdllPin(arch: "i386",
                 cleanSHA256: "cc8a9035cea0e26c5d333ef220f1becefc27ae44d2cdcdaea3278e8739d26fd9",
                 detourFile: "detour32-winecx-4.7.3.bin",
                 detourSHA256: "085df281ffe81c2803f44dd30df885248e5510c8560f0f20a5ae36e8446f7559",
                 patchedSHA256: "628d08854dc42009f63dc489005c2a49a3f1fe4c6a949dc1ac505915004e5b70"),
    ]

    static let pins1119: [NtdllPin] = [
        NtdllPin(arch: "x86_64",
                 cleanSHA256: "53692da95fb6fac94f320ba11378c07dad37ea9dc3a99237a36882c885ae1ed8",
                 detourFile: "detour2-winecx-4.8.3.bin",
                 detourSHA256: "6a897274f0eba3768cc91fb36a89b65ffa58058ff59c0f0150dff9c1dc409bf6",
                 patchedSHA256: "77ab70fe288d96d3f505912b9275ad798a649b5df9321193fafdb5da17daefaa"),
        NtdllPin(arch: "i386",
                 cleanSHA256: "404264bcb910ca81fd4832e14c2bb8a8a808742fad562ff18df7476575e26473",
                 detourFile: "detour32-winecx-4.8.3.bin",
                 detourSHA256: "e22e92dec742b6b6b52d0bc10aea18c8fd1a73ecb508f83e57c1b80ec857de4c",
                 patchedSHA256: "5d515cf480c596b43e61726a745a1af261228ee95a996c6b9c18a7c078c9212e"),
    ]

    public init(paths: Paths = .live, spec: EngineSpec = .newest) {
        self.paths = paths
        self.spec = spec
    }

    public func output(arch: String) -> URL {
        paths.engines.appending(path: "patched-\(spec.version)/\(arch)-windows/ntdll.dll")
    }

    /// Returns a verified patched ntdll for this architecture, making it if needed.
    public func patched(arch: String) throws -> URL {
        let fm = FileManager.default
        let clean = Engine(paths: paths, spec: spec).wine.appending(path: "lib/wine/\(arch)-windows/ntdll.dll")
        let cleanHash = try Hashing.sha256(of: clean)
        guard let recipe = NtdllRecipe.all.first(where: { $0.arch == arch && $0.cleanSHA256 == cleanHash }) else {
            throw NtdllPatchError.unknownEngine(arch: arch, sha256: cleanHash)
        }

        let out = output(arch: arch)
        if fm.fileExists(atPath: out.path), try Hashing.sha256(of: out) == recipe.patchedSHA256 { return out }

        try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = out.appendingPathExtension("tmp")
        try? fm.removeItem(at: temporary)
        try recipe.apply(to: try Data(contentsOf: clean)).write(to: temporary)

        let actual = try Hashing.sha256(of: temporary)
        guard actual == recipe.patchedSHA256 else {
            try? fm.removeItem(at: temporary)
            throw NtdllPatchError.resultMismatch(arch: arch, expected: recipe.patchedSHA256, actual: actual)
        }
        try? fm.removeItem(at: out)
        try fm.moveItem(at: temporary, to: out)
        return out
    }
}
