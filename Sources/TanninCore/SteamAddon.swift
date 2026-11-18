import Foundation

public enum SteamAddonError: Error, CustomStringConvertible {
    case steamMissing
    case kitMissing
    case foreignLibrary(String)
    case notPermitted
    case steamStillRunning
    case signingFailed(String)
    case restoreNotValve(String)

    public var description: String {
        switch self {
        case .steamMissing: return "Steam.app was not found in Applications."
        case .kitMissing: return "The Steam bridge is not installed yet. Finish setup first (in the app, Set Up Tannin; on the command line, tannin kit install)."
        case let .foreignLibrary(value):
            return "Steam is already set to load something else (\(value)). Tannin will not overwrite it. Remove the other tool first."
        case .notPermitted:
            return "macOS did not let Tannin change Steam.app. In System Settings > Privacy & Security > App Management, allow Tannin (or the terminal app, if you ran the command line tool), then try again."
        case .steamStillRunning: return "Steam did not quit. Quit Steam and try again."
        case let .signingFailed(detail): return "Signing Steam failed: \(detail). Remove Steam Play to put Steam back as Valve ships it."
        case let .restoreNotValve(detail): return "The downloaded Steam.app is not signed by Valve (\(detail)). Nothing was replaced."
        }
    }
}

/// Adds Steam Play to Steam.app and takes it out again.
///
/// Enabling places one library inside Steam.app, tells Steam to load it, and signs Steam again on this Mac.
/// Disabling puts back a copy of Steam.app signed by Valve, downloaded from Valve and checked first.
public struct SteamAddon: Sendable {
    public let paths: Paths

    public enum State: Equatable, Sendable {
        case off
        case on
        case foreign(String)
    }

    public init(paths: Paths = .live) { self.paths = paths }

    static let insertKey = "DYLD_INSERT_LIBRARIES"
    static let joystickKey = "SDL_JOYSTICK_BLACKLIST_DEVICES"
    static let joystickValue = "0x05ac/0x0004"

    public var installedLibrary: URL { paths.steamMacOS.appending(path: "notproton.dylib") }
    var plistBackup: URL { paths.backups.appending(path: "Steam-Info.plist.before-tannin") }

    public func state() -> State {
        guard let value = SteamInstall(paths: paths).injectedLibraries() else { return .off }
        return value == installedLibrary.path ? .on : .foreign(value)
    }

    // MARK: Info.plist edits (pure, tested)

    /// Returns the plist with Steam told to load `library`. Keeps the original format and every other key.
    static func plist(_ data: Data, loading library: String) throws -> Data {
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard var root = try PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        var environment = root["LSEnvironment"] as? [String: Any] ?? [:]
        environment[insertKey] = library
        environment[joystickKey] = joystickValue
        root["LSEnvironment"] = environment
        return try PropertyListSerialization.data(fromPropertyList: root, format: format, options: 0)
    }

    /// Returns the plist with Tannin's two keys removed.
    static func plistWithoutAddon(_ data: Data) throws -> Data {
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard var root = try PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        if var environment = root["LSEnvironment"] as? [String: Any] {
            environment.removeValue(forKey: insertKey)
            environment.removeValue(forKey: joystickKey)
            if environment.isEmpty { root.removeValue(forKey: "LSEnvironment") } else { root["LSEnvironment"] = environment }
        }
        return try PropertyListSerialization.data(fromPropertyList: root, format: format, options: 0)
    }

    // MARK: Steam process

    /// Asks Steam to quit, then insists. Throws if it is still running afterwards.
    public func stopSteam() throws {
        let steam = SteamInstall(paths: paths)
        guard steam.isRunning() else { return }
        _ = try? Shell.run("/usr/bin/open", ["-g", "steam://exit"])
        for _ in 0..<30 {
            if !steam.isRunning() { return }
            Thread.sleep(forTimeInterval: 1)
        }
        _ = try? Shell.run("/usr/bin/pkill", ["-x", "steam_osx"])
        Thread.sleep(forTimeInterval: 2)
        if steam.isRunning() { throw SteamAddonError.steamStillRunning }
    }

    // MARK: Enable

    /// The changes `enable` makes, in order, for showing to the user before anything happens.
    public func enablePlan() -> [String] {
        [
            "Quit Steam if it is running.",
            "Copy the add-on to \(installedLibrary.path)",
            "Add two keys to \(paths.steamInfoPlist.path) (a backup goes to \(plistBackup.path))",
            "Sign Steam.app again on this Mac (Valve's signature is replaced).",
            "Reset Steam's Accessibility and input-monitoring permissions; macOS will ask for them again.",
            "Re-register Steam.app with macOS.",
        ]
    }

    public func enable() throws {
        let fm = FileManager.default
        let steam = SteamInstall(paths: paths)
        guard steam.isInstalled else { throw SteamAddonError.steamMissing }
        let source = NotProtonKit(paths: paths).addonDylib
        guard fm.fileExists(atPath: source.path) else { throw SteamAddonError.kitMissing }
        if case let .foreign(value) = state() { throw SteamAddonError.foreignLibrary(value) }

        try stopSteam()

        // Permission check before changing anything real.
        let probe = paths.steamMacOS.appending(path: ".tannin-write-probe-\(UUID().uuidString)")
        guard fm.createFile(atPath: probe.path, contents: nil) else { throw SteamAddonError.notPermitted }
        try? fm.removeItem(at: probe)

        let originalPlist = try Data(contentsOf: paths.steamInfoPlist)
        try fm.createDirectory(at: paths.backups, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: plistBackup.path) { try originalPlist.write(to: plistBackup) }

        // Library: copy beside its destination, then swap in, so Steam never sees half a file.
        let staged = paths.steamMacOS.appending(path: ".notproton.dylib.\(UUID().uuidString)")
        try fm.copyItem(at: source, to: staged)
        if fm.fileExists(atPath: installedLibrary.path) { try fm.removeItem(at: installedLibrary) }
        try fm.moveItem(at: staged, to: installedLibrary)

        try Self.plist(originalPlist, loading: installedLibrary.path).write(to: paths.steamInfoPlist, options: .atomic)

        do {
            try sign()
        } catch {
            // Put the plist back and take the library out, so Steam is not left loading nothing.
            try? originalPlist.write(to: paths.steamInfoPlist, options: .atomic)
            try? fm.removeItem(at: installedLibrary)
            _ = try? sign()
            throw error
        }

        // The signature changed, so macOS no longer trusts Steam's old input permissions; clear them so it asks again.
        for service in ["Accessibility", "PostEvent", "ListenEvent"] {
            _ = try? Shell.run("/usr/bin/tccutil", ["reset", service, Pins.steamBundleID])
        }
        registerWithLaunchServices()
    }

    func sign() throws {
        let targets = [installedLibrary.path, paths.steamMacOS.appending(path: "steam_osx").path, paths.steamApp.path]
            .filter { FileManager.default.fileExists(atPath: $0) }
        for (index, target) in targets.enumerated() {
            var result = try Shell.run("/usr/bin/codesign", ["-f", "-s", "-", target])
            if !result.ok, result.stderr.contains("detritus") {
                for attribute in ["com.apple.FinderInfo", "com.apple.ResourceFork"] {
                    _ = try? Shell.run("/usr/bin/xattr", ["-r", "-d", attribute, paths.steamApp.path])
                }
                result = try Shell.run("/usr/bin/codesign", ["-f", "-s", "-", target])
            }
            guard result.ok else {
                throw SteamAddonError.signingFailed("step \(index + 1): \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
    }

    func registerWithLaunchServices() {
        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        _ = try? Shell.run(lsregister, ["-f", paths.steamApp.path])
    }

    // MARK: Disable

    public func disablePlan() -> [String] {
        [
            "Quit Steam if it is running.",
            "Download Steam.app from Valve (\(Pins.steamBundle.name)) and check its SHA-256.",
            "Check that copy is signed by Valve (team \(Pins.valveTeamID)).",
            "Move the current Steam.app to \(paths.backups.path) and put Valve's copy in its place.",
            "Remove Tannin's Steam update freeze, if set.",
        ]
    }

    /// Puts back a Valve-signed Steam.app. Games, saves and the Steam account live elsewhere and are not touched.
    public func disable(quiet: Bool = false) throws {
        let fm = FileManager.default
        guard SteamInstall(paths: paths).isInstalled else { throw SteamAddonError.steamMissing }
        try stopSteam()

        let zip = try Downloader(paths: paths).fetch(Pins.steamBundle, quiet: quiet)
        let work = paths.backups.appending(path: ".restore-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        try Shell.check("/usr/bin/unzip", ["-q", "-o", zip.path, "SteamMacBootstrapper.tar.gz", "-d", work.path])
        try Shell.check("/usr/bin/tar", ["-xzf", work.appending(path: "SteamMacBootstrapper.tar.gz").path, "-C", work.path])

        let fresh = work.appending(path: "Steam.app")
        let signature = SteamInstall(paths: Paths(home: paths.home, steamApp: fresh)).signature()
        guard signature.isValve else {
            throw SteamAddonError.restoreNotValve("team \(signature.teamID ?? "none"), identifier \(signature.identifier ?? "none"), valid \(signature.valid)")
        }

        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        let retired = paths.backups.appending(path: "Steam.app.replaced-\(stamp)")
        try fm.moveItem(at: paths.steamApp, to: retired)
        do {
            try fm.moveItem(at: fresh, to: paths.steamApp)
        } catch {
            try? fm.moveItem(at: retired, to: paths.steamApp)
            throw error
        }
        registerWithLaunchServices()
        try UpdateFreeze(paths: paths).set(false)
    }
}
