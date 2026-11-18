import SwiftUI

/// The small coloured mark that says how something is doing. Each state has its own shape as well as its own
/// colour, so it reads without colour.
enum StatusSymbol {
    case ok, warning, info, pending, download

    var systemImage: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        case .pending: "circle"
        case .download: "arrow.down.circle"
        }
    }

    var color: Color {
        switch self {
        case .ok: .green
        case .warning: .orange
        case .info: .blue
        case .pending, .download: .secondary
        }
    }

    var image: some View {
        Image(systemName: systemImage)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}
