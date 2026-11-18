import SwiftUI
import TanninCore

/// The row above the sidebar's status lines, shown on every page while something Tannin installed is behind
/// the app. Clicking it opens the Engine page, where each thing has its own row and button.
struct UpkeepSidebarRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.upkeep.isEmpty {
            Button {
                model.selection = .engine
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Finish Updating")
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 9)
                .frame(height: 42)
                .background(.quaternary, in: .rect(cornerRadius: 8))
                .contentShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
            .help("Open the Engine page to finish updating")
        }
    }

    private var summary: String {
        model.upkeep.map { item in
            switch item {
            case .graphicsLayers: "Graphics layers"
            }
        }.joined(separator: ", ")
    }
}
