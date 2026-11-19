import TanninCore

/// Why Windows games cannot be started right now, in the app's own terms.
enum SteamPlayProblem: Equatable {
    case steamMissing
    case setupIncomplete
    case off
    case otherTool
    /// Steam moved to a build the Steam add-on does not know, so the add-on installed nothing.
    case steamUpdated

    init?(_ status: TanninStatus) {
        switch status.headline {
        case .ready: return nil
        case .steamMissing: self = .steamMissing
        case .setupIncomplete: self = .setupIncomplete
        case .steamPlayOff: self = .off
        case .foreignTool: self = .otherTool
        case .steamUpdatedPastAddon: self = .steamUpdated
        }
    }

    /// The short line shown under the sidebar and in the menu bar.
    var title: String {
        switch self {
        case .steamMissing: "Steam isn’t installed"
        case .setupIncomplete: "Setup isn’t finished"
        case .off, .steamUpdated: "Steam Play is off"
        case .otherTool: "Another tool has modified Steam"
        }
    }

    var detail: String {
        switch self {
        case .steamMissing: "Install Steam, then open Tannin again"
        case .setupIncomplete: "Open Steam Play to continue"
        case .off: "Add it in Steam Play"
        case .steamUpdated: "Steam was updated"
        case .otherTool: "Remove the other tool first"
        }
    }

    /// The sentence shown on a game's page.
    var explanation: String {
        switch self {
        case .steamMissing: "Steam isn’t in the Applications folder."
        case .setupIncomplete: "Setup isn’t finished."
        case .off: "Steam Play hasn’t been added to Steam."
        case .otherTool: "Another tool has modified Steam. Tannin won’t replace it."
        case .steamUpdated: "Steam updated to a build Tannin doesn’t support yet, so Steam Play is off."
        }
    }

    /// Whether this deserves a warning mark, as opposed to simply not being set up yet.
    var isWarning: Bool {
        switch self {
        case .steamUpdated, .otherTool, .steamMissing: true
        case .off, .setupIncomplete: false
        }
    }
}
