import SwiftUI

/// The small coloured tile in front of an engine or a renderer. Grey while the thing is not on this Mac.
struct ComponentTile: View {
    enum Kind {
        case engine, renderer

        var systemImage: String {
            switch self {
            case .engine: "cpu"
            case .renderer: "cube"
            }
        }

        var color: Color {
            switch self {
            case .engine: .indigo
            case .renderer: .teal
            }
        }
    }

    let kind: Kind
    var isOnThisMac = true
    var size = 26.0

    var body: some View {
        Image(systemName: kind.systemImage)
            .font(.system(size: size * 0.54, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(isOnThisMac ? AnyShapeStyle(kind.color.gradient) : AnyShapeStyle(.tertiary), in: .rect(cornerRadius: size * 0.27))
            .accessibilityHidden(true)
    }
}
