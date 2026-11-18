import SwiftUI
import TanninCore

/// The game's Steam artwork across the top of its page, with the title over a darkened lower edge so it
/// reads on any picture. The picture itself continues under the toolbar and the floating sidebar.
struct GameHero: View {
    let game: LibraryGame
    @State private var image: CGImage?

    /// Height below the toolbar. With the toolbar's own height the picture is about 190 points tall.
    static let height: CGFloat = 138

    var body: some View {
        Color.clear
            .frame(height: Self.height)
            .background {
                artwork.ignoresSafeArea(edges: [.top, .leading])
            }
            .overlay(alignment: .bottomLeading) {
                Text(game.name)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 6, y: 1)
                    .lineLimit(2)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 14)
                    .accessibilityAddTraits(.isHeader)
            }
            .task(id: game.art.banner) {
                guard let url = game.art.banner else {
                    image = nil
                    return
                }
                image = await ArtworkCache.image(at: url, pixels: 2400)
            }
    }

    private var artwork: some View {
        // The plain fill takes exactly the space offered; the picture is laid over it and cropped to it.
        // (A fill-scaled image on its own reports a larger size and would spill past the header.)
        Rectangle()
            // Shown while the picture loads, and for the few games Steam has no banner for.
            .fill(LinearGradient(colors: [Color(white: 0.32), Color(white: 0.14)], startPoint: .top, endPoint: .bottom))
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                }
            }
            .overlay {
                LinearGradient(
                    stops: [.init(color: .clear, location: 0.4), .init(color: .black.opacity(0.62), location: 1)],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .clipped()
            .accessibilityHidden(true)
    }
}
