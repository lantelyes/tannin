import SwiftUI
import TanninCore

/// What games run on: the Wine engines and the renderers, as two lists whose rows work the same way.
struct RenderersView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.status != nil {
                Form {
                    if model.problem == .setupIncomplete {
                        SetupNoticeSection()
                    }
                    EnginesSection()
                    RenderersSection()
                }
                .formStyle(.grouped)
            } else {
                ProgressView("Checking this Mac…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Engines & Renderers")
    }
}

extension Int {
    /// "No games", "1 game", "3 games".
    var gamesPhrase: String {
        switch self {
        case 0: "No games"
        case 1: "1 game"
        default: "\(self) games"
        }
    }
}
