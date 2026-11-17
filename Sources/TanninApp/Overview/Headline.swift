import TanninCore

/// The one sentence at the top of Overview: what state things are in and, if needed, what to do.
struct Headline {
    let kind: StatusKind
    let title: String
    let detail: String
    /// Label of the single action offered, if any.
    var action: String?

    init(_ status: TanninStatus) {
        switch status.headline {
        case .ready:
            self.init(kind: .ok, title: "Steam Play is ready.",
                      detail: "Windows games install and play from your Steam library.")
        case .steamPlayOff:
            self.init(kind: .off, title: "Steam Play is off.",
                      detail: "Add it to Steam to install and play Windows games.", action: "Add Steam Play")
        case .steamUpdatedPastAddon:
            self.init(kind: .attention, title: "Steam is newer than Tannin.",
                      detail: "Steam Play stays off until Tannin knows this Steam build. Mac games still work.")
        case let .foreignTool(value):
            self.init(kind: .attention, title: "Another tool is loaded into Steam.",
                      detail: "Tannin will not replace it. Remove the other tool first. (\(value))")
        case let .setupIncomplete(missing):
            self.init(kind: .attention, title: "Setup isn't finished.", detail: missing.joined(separator: " "))
        case .steamMissing:
            self.init(kind: .broken, title: "Steam isn't installed.",
                      detail: "Install Steam from store.steampowered.com, then open Tannin again.")
        }
    }

    private init(kind: StatusKind, title: String, detail: String, action: String? = nil) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.action = action
    }
}
