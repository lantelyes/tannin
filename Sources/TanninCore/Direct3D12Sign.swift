import Foundation

extension GameLogSigns {
    /// What DXMT writes when Wine's own Direct3D 12 asks it for an interface only Wine's own DXGI has. It is
    /// there whenever a game tries Direct3D 12 on a Mac without D3DMetal (found 2026-11-18; see FINDINGS.md).
    static let direct3D12Asked = "DXGIAdapter: Unknown interface query f0db4c7f-fe5a-42a2-bd62-f2a6cf6fc83e"

    /// True when the game asked for Direct3D 12, did not get it, and nothing else drew it either. A game that
    /// tries Direct3D 12 first and then settles for 11, as LEGO Builder's Journey does, leaves the first line
    /// and then DXMT's own start-up lines, and is not counted: it runs.
    public static func neededDirect3D12(wineLog: String) -> Bool {
        wineLog.contains(direct3D12Asked) && LayerUsage.reading(wineLog: wineLog, d3dMetalPossible: false) == nil
    }

    public static func neededDirect3D12(appID: String, paths: Paths = .live) -> Bool {
        let log = paths.notproton.appending(path: "launchers/\(appID)/notproton-wine.log")
        guard let handle = try? FileHandle(forReadingFrom: log) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 2_000_000),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return false }
        return neededDirect3D12(wineLog: text)
    }
}
