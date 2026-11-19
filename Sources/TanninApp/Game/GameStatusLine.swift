import SwiftUI
import TanninCore

/// "Ready to play · Windows game, 4.3 GB": the game's state in a few words, with a mark that matches.
struct GameStatusLine: View {
    @Environment(AppModel.self) private var model
    let game: LibraryGame

    var body: some View {
        HStack(spacing: 6) {
            symbol.image
            Text(state).fontWeight(.medium)
            Text("· \(facts)")
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private var symbol: StatusSymbol {
        switch game.install {
        case .notInstalled, .installing: return .download
        case .installed:
            guard model.status != nil else { return .pending }
            guard let problem = model.problem else { return .ok }
            return problem.isWarning ? .warning : .pending
        }
    }

    private var state: String {
        switch game.install {
        case .notInstalled: return "Not installed"
        case .installing: return "Installing in Steam"
        case .installed:
            guard model.status != nil else { return "Checking" }
            return model.problem == nil ? "Ready to play" : "Can’t start right now"
        }
    }

    private var facts: String {
        var parts = ["Windows game"]
        if let size = game.sizeOnDisk, size > 0 {
            parts.append(size.formatted(.byteCount(style: .file)))
        }
        return parts.joined(separator: ", ")
    }
}
