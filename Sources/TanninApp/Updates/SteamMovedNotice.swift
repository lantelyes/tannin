import SwiftUI

/// The notice on a game's page when Steam has moved to a build this Tannin does not support.
/// It reports the quiet check for a Tannin update, since a newer Tannin is the only thing that helps.
struct SteamMovedNotice: View {
    @Environment(AppModel.self) private var model
    @Environment(Updates.self) private var updates
    /// Asks to take Steam Play out of Steam; offered only by a copy that cannot update itself.
    let remove: () -> Void

    private static let off = "Steam updated itself, so Steam Play is off."

    var body: some View {
        NoticeRow(symbol: .warning, text: text) {
            if !updates.canUpdate {
                Button("Show Logs") { model.selection = .logs }
                Button("Remove Steam Play…", action: remove)
                    .disabled(model.isBusy)
            } else {
                switch updates.status {
                case .checking:
                    ProgressView().controlSize(.small)
                case .available:
                    Button("Update Tannin…") { updates.checkNow() }
                        .buttonStyle(.borderedProminent)
                case .failed:
                    Button("Try Again") { updates.checkQuietly() }
                        .disabled(!updates.canCheck)
                case .unknown, .upToDate:
                    Button("Show Logs") { model.selection = .logs }
                }
            }
        }
    }

    private var text: String {
        guard updates.canUpdate else { return SteamPlayProblem.steamUpdated.explanation }
        switch updates.status {
        case .unknown:
            return SteamPlayProblem.steamUpdated.explanation
        case .checking:
            return "\(Self.off) Checking for a Tannin update…"
        case let .available(version):
            // The feed says a newer Tannin exists, not which Steam builds it supports, so this claims no more.
            return "\(Self.off) Tannin \(version) is available."
        case .upToDate:
            let daily = updates.checksAutomatically ? " Tannin checks again every day." : ""
            return "\(Self.off) No Tannin update supports the new Steam yet.\(daily)"
        case .failed:
            return "\(Self.off) Tannin couldn't check for an update."
        }
    }
}
