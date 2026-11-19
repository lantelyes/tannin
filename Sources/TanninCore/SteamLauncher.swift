import Foundation

public enum SteamLauncherError: Error, CustomStringConvertible {
    case badAppID(String)

    public var description: String {
        switch self {
        case let .badAppID(value): return "“\(value)” isn’t a Steam app ID."
        }
    }
}

/// Asks Steam to do things. Tannin never starts a game itself: Steam does, so the game runs exactly as it would
/// from Steam's own Play button.
public struct SteamLauncher: Sendable {
    public let paths: Paths

    public init(paths: Paths = .live) { self.paths = paths }

    public enum Request: Sendable, Equatable {
        case play(String)
        case install(String)
        case showInLibrary(String)

        var appID: String {
            switch self {
            case let .play(id), let .install(id), let .showInLibrary(id): id
            }
        }
    }

    /// The address Steam understands for a request. App IDs are digits only, so nothing else can end up in it.
    static func address(for request: Request) throws -> String {
        let appID = request.appID
        guard !appID.isEmpty, appID.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw SteamLauncherError.badAppID(appID) }
        return switch request {
        case .play: "steam://rungameid/\(appID)"
        case .install: "steam://install/\(appID)"
        case .showInLibrary: "steam://nav/games/details/\(appID)"
        }
    }

    public func send(_ request: Request) throws {
        // Named explicitly so the request always goes to the Mac Steam client, whatever else handles steam:// links.
        try Shell.check("/usr/bin/open", ["-a", paths.steamApp.path, try Self.address(for: request)])
    }

    public func openSteam() throws {
        try Shell.check("/usr/bin/open", ["-a", paths.steamApp.path])
    }
}
