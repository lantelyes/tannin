import SwiftUI
import TanninCore

/// "After the Update": what an earlier Tannin installed that this one would bring up to date, one row each.
/// Nothing is downloaded or changed until a row's button is pressed.
struct UpkeepSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Section("Finish Updating") {
            switch model.upkeepProgress {
            case let .working(item):
                LabeledContent {
                    EmptyView()
                } label: {
                    Label {
                        Text(workingTitle(item))
                        Text("This takes a few seconds.")
                    } icon: {
                        ProgressView().controlSize(.small)
                    }
                }
            case .finished:
                LabeledContent {
                    Button("Done") { model.dismissUpkeepResult() }
                } label: {
                    Label {
                        Text("Everything is up to date")
                        if let status = model.status {
                            Text("\(status.stackSummary), Steam bridge \(status.bridgeVersion).")
                        }
                    } icon: {
                        StatusSymbol.ok.image
                    }
                }
            case let .failed(item, message):
                LabeledContent {
                    Button("Show Logs") { model.selection = .logs }
                    Button("Try Again") { Task { await model.runUpkeep(item) } }
                        .disabled(model.isBusy)
                } label: {
                    Label {
                        Text("The update didn’t finish")
                        Text("Nothing changed, and Steam Play still works. \(message)")
                    } icon: {
                        StatusSymbol.warning.image
                    }
                }
            case nil:
                ForEach(model.upkeep) { item in
                    LabeledContent {
                        Button(item.action) { Task { await model.runUpkeep(item) } }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isBusy)
                    } label: {
                        Label {
                            Text(item.title)
                            Text(item.detail)
                        } icon: {
                            StatusSymbol.download.image
                        }
                    }
                }
            }
        }
    }

    private func workingTitle(_ item: Upkeep.Item) -> String {
        switch item {
        case .graphicsLayers: "Adding the renderers…"
        }
    }
}
