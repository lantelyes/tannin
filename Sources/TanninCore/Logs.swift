import Foundation

public struct LogLine: Sendable, Equatable, Identifiable {
    public enum Level: String, Sendable {
        case info, warning, error
    }

    public let id: Int
    public let time: String
    public let level: Level
    public let source: String
    public let message: String
}

/// Reads the Steam add-on's log. It is the only place that says whether the add-on loaded.
public struct LogReader: Sendable {
    public let paths: Paths

    public init(paths: Paths = .live) { self.paths = paths }

    public var addonLog: URL { paths.notproton.appending(path: "notproton.log") }

    /// Parses lines shaped like `2026-11-17 23:47:02 [notproton] info resolver: 18/18 signatures resolved`.
    static func parse(_ text: String, limit: Int) -> [LogLine] {
        let raw = text.split(separator: "\n", omittingEmptySubsequences: true).suffix(limit)
        var lines: [LogLine] = []
        for (index, line) in raw.enumerated() {
            let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard parts.count == 5, parts[2].hasPrefix("[") else {
                lines.append(LogLine(id: index, time: "", level: .info, source: "", message: String(line)))
                continue
            }
            let level: LogLine.Level = switch parts[3] {
            case "error": .error
            case "warn", "warning": .warning
            default: .info
            }
            let rest = String(parts[4])
            var source = ""
            var message = rest
            if let colon = rest.range(of: ": "), !rest[..<colon.lowerBound].contains(" ") {
                source = String(rest[..<colon.lowerBound])
                message = String(rest[colon.upperBound...])
            }
            lines.append(LogLine(id: index, time: String(parts[1]), level: level, source: source, message: message))
        }
        return lines
    }

    public func recentLines(limit: Int = 400) -> [LogLine] {
        guard let text = try? String(contentsOf: addonLog, encoding: .utf8) else { return [] }
        return Self.parse(text, limit: limit)
    }

    /// True if the add-on's most recent verdict was "hooks installed", false if it gave up, nil if it never ran.
    public func addonLoadedOnLastStart() -> Bool? {
        guard let text = try? String(contentsOf: addonLog, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() {
            if line.contains("install_thread: ready,") { return true }
            if line.contains("installing nothing") { return false }
        }
        return nil
    }

    /// Text for a bug report: versions plus the last lines of the log, with the home folder written as "~".
    public func bugReport(status: TanninStatus, lines: Int = 60) -> String {
        var out = [
            "Tannin bug report",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Steam build: \(status.steamBuild ?? "unknown")",
            "Steam Play: \(status.steamPlay)",
            "Add-on loaded on last start: \(status.addonLoaded.map(String.init) ?? "never ran")",
            "Wine engine: \(status.engineInstalled ? status.engineWine : "not installed")",
            "D3DMetal: \(status.d3dMetalVersion ?? "not imported")",
            "Steam bridge: NotProton \(status.bridgeVersion)",
            "Update freeze: \(status.updateFreeze ? "on" : "off")",
            "",
            "Last \(lines) log lines:",
        ]
        out += recentLines(limit: lines).map { "\($0.time) \($0.level.rawValue) \($0.source) \($0.message)" }
        return out.joined(separator: "\n").replacingOccurrences(of: paths.home.path, with: "~")
    }
}
