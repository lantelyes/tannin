import SwiftUI

/// One cover in the setup window's band, somewhere between grey and its own colours.
struct SetupCover: View {
    let url: URL?
    /// 0 is grey and dimmed, 1 is the cover as Steam shows it.
    let amount: Double
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .frame(width: 106, height: 159)
        .clipShape(.rect(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9).strokeBorder(.black.opacity(0.25), lineWidth: 0.5)
        }
        .saturation(amount)
        .opacity(0.42 + 0.58 * amount)
        .shadow(color: .black.opacity(0.2 * amount), radius: 9, y: 8)
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            image = await ArtworkCache.image(at: url, pixels: 480)
        }
    }
}
