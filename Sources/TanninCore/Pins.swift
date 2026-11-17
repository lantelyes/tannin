import Foundation

/// A download Tannin is willing to use: where it comes from and exactly what it must hash to.
public struct Pin: Sendable, Equatable {
    public let name: String
    public let urls: [String]
    public let sha256: String
    public let size: Int64?

    public init(name: String, urls: [String], sha256: String, size: Int64? = nil) {
        self.name = name
        self.urls = urls
        self.sha256 = sha256
        self.size = size
    }
}

/// One file taken out of a Valve package and placed in the bridge folder.
public struct ValveFile: Sendable, Equatable {
    public let destination: String
    public let package: String
    public let pathInPackage: String
    public let sha256: String
}

public enum Pins {
    /// Wine engine: CrossOver 26.3 changes on Wine 11.19, built by public CI.
    public static let engine = Pin(
        name: "winecx-gptk-4.8.3-Libraries.tar.gz",
        urls: ["https://github.com/frankea/winecx-gptk/releases/download/runtime-v4.8.3/Libraries.tar.gz"],
        sha256: "08ffabd7b7c352470faee2b1d51061b341316e401439ca805c5302acc2fb8818",
        size: 479_015_992
    )
    public static let engineVersion = "4.8.3"
    public static let engineWine = "11.19"

    /// NotProton release: Steam add-on, Steam bridge, signatures, helpers.
    public static let notProton = Pin(
        name: "NotProton-1.2.6.zip",
        urls: ["https://github.com/NotProtonNot/NotProton/releases/download/v1.2.6/NotProton.zip"],
        sha256: "595e6d6293a8372dd06c4fce423df39764c5986fb1577cd3af1ee3296ea0188a",
        size: 73_533_382
    )
    public static let notProtonVersion = "1.2.6"
    public static let notProtonPayloadPath =
        "NotProton.app/Contents/Resources/NotProtonApp_NotProtonApp.bundle/Contents/Resources/payload"

    // Valve's own files, from Valve's CDN. Hashes copied from NotProton v1.2.6 `valve-packages.manifest`.
    private static let valveBases = [
        "https://client-update.akamai.steamstatic.com",
        "https://steamcdn-a.akamaihd.net/client",
        "https://media.steampowered.com/client",
    ]
    private static func valve(_ file: String, _ sha256: String) -> Pin {
        Pin(name: file, urls: valveBases.map { "\($0)/\(file)" }, sha256: sha256)
    }

    public static let valveLinux = valve(
        "bins_misc_ubuntu12.zip.3f92810725ee673827371a0470cd4f8c7ea8cfae",
        "026b984726c728bbf81ae3ba16623bcd96e2bf837a859c235acf0ee279d940fd"
    )
    public static let valveWin64 = valve(
        "bins_win64.zip.36f5d9202e79ab2aa3e3c5902e84bbd799d31fc0",
        "93f5b6bea0267fd85dc8cc823fdab5c5fb55d7f3a1deab0598acefef0e133bce"
    )
    /// A pristine, Valve-signed Steam.app, used to undo the add-on.
    public static let steamBundle = valve(
        "appdmg_osx.zip.984652b88a9737e3f4e77c656d9ffa67d5042c2c",
        "8bf4ce8b4bcbc50f642988c955559f605e7a877372116e7a2b3fd1355004bedb"
    )

    public static let valveFiles: [ValveFile] = [
        ValveFile(destination: "legacycompat/Steam.dll", package: "linux", pathInPackage: "legacycompat/Steam.dll",
                  sha256: "b2000e57123e99bbbe26aaec40cfaf09a4df93959c5148f0db571ed2e3401102"),
        ValveFile(destination: "legacycompat/SteamService.exe", package: "linux", pathInPackage: "legacycompat/SteamService.exe",
                  sha256: "a12c6c9ed617bf7c804227cb494666487c9d185daf61940af498980f6937387e"),
        ValveFile(destination: "legacycompat/iscriptevaluator.exe", package: "linux", pathInPackage: "legacycompat/iscriptevaluator.exe",
                  sha256: "bafaae73e3763522917d34681b77120c29bef7dd3801c34e8cc8d5e92a78eeeb"),
        ValveFile(destination: "legacycompat/steamclient.dll", package: "linux", pathInPackage: "legacycompat/steamclient.dll",
                  sha256: "e9e961c914a418b6a3c597822bdc920bdea62c842ff42de23dc306331da563f8"),
        ValveFile(destination: "legacycompat/steamclient64.dll", package: "linux", pathInPackage: "steamclient64.dll",
                  sha256: "caba4826aa3501039d095aee1843a6bfb270fb43a3ab4455b2d6733223579fee"),
        ValveFile(destination: "legacycompat/GameOverlayRenderer64.dll", package: "linux", pathInPackage: "GameOverlayRenderer64.dll",
                  sha256: "59057f983ae6f02b7eb2495bf65e0430129dd81dff8d9628c764bd1a07e23fee"),
        ValveFile(destination: "steamclient.dll", package: "linux", pathInPackage: "legacycompat/steamclient.dll",
                  sha256: "e9e961c914a418b6a3c597822bdc920bdea62c842ff42de23dc306331da563f8"),
        ValveFile(destination: "steamclient64.dll", package: "linux", pathInPackage: "steamclient64.dll",
                  sha256: "caba4826aa3501039d095aee1843a6bfb270fb43a3ab4455b2d6733223579fee"),
        ValveFile(destination: "tier0_s64.dll", package: "win64", pathInPackage: "tier0_s64.dll",
                  sha256: "30f7bb8d9b86006852493c26124ba253bd9e7ffd40a8b3c7254f86a9032c3be3"),
        ValveFile(destination: "vstdlib_s64.dll", package: "win64", pathInPackage: "vstdlib_s64.dll",
                  sha256: "99efb4c2ad47f90c803b5ee0bd6424916b28facb9fa2568845b1b1f58a36062a"),
    ]

    /// Valve's signing identity, checked before a restored Steam.app is trusted.
    public static let valveTeamID = "MXGJJ98X76"
    public static let steamBundleID = "com.valvesoftware.steam"

    /// Every pin, for sanity tests.
    public static let all: [Pin] = [engine, notProton, valveLinux, valveWin64, steamBundle]
}
