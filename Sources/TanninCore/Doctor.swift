import Foundation

/// One line of the health report. States carry a word, never colour alone.
public struct Check: Sendable, Equatable {
    public enum State: String, Sendable {
        case ok = "ok"
        case attention = "attention"
        case broken = "broken"
        case info = "info"
    }

    public let name: String
    public let state: State
    public let detail: String

    public init(_ name: String, _ state: State, _ detail: String) {
        self.name = name
        self.state = state
        self.detail = detail
    }
}

/// Checks this Mac without changing anything, unless the caller asks for the Steam write probe.
public struct Doctor: Sendable {
    public let paths: Paths

    public init(paths: Paths = .live) { self.paths = paths }

    public func run(probeSteam: Bool = false) -> [Check] {
        var checks: [Check] = []
        let fm = FileManager.default
        let steam = SteamInstall(paths: paths)

        // Mac
        let machine = (try? Shell.run("/usr/bin/uname", ["-m"]))?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
        checks.append(machine == "arm64"
            ? Check("Mac", .ok, "Apple silicon, macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
            : Check("Mac", .broken, "Tannin needs Apple silicon. This Mac reports \(machine)."))

        let rosetta = fm.fileExists(atPath: "/Library/Apple/usr/share/rosetta/rosetta")
        checks.append(rosetta
            ? Check("Rosetta", .ok, "Installed.")
            : Check("Rosetta", .broken, "Not installed. Run: softwareupdate --install-rosetta"))

        // Steam
        if steam.isInstalled {
            let signature = steam.signature()
            let injected = steam.injectedLibraries()
            if signature.isValve, injected == nil {
                checks.append(Check("Steam", .ok, "Found in Applications, unmodified."))
            } else if let injected {
                checks.append(Check("Steam", .info, "Steam Play add-on is installed (\(injected))."))
            } else {
                checks.append(Check("Steam", .attention,
                                    "Steam.app isn't Valve-signed (team \(signature.teamID ?? "none"), valid: \(signature.valid))."))
            }
            checks.append(Check("Steam build", .info, steam.clientBuild() ?? "unknown; Steam hasn't run yet"))
            checks.append(Check("Steam running", .info, steam.isRunning() ? "yes" : "no"))
            let apps = steam.installedApps()
            checks.append(Check("Installed games", .info,
                                apps.isEmpty ? "none" : apps.map { "\($0.name) (\($0.appID))" }.joined(separator: ", ")))
        } else {
            checks.append(Check("Steam", .broken, "Not found at \(paths.steamApp.path). Install Steam first."))
        }

        // Disk
        if let values = try? paths.home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let free = values.volumeAvailableCapacityForImportantUsage {
            let gb = Double(free) / 1_000_000_000
            let text = String(format: "%.0f GB free", gb)
            checks.append(gb >= 10 ? Check("Disk space", .ok, text) : Check("Disk space", .attention, "\(text). The engine and one game need about 10 GB."))
        }

        // Stray Wine processes
        let wine = (try? Shell.run("/usr/bin/pgrep", ["-fl", "-i", "wineserver|wine64|wine-preloader|winedevice|steam\\.exe"]))?.stdout ?? ""
        let wineLines = wine.split(separator: "\n").filter { !$0.contains("pgrep") }
        checks.append(wineLines.isEmpty
            ? Check("Other Wine processes", .ok, "None running.")
            : Check("Other Wine processes", .attention, "\(wineLines.count) running. Quit other Wine apps before testing."))

        // Game Porting Toolkit download
        let downloads = (try? fm.contentsOfDirectory(atPath: paths.userDownloads.path)) ?? []
        let toolkit = downloads.filter {
            let lower = $0.lowercased()
            return lower.hasSuffix(".dmg") && (lower.contains("game_porting_toolkit") || lower.contains("game porting toolkit") || lower.contains("evaluation environment"))
        }
        checks.append(toolkit.isEmpty
            ? Check("Game Porting Toolkit", .attention, "No disk image in Downloads. Get it from developer.apple.com/download/all/?q=game%20porting%20toolkit")
            : Check("Game Porting Toolkit", .ok, "Found in Downloads: \(toolkit.joined(separator: ", "))"))

        // Build tools for the ntdll patch
        let mingw = fm.fileExists(atPath: "/opt/homebrew/bin/x86_64-w64-mingw32-gcc")
        checks.append(mingw
            ? Check("mingw-w64", .ok, "Installed.")
            : Check("mingw-w64", .attention, "Not installed. Needed once to build the Steam bridge patch: brew install mingw-w64"))

        if probeSteam, steam.isInstalled {
            checks.append(probeSteamWrite())
        }
        return checks
    }

    /// Creates and removes one empty file inside Steam.app to learn whether macOS lets this program change it.
    func probeSteamWrite() -> Check {
        let probe = paths.steamMacOS.appending(path: ".tannin-write-probe-\(UUID().uuidString)")
        let created = FileManager.default.createFile(atPath: probe.path, contents: nil)
        if created {
            try? FileManager.default.removeItem(at: probe)
            return Check("Permission to change Steam", .ok, "Allowed.")
        }
        return Check("Permission to change Steam", .attention,
                     "Not allowed yet. In System Settings > Privacy & Security > App Management, allow your terminal app.")
    }
}
