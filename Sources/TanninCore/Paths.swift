import Foundation

/// Every location Tannin reads or writes. Instance-based so tests can point it at a temp folder.
public struct Paths: Sendable {
    public let home: URL
    public let steamApp: URL

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        steamApp: URL = URL(fileURLWithPath: "/Applications/Steam.app")
    ) {
        self.home = home
        self.steamApp = steamApp
    }

    public static let live = Paths()

    public var appSupport: URL { home.appending(path: "Library/Application Support") }
    public var userDownloads: URL { home.appending(path: "Downloads") }

    // Tannin's own folder.
    public var tannin: URL { appSupport.appending(path: "Tannin") }
    public var downloads: URL { tannin.appending(path: "Downloads") }
    public var engines: URL { tannin.appending(path: "Engines") }
    public var gptk: URL { tannin.appending(path: "GPTK") }
    public var kit: URL { tannin.appending(path: "Kit") }
    public var backups: URL { tannin.appending(path: "Backups") }

    /// The folder the Steam add-on reads. The name is fixed by the add-on.
    public var notproton: URL { appSupport.appending(path: "notproton") }

    // Steam.
    public var steamData: URL { appSupport.appending(path: "Steam") }
    public var steamInnerBundle: URL { steamData.appending(path: "Steam.AppBundle/Steam") }
    public var steamInfoPlist: URL { steamApp.appending(path: "Contents/Info.plist") }
    public var steamMacOS: URL { steamApp.appending(path: "Contents/MacOS") }
    public var steamClientManifest: URL {
        steamInnerBundle.appending(path: "Contents/MacOS/package/steam_client_signed_osx.manifest")
    }
    public var steamConfig: URL { steamData.appending(path: "config/config.vdf") }
    public var steamLibraryFolders: URL { steamData.appending(path: "steamapps/libraryfolders.vdf") }
    public var steamCfg: URL { steamData.appending(path: "steam.cfg") }
}
