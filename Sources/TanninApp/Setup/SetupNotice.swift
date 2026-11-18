import SwiftUI

/// Something in the way of setup, said in the window: what it is, what to do about it, and at most one button.
struct SetupNotice<Actions: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            StatusSymbol.warning.image
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) { actions }
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: 560)
        .background(StatusSymbol.warning.color.opacity(0.14), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }
}

extension SetupNotice where Actions == EmptyView {
    init(title: String, detail: String) {
        self.init(title: title, detail: detail) { EmptyView() }
    }
}
