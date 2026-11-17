import SwiftUI

/// Says what Tannin is doing while a long action runs.
struct ActivityBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.card, in: .capsule)
        .overlay { Capsule().strokeBorder(Theme.line) }
        .padding(.bottom, 16)
        .accessibilityElement(children: .combine)
    }
}
