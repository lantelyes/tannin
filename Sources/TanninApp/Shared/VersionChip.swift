import SwiftUI

/// A version or build number, in monospaced type on a quiet chip.
struct VersionChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.monospaced())
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Theme.chip, in: .rect(cornerRadius: 6))
    }
}
