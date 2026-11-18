import SwiftUI

/// The row at the top of a page while setup has not been finished, with the way back into it.
struct SetupNoticeSection: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Section {
            LabeledContent {
                Button("Continue Setup…") { openWindow(id: WindowID.setup) }
                    .buttonStyle(.borderedProminent)
            } label: {
                Label {
                    Text("Setup isn't finished")
                    Text("Some of what Tannin needs is not on this Mac yet.")
                } icon: {
                    StatusSymbol.pending.image
                }
            }
        }
    }
}
