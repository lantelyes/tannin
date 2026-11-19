import Foundation

/// Which renderer a game ran on the last time it was started, as far as its logs show.
///
/// DXMT and DXVK both write lines of their own into the game's Wine log. D3DMetal writes none, so it is only
/// named when everything else points to it; and nothing in the log tells a Direct3D 9 game on Wine's own layer
/// from a game that never reached its graphics. When in doubt the answer is nil and the app says nothing.
/// (Found with LEGO Builder's Journey and Just Cause 2 on 2026-11-18; see FINDINGS.md.)
public enum LayerUsage: String, Sendable, Equatable {
    case d3dMetal, dxmt, dxvk
    /// Wine's own layer, which is what Direct3D 9 and older get.
    case wineOwn

    public var title: String {
        switch self {
        case .d3dMetal: "D3DMetal"
        case .dxmt: "DXMT"
        case .dxvk: "DXVK"
        case .wineOwn: "WineD3D"
        }
    }

    /// Reads it from the text of a game's Wine log. `d3dMetalPossible` says whether D3DMetal could have been
    /// what answered: a 64-bit game on a runner that has it.
    public static func reading(wineLog: String, d3dMetalPossible: Bool) -> LayerUsage? {
        if wineLog.contains("info:  DXVK: v") { return .dxvk }
        // DXMT's own start-up lines. DXVK's carry a function name in front, so they do not match.
        if wineLog.contains("\ninfo:  Using feature level D3D_FEATURE_LEVEL") || wineLog.contains("\ninfo:  Maximum supported feature level:") {
            return .dxmt
        }
        // Only present when the user has Wine list the libraries it loads.
        let loaded = wineLog.contains("trace:loaddll")
        if loaded {
            // A line reads: Loaded L"C:\\windows\\system32\\d3d11.dll" at …, with the backslashes doubled.
            func has(_ name: String) -> Bool { wineLog.range(of: "\\\\\(name)\" at ", options: .caseInsensitive) != nil }
            let modern = has("d3d11.dll") || has("d3d12.dll") || has("d3d10core.dll")
            if modern, d3dMetalPossible { return .d3dMetal }
            if !modern, has("d3d9.dll") || has("d3d8.dll") { return .wineOwn }
        }
        // D3DMetal starts Apple's upscaler, which leaves this line; DXMT and DXVK runs do not have it.
        if d3dMetalPossible, wineLog.contains("com.apple.appleneuralengine") { return .d3dMetal }
        return nil
    }

    /// The layer a game last ran on, or nil when its log does not say.
    public static func lastRun(appID: String, is32Bit: Bool?, paths: Paths = .live) -> LayerUsage? {
        let log = paths.notproton.appending(path: "launchers/\(appID)/notproton-wine.log")
        guard let handle = try? FileHandle(forReadingFrom: log) else { return nil }
        defer { try? handle.close() }
        // The layers announce themselves when the game starts, so the start of the log is enough.
        guard let data = try? handle.read(upToCount: 2_000_000), let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        let onBaseRunner = !lastSessionUsedVariant(appID: appID, paths: paths)
        let possible = is32Bit == false && onBaseRunner && D3DMetalLink(paths: paths).linkedVersion() != nil
        return reading(wineLog: text, d3dMetalPossible: possible)
    }

    /// Whether the game's last start asked the launch script for one of the per-layer copies of the runner.
    static func lastSessionUsedVariant(appID: String, paths: Paths) -> Bool {
        guard let steamLibrary = SteamInstall(paths: paths).libraries().first(where: {
            FileManager.default.fileExists(atPath: $0.appending(path: "steamapps/compatdata/\(appID)").path)
        }) else { return false }
        let log = steamLibrary.appending(path: "steamapps/compatdata/\(appID)/notproton-run.log")
        guard let text = try? String(contentsOf: log, encoding: .utf8) else { return false }
        let lastSession = text.components(separatedBy: "=== notproton run ").last ?? ""
        return lastSession.contains("runner: variant asked for")
    }
}
