import SwiftUI
import TanninCore

/// The same seven covers across the top of the setup window, for everyone. They do not change while setup goes:
/// the bar and the line under it say how far it is.
///
/// Until the pictures are on this Mac, each place holds a wash of its cover's colours. The pictures then come in
/// all seven together, once. Pictures that were here when the window opened are simply there.
struct SetupCoverBand: View {
    /// All seven, in order, or nil while any is still on its way.
    let pictures: [CGImage]?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var picturesAreShown: Bool

    init(pictures: [CGImage]?) {
        self.pictures = pictures
        _picturesAreShown = State(initialValue: pictures != nil)
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(SetupArt.covers.enumerated()), id: \.element.id) { index, cover in
                SetupCover(tint: cover.tint,
                           picture: pictures.flatMap { $0.indices.contains(index) ? $0[index] : nil },
                           pictureOpacity: picturesAreShown ? 1 : 0)
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
        // Decoration: the title says what the window is for.
        .accessibilityHidden(true)
        .onChange(of: pictures != nil) { _, arrived in
            if reduceMotion {
                picturesAreShown = arrived
            } else {
                withAnimation(.easeOut(duration: 0.35)) { picturesAreShown = arrived }
            }
        }
    }
}
