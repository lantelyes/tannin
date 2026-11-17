import SwiftUI

/// A state shown to the user. Each has its own symbol shape and word, so it never depends on colour alone.
enum StatusKind {
    case ok, attention, broken, off, pending

    var symbol: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .broken: "xmark.octagon.fill"
        case .off: "minus.circle.fill"
        case .pending: "circle"
        }
    }

    var color: Color {
        switch self {
        case .ok: Theme.ok
        case .attention: Theme.attention
        case .broken: Theme.broken
        case .off, .pending: Theme.secondary
        }
    }

    var word: String {
        switch self {
        case .ok: "Ready"
        case .attention: "Needs attention"
        case .broken: "Not working"
        case .off: "Off"
        case .pending: "Not set up"
        }
    }
}
