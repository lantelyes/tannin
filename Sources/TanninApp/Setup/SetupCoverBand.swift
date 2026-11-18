import SwiftUI
import TanninCore

/// The person's own covers across the top of the setup window. They are grey while Steam cannot install them
/// and come into colour from the left as setup goes; the cover that colour has reached is part-way there.
struct SetupCoverBand: View {
    let games: [LibraryGame]
    /// How many covers are in colour, counted from the left. 2.5 is two covers and half of the third.
    let lit: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            ForEach(games.enumerated(), id: \.element.id) { index, game in
                SetupCover(url: game.art.cover, amount: min(1, max(0, lit - Double(index))))
            }
        }
        // The covers start just under the title bar, clear of the window's buttons.
        .padding(.top, 4)
        // Seven covers are wider than the window, so the two at the edges are cropped by it.
        .frame(width: 720, height: 194, alignment: .top)
        .clipped()
        // The covers fade out towards the title, whatever the window is drawn on.
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.5), .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: lit)
        // Decoration: the title and the progress line say the same in words.
        .accessibilityHidden(true)
    }
}
