import SwiftUI

/// A tinted note above a page's settings: something the user should know, with at most two things to do about it.
struct NoticeRow<Actions: View>: View {
    let symbol: StatusSymbol
    let text: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            symbol.image
            // No fixed vertical size here: when the window works out its smallest size it offers almost no width,
            // and text that insists on its full height at that width makes the window grow to the screen.
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            actions
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(symbol.color.opacity(0.14), in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }
}

extension NoticeRow where Actions == EmptyView {
    init(symbol: StatusSymbol, text: String) {
        self.init(symbol: symbol, text: text) { EmptyView() }
    }
}
