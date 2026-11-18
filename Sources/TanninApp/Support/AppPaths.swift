import Foundation
import TanninCore

extension Paths {
    /// Where the app reads and writes: this Mac's own home folder and Steam.
    ///
    /// Development aid: TANNIN_HOME and TANNIN_STEAM_APP point the app at another home folder and another
    /// Steam.app, so setup can be run from nothing without disturbing a working install. It does not make
    /// Add Steam Play safe to press there: that step still quits the real Steam.
    static let app: Paths = {
        let environment = ProcessInfo.processInfo.environment
        guard let home = environment["TANNIN_HOME"], !home.isEmpty else { return .live }
        let steam = environment["TANNIN_STEAM_APP"].map { URL(fileURLWithPath: $0) } ?? Paths.live.steamApp
        return Paths(home: URL(fileURLWithPath: home), steamApp: steam)
    }()
}
