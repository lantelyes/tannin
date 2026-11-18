import SwiftUI

/// An entry of a pop-up button that has a second line under its name.
///
/// In a pop-up's menu only a button's label is drawn with a second line; two texts in a stack show the first
/// alone (seen on macOS 27, 2026-11-18). The button's own action is never used: choosing the entry sets the
/// pop-up's selection through the tag it is given.
struct PopUpEntry: View {
    let title: String
    let detail: String

    init(_ title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        Button {} label: {
            Text(title)
            Text(detail)
        }
    }
}
