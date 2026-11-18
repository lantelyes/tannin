import SwiftUI
import TanninCore

/// One place in the setup window's row of covers: a wash of the cover's own colours, and over it the picture
/// once there is one. It loads nothing itself, so no cover can arrive alone.
struct SetupCover: View {
    let tint: SetupArt.Tint
    let picture: CGImage?
    /// How much of the picture shows, from 0 to 1. The same for all seven.
    let pictureOpacity: Double
    @Environment(\.colorScheme) private var colorScheme

    static let size = CGSize(width: 106, height: 159)
    private static let shape = RoundedRectangle(cornerRadius: 9)

    var body: some View {
        ZStack {
            tile
            if let picture {
                cover(picture)
                    // The picture, its edge and its shadow fade as one piece, so the shadow never shows through.
                    .compositingGroup()
                    .opacity(pictureOpacity)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    /// Softer in dark, where a full-strength colour would glow against the window.
    private var tile: some View {
        let isDark = colorScheme == .dark
        return Self.shape
            .fill(LinearGradient(stops: [
                .init(color: Color(rgb: tint.top), location: 0),
                .init(color: Color(rgb: tint.middle), location: 0.52),
                .init(color: Color(rgb: tint.bottom), location: 1),
            ], startPoint: .top, endPoint: .bottom))
            .overlay {
                Self.shape.strokeBorder(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 0.5)
            }
            .opacity(isDark ? 0.42 : 0.6)
    }

    private func cover(_ picture: CGImage) -> some View {
        Image(decorative: picture, scale: 1)
            .resizable()
            .scaledToFill()
            .frame(width: Self.size.width, height: Self.size.height)
            .clipShape(Self.shape)
            .overlay {
                Self.shape.strokeBorder(.black.opacity(0.25), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.2), radius: 9, y: 8)
    }
}

private extension Color {
    /// A colour written as 0xRRGGBB.
    init(rgb: UInt32) {
        self.init(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}
