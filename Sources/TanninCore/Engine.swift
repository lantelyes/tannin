import Foundation

public enum EngineError: Error, CustomStringConvertible {
    case missingFile(String)
    case notInstalled

    public var description: String {
        switch self {
        case let .missingFile(path): return "The engine archive is not laid out as expected: \(path) is missing."
        case .notInstalled: return "The Wine engine is not installed. Run: tannin engine install"
        }
    }
}

/// The Wine engine: a free build of Wine from CodeWeavers' published CrossOver sources.
public struct Engine: Sendable {
    public let paths: Paths

    public init(paths: Paths = .live) { self.paths = paths }

    /// Where the unpacked, untouched engine lives. Runners are cloned from here.
    public var root: URL { paths.engines.appending(path: "winecx-\(Pins.engineVersion)") }
    public var wine: URL { root.appending(path: "Wine") }

    /// Files the Steam add-on's launch script and the bridge patch rely on.
    public static let requiredFiles = [
        "bin/wineserver",
        "lib/wine/x86_64-unix/wine",
        "lib/wine/x86_64-unix/ntdll.so",
        "lib/wine/x86_64-windows/ntdll.dll",
        "lib/wine/i386-windows/ntdll.dll",
        "share/wine/wine.inf",
    ]

    public var isInstalled: Bool {
        Self.requiredFiles.allSatisfy { FileManager.default.fileExists(atPath: wine.appending(path: $0).path) }
    }

    /// Downloads (if needed), verifies and unpacks the engine. Safe to run again.
    @discardableResult
    public func install(quiet: Bool = false) throws -> URL {
        try install(WorkContext(quiet: quiet))
    }

    /// Downloads (if needed), verifies and unpacks the engine. Safe to run again, and to cancel and run again.
    @discardableResult
    public func install(_ context: WorkContext) throws -> URL {
        if isInstalled { return root }
        let fm = FileManager.default
        let archive = try Downloader(paths: paths).fetch(Pins.engine, context)

        try fm.createDirectory(at: paths.engines, withIntermediateDirectories: true)
        let staging = paths.engines.appending(path: ".unpack-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        // bsdtar refuses absolute paths and ".." by default, so the archive cannot write outside `staging`.
        try Shell.check("/usr/bin/tar", ["-xzf", archive.path, "-C", staging.path], cancellation: context.cancellation)

        let unpacked = staging.appending(path: "Libraries")
        for file in Self.requiredFiles {
            let path = unpacked.appending(path: "Wine").appending(path: file)
            guard fm.fileExists(atPath: path.path) else { throw EngineError.missingFile("Libraries/Wine/\(file)") }
        }
        if fm.fileExists(atPath: root.path) { try fm.removeItem(at: root) }
        try fm.moveItem(at: unpacked, to: root)
        return root
    }

    /// How much disk the unpacked engine takes. Walks the whole folder, so ask once and keep the answer.
    public func sizeOnDisk() -> Int64? {
        guard isInstalled, let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return nil }
        var total: Int64 = 0
        for case let file as URL in files {
            total += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }

    /// What the engine says about itself, e.g. "wine-11.19".
    public func reportedVersion() throws -> String {
        guard isInstalled else { throw EngineError.notInstalled }
        let result = try Shell.check(wine.appending(path: "lib/wine/x86_64-unix/wine").path, ["--version"])
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// SHA-256 of the engine's untouched ntdll, which the bridge patch is derived from and keyed to.
    public func cleanNtdllHash(arch: String) throws -> String {
        guard isInstalled else { throw EngineError.notInstalled }
        return try Hashing.sha256(of: wine.appending(path: "lib/wine/\(arch)-windows/ntdll.dll"))
    }
}
