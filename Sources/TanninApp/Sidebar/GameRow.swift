import SwiftUI
import TanninCore

struct GameRow: View {
    let game: LibraryGame

    var body: some View {
        HStack(spacing: 8) {
            Label {
                Text(game.name)
                    .lineLimit(1)
            } icon: {
                GameThumbnail(url: game.art.thumbnail)
            }
            if !game.isInstalled {
                Spacer(minLength: 0)
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Not installed")
            }
        }
    }
}
