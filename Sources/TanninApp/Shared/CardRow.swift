import SwiftUI

/// One row on a card: optional status glyph, a title with an optional plain-language caption, and trailing content.
struct CardRow<Trailing: View>: View {
    let title: String
    var caption: String?
    var status: StatusKind?
    var showsDivider = true
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let status {
                StatusGlyph(kind: status)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Theme.text)
                if let caption {
                    Text(caption)
                        .font(.callout)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: 40)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle().fill(Theme.line).frame(height: 1)
            }
        }
    }
}

extension CardRow where Trailing == EmptyView {
    init(title: String, caption: String? = nil, status: StatusKind? = nil, showsDivider: Bool = true) {
        self.init(title: title, caption: caption, status: status, showsDivider: showsDivider) { EmptyView() }
    }
}
