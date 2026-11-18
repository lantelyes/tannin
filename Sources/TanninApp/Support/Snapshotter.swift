import AppKit
import TanninCore

/// Development aid: when TANNIN_SNAPSHOT_DIR is set, the app walks its own screens in light and dark,
/// writes each one as a PNG, and quits. An app may draw its own window, so this needs no screen-recording permission.
/// States this Mac is not in are shown from prepared data (`Fixture`); nothing outside the app is changed.
@MainActor
enum Snapshotter {
    static var outputFolder: URL? {
        ProcessInfo.processInfo.environment["TANNIN_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    static func run(model: AppModel, into folder: URL, openWindow: (String) -> Void) async {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? await Task.sleep(for: .milliseconds(600))
        window(WindowID.main)?.setContentSize(NSSize(width: 940, height: 640))
        // Controls are drawn greyed in a window that is not in front, so bring the app forward for its pictures.
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)

        let appearances = [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)]
        for (name, appearance) in appearances {
            NSApp.appearance = NSAppearance(named: appearance)

            await model.showLiveData()
            await capture(WindowID.main, to: folder.appending(path: "live-\(name).png"))

            for scenario in Fixture.mainWindowScenarios {
                model.show(scenario.fixture)
                let isSheet = scenario.fixture.isShowingSteamPlaySheet
                await capture(WindowID.main, to: folder.appending(path: "\(scenario.name)-\(name).png"), sheet: isSheet)
                if isSheet {
                    model.isShowingSteamPlaySheet = false
                    try? await Task.sleep(for: .milliseconds(600))
                }
            }
        }

        openWindow(WindowID.setup)
        for (name, appearance) in appearances {
            NSApp.appearance = NSAppearance(named: appearance)
            model.show(.setupDownloading)
            await capture(WindowID.setup, to: folder.appending(path: "setup-\(name).png"))
        }
        NSApp.terminate(nil)
    }

    /// SwiftUI names each window after its scene, sometimes with a suffix.
    private static func window(_ id: String) -> NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.canBecomeMain && ($0.identifier?.rawValue.hasPrefix(id) ?? false) }
    }

    private static func capture(_ id: String, to file: URL, sheet: Bool = false) async {
        window(id)?.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(900))
        guard let window = window(id) else {
            FileHandle.standardError.write(Data("no window \(id): \(NSApp.windows.map { $0.identifier?.rawValue ?? "?" })\n".utf8))
            return
        }
        // The system's own window capture, so glass, materials and the toolbar come out as they look on screen.
        // A sheet is part of its parent window's picture.
        let number = String(window.windowNumber)
        let path = file.path
        _ = await Task.detached {
            try? Shell.run("/usr/sbin/screencapture", ["-x", "-o", "-l", number, path])
        }.value
    }
}
