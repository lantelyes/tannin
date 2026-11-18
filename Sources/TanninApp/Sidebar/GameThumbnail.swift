import SwiftUI

/// A game's cover, cropped to a small rounded square for the sidebar.
struct GameThumbnail: View {
    let url: URL?
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(.rect(cornerRadius: 5))
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            image = await ArtworkCache.image(at: url, pixels: 96)
        }
    }
}
