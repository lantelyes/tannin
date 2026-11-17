import AppKit
import TanninCore

/// Development aid: when TANNIN_SNAPSHOT_DIR is set, the app walks its own screens in light and dark,
/// writes each one as a PNG, and quits. An app may draw its own window, so this needs no screen-recording permission.
@MainActor
enum Snapshotter {
    static var outputFolder: URL? {
        ProcessInfo.processInfo.environment["TANNIN_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    static func run(model: AppModel, into folder: URL) async {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        await model.refresh()
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            for item in SidebarItem.allCases {
                model.gamesPath = []
                model.selection = item
                await capture(to: folder.appending(path: "\(item.rawValue)-\(name).png"))
            }
            if let game = model.games.first {
                model.selection = .games
                model.gamesPath = [game]
                await capture(to: folder.appending(path: "game-\(name).png"))
                model.gamesPath = []
            }
            model.selection = .overview
            model.isShowingSteamPlaySheet = true
            await capture(to: folder.appending(path: "sheet-\(name).png"), sheet: true)
            model.isShowingSteamPlaySheet = false
            try? await Task.sleep(for: .milliseconds(500))
        }
        NSApp.terminate(nil)
    }

    private static func capture(to file: URL, sheet: Bool = false) async {
        try? await Task.sleep(for: .milliseconds(900))
        guard let main = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { return }
        let window = sheet ? (main.attachedSheet ?? main) : main
        // The frame view includes the title bar and toolbar, not just the content.
        guard let view = window.contentView?.superview ?? window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: file)
    }
}
