import SwiftUI

/// A state in a word with its mark, at the trailing edge of a row: "Installed", "In place", "Added".
struct StateLabel: View {
    let text: String
    let symbol: StatusSymbol

    init(_ text: String, _ symbol: StatusSymbol) {
        self.text = text
        self.symbol = symbol
    }

    var body: some View {
        HStack(spacing: 5) {
            symbol.image
            Text(text)
        }
        .accessibilityElement(children: .combine)
    }
}
