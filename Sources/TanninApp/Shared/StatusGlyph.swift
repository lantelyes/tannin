import SwiftUI

struct StatusGlyph: View {
    let kind: StatusKind
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: size))
            .foregroundStyle(kind.color)
            .accessibilityLabel(kind.word)
    }
}
