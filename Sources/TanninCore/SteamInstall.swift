import Foundation

public struct SteamSignature: Sendable, Equatable {
    public let identifier: String?
    public let teamID: String?
    public let valid: Bool

    /// True only for an untouched Steam.app as Valve ships it.
    public var isValve: Bool {
        valid && teamID == Pins.valveTeamID && identifier == Pins.steamBundleID
    }
}

public struct SteamApp: Sendable, Equatable {
    public let appID: String
    public let name: String
    public let installDir: String
    public let library: URL
}

/// Read-only facts about the Steam installation on this Mac.
public struct SteamInstall: Sendable {
    public let paths: Paths

    public init(paths: Paths = .live) { self.paths = paths }

    public var isInstalled: Bool {
        FileManager.default.fileExists(atPath: paths.steamMacOS.appending(path: "steam_osx").path)
    }

    /// The client build number Steam last updated itself to, if it has run on this Mac.
    public func clientBuild() -> String? {
        guard let manifest = try? VDF.load(paths.steamClientManifest) else { return nil }
        // The file has a single root object whose name varies; the version sits directly inside it.
        for pair in manifest.pairs {
            if let version = pair.value["version"]?.string { return version }
        }
        return nil
    }

    public func signature() -> SteamSignature {
        let app = paths.steamApp.path
        let describe = try? Shell.run("/usr/bin/codesign", ["-dv", app])
        let lines = (describe?.stderr ?? "").split(separator: "\n").map(String.init)
        func field(_ name: String) -> String? {
            lines.first { $0.hasPrefix("\(name)=") }.map { String($0.dropFirst(name.count + 1)) }
        }
        let verify = try? Shell.run("/usr/bin/codesign", ["--verify", "--strict", app])
        return SteamSignature(
            identifier: field("Identifier"),
            teamID: field("TeamIdentifier"),
            valid: verify?.ok ?? false
        )
    }

    /// The library Steam.app is told to load at start, if any. Nil on an untouched Steam.
    public func injectedLibraries() -> String? {
        guard
            let data = try? Data(contentsOf: paths.steamInfoPlist),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let environment = plist["LSEnvironment"] as? [String: Any]
        else { return nil }
        return environment["DYLD_INSERT_LIBRARIES"] as? String
    }

    public func isRunning() -> Bool {
        (try? Shell.run("/usr/bin/pgrep", ["-x", "steam_osx"]))?.ok ?? false
    }

    /// Every Steam library folder, including the default one.
    public func libraries() -> [URL] {
        var result: [URL] = [paths.steamData]
        if let folders = try? VDF.load(paths.steamLibraryFolders), let root = folders["libraryfolders"] {
            for pair in root.pairs {
                if let path = pair.value["path"]?.string {
                    let url = URL(fileURLWithPath: path)
                    if !result.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) {
                        result.append(url)
                    }
                }
            }
        }
        return result
    }

    public func installedApps() -> [SteamApp] {
        var apps: [SteamApp] = []
        for library in libraries() {
            let steamapps = library.appending(path: "steamapps")
            let files = (try? FileManager.default.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.lastPathComponent.hasPrefix("appmanifest_") && file.pathExtension == "acf" {
                guard let manifest = try? VDF.load(file), let state = manifest["AppState"] else { continue }
                guard let appID = state["appid"]?.string else { continue }
                apps.append(SteamApp(
                    appID: appID,
                    name: state["name"]?.string ?? appID,
                    installDir: state["installdir"]?.string ?? "",
                    library: library
                ))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
