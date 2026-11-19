import Foundation

public enum KitError: Error, CustomStringConvertible {
    case payloadMissing(String)
    case valveFileMismatch(String, expected: String, actual: String)
    case notUnpacked

    public var description: String {
        switch self {
        case let .payloadMissing(path): return "The NotProton release doesn’t contain \(path)."
        case let .valveFileMismatch(name, expected, actual):
            return "Valve file \(name) doesn’t match its pinned SHA-256 (expected \(expected), got \(actual))."
        case .notUnpacked: return "The Steam Play kit isn't installed. Run: tannin kit install"
        }
    }
}

/// The pieces taken from the NotProton release: the Steam add-on, the Steam bridge, signatures and helpers,
/// plus the Steam client files Valve publishes that the bridge needs.
public struct NotProtonKit: Sendable {
    public let paths: Paths

    public init(paths: Paths = .live) { self.paths = paths }

    /// The unpacked `payload` folder from the release, kept untouched.
    public var payload: URL { paths.kit.appending(path: "notproton-\(Pins.notProtonVersion)/payload") }
    public var addonDylib: URL { payload.appending(path: "notproton.dylib") }
    public var bridge: URL { paths.notproton.appending(path: "bridge") }

    /// Bridge files in the release, and where the add-on's launch script expects each one.
    static let bridgeMap: [(source: String, destinations: [String])] = [
        ("bridge/steam.exe", ["steam.exe"]),
        ("bridge/x86_64-windows-lsteamclient.dll", ["lsteamclient.dll", "x86_64-windows/lsteamclient.dll"]),
        ("bridge/i386-windows-lsteamclient.dll", ["i386-windows/lsteamclient.dll"]),
        ("bridge/x86_64-unix-lsteamclient.so", ["lsteamclient.so", "x86_64-unix/lsteamclient.so"]),
        ("bridge/aarch64-unix-lsteamclient.so", ["aarch64-unix/lsteamclient.so"]),
    ]

    public var isUnpacked: Bool {
        FileManager.default.fileExists(atPath: addonDylib.path)
    }

    /// Downloads and unpacks the pinned NotProton release into Tannin's own folder.
    public func unpack(quiet: Bool = false) throws {
        try unpack(WorkContext(quiet: quiet))
    }

    public func unpack(_ context: WorkContext) throws {
        if isUnpacked { return }
        let fm = FileManager.default
        let zip = try Downloader(paths: paths).fetch(Pins.notProton, context)
        let staging = paths.kit.appending(path: ".unpack-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        try Shell.check("/usr/bin/ditto", ["-x", "-k", zip.path, staging.path])

        let source = staging.appending(path: Pins.notProtonPayloadPath)
        guard fm.fileExists(atPath: source.appending(path: "notproton.dylib").path) else {
            throw KitError.payloadMissing("payload/notproton.dylib")
        }
        let destination = payload
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: source, to: destination)
    }

    /// Copies signatures, bridge, helpers and fonts into the folder the Steam add-on reads.
    public func stage() throws {
        guard isUnpacked else { throw KitError.notUnpacked }
        let fm = FileManager.default
        let target = paths.notproton
        try fm.createDirectory(at: target, withIntermediateDirectories: true)

        func copy(_ from: URL, _ to: URL, executable: Bool = false) throws {
            guard fm.fileExists(atPath: from.path) else {
                throw KitError.payloadMissing(from.path.replacingOccurrences(of: payload.path + "/", with: "payload/"))
            }
            try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: to.path) { try fm.removeItem(at: to) }
            try fm.copyItem(at: from, to: to)
            if executable { try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: to.path) }
        }

        // Signatures: how the add-on finds Steam's functions in each Steam build.
        let signatures = payload.appending(path: "signatures/macos.arm64")
        for file in try fm.contentsOfDirectory(at: signatures, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
            try copy(file, target.appending(path: "signatures/macos.arm64/\(file.lastPathComponent)"))
        }

        // Steam bridge.
        for entry in Self.bridgeMap {
            for destination in entry.destinations {
                try copy(payload.appending(path: entry.source), bridge.appending(path: destination))
            }
        }

        // Helpers.
        try copy(payload.appending(path: "overlay-shim.dylib"), target.appending(path: "overlay-shim.dylib"))
        try copy(payload.appending(path: "iconmaker"), target.appending(path: "iconmaker"), executable: true)
        try copy(payload.appending(path: "appinfo"), target.appending(path: "appinfo"), executable: true)

        // Fonts stand in for the Windows fonts games expect.
        let fonts = payload.appending(path: "fonts")
        if fm.fileExists(atPath: fonts.path) {
            let destination = target.appending(path: "fonts")
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.copyItem(at: fonts, to: destination)
        }
    }

    /// Downloads Valve's packages from Valve's servers and places the pinned files in the bridge folder.
    public func installValveFiles(quiet: Bool = false) throws {
        try installValveFiles(WorkContext(quiet: quiet))
    }

    public func installValveFiles(_ context: WorkContext) throws {
        let fm = FileManager.default
        let downloader = Downloader(paths: paths)
        let packages = [
            "linux": try downloader.fetch(Pins.valveLinux, context),
            "win64": try downloader.fetch(Pins.valveWin64, context),
        ]
        let staging = paths.kit.appending(path: ".valve-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }

        for (name, zip) in packages {
            let inner = Array(Set(Pins.valveFiles.filter { $0.package == name }.map(\.pathInPackage))).sorted()
            let destination = staging.appending(path: name)
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            try Shell.check("/usr/bin/unzip", ["-q", "-o", zip.path] + inner + ["-d", destination.path])
        }

        for file in Pins.valveFiles {
            let source = staging.appending(path: file.package).appending(path: file.pathInPackage)
            let actual = try Hashing.sha256(of: source)
            guard actual == file.sha256 else {
                throw KitError.valveFileMismatch(file.destination, expected: file.sha256, actual: actual)
            }
            let destination = bridge.appending(path: file.destination)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.copyItem(at: source, to: destination)
        }
    }

    /// Everything the launch script needs from this kit, relative to the add-on's folder.
    public static let stagedFiles: [String] =
        bridgeMap.flatMap { $0.destinations.map { "bridge/\($0)" } }
        + Pins.valveFiles.map { "bridge/\($0.destination)" }
        + ["overlay-shim.dylib", "iconmaker", "appinfo"]

    public func missingStagedFiles() -> [String] {
        let fm = FileManager.default
        var missing = Self.stagedFiles.filter { !fm.fileExists(atPath: paths.notproton.appending(path: $0).path) }
        let signatures = (try? fm.contentsOfDirectory(atPath: paths.notproton.appending(path: "signatures/macos.arm64").path)) ?? []
        if !signatures.contains(where: { $0.hasSuffix(".json") }) { missing.append("signatures/macos.arm64/*.json") }
        return missing
    }
}
