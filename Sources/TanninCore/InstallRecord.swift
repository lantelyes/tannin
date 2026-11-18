import Foundation

/// The version of Tannin this code is. Kept equal to the `VERSION` file by a test.
public enum TanninVersion {
    public static let current = "0.7.0"
}

/// What Tannin has installed and from which versions, written whenever it builds or changes those parts.
///
/// An install with no record was made by Tannin 0.2, whose versions are known. The record keeps the parts every
/// runner shares (the Steam bridge) apart from what belongs to one runner (engine, D3DMetal), so that several
/// runners can be listed later.
public struct InstallRecord: Codable, Sendable, Equatable {
    public struct Shared: Codable, Sendable, Equatable {
        public var bridgeVersion: String
    }

    public struct RunnerEntry: Codable, Sendable, Equatable {
        public var tool: String
        public var build: String
        public var engineVersion: String
        public var wineVersion: String
        /// SHA-256 of the runner's ntdll, per bit width.
        public var ntdll: [String: String]
        public var d3dMetalVersion: String?
        public var dxmtVersion: String
        public var dxvkVersion: String
        /// The Tannin that last built or changed this runner.
        public var tannin: String
    }

    public var shared: Shared
    public var runners: [RunnerEntry]

    /// Reads the record, or nil when there is none.
    public static func read(paths: Paths = .live) -> InstallRecord? {
        guard let data = try? Data(contentsOf: paths.installRecord) else { return nil }
        return try? JSONDecoder().decode(InstallRecord.self, from: data)
    }

    /// The record of what is on disk now. Nil when no runner has been built.
    public static func current(paths: Paths = .live) -> InstallRecord? {
        let entries = EngineSpec.all.compactMap { spec -> RunnerEntry? in
            let runner = Runner(paths: paths, spec: spec)
            guard runner.exists else { return nil }
            var ntdll: [String: String] = [:]
            for arch in ["x86_64", "i386"] {
                ntdll[arch] = try? Hashing.sha256(of: runner.root.appending(path: "lib/wine/\(arch)-windows/ntdll.dll"))
            }
            return RunnerEntry(
                tool: spec.toolName, build: spec.build, engineVersion: spec.version, wineVersion: spec.wine,
                ntdll: ntdll, d3dMetalVersion: D3DMetalLink(paths: paths, spec: spec).linkedVersion(),
                dxmtVersion: LayerStore.dxmtVersion, dxvkVersion: LayerStore.dxvkVersion, tannin: TanninVersion.current
            )
        }
        return entries.isEmpty ? nil : InstallRecord(shared: Shared(bridgeVersion: Pins.notProtonVersion), runners: entries)
    }

    /// Writes the record of what is on disk now.
    public static func write(paths: Paths = .live) throws {
        guard let record = current(paths: paths) else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: paths.tannin, withIntermediateDirectories: true)
        try encoder.encode(record).write(to: paths.installRecord, options: .atomic)
    }
}
