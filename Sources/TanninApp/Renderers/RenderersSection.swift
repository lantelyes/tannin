import SwiftUI
import TanninCore

/// The three renderers, as a list. D3DMetal is one of them; it differs only in how it arrives, which is from
/// the user's own copy of Apple's Game Porting Toolkit. DXMT and DXVK come inside each Wine engine.
struct RenderersSection: View {
    @Environment(AppModel.self) private var model
    @State private var isConfirmingRemoval = false

    private var hasEngine: Bool { model.status?.engineInstalled == true }

    var body: some View {
        Section {
            d3dMetal
            included("DXMT \(LayerStore.dxmtVersion)", "Direct3D 10 and 11, 32-bit and 64-bit games. Included with Wine.", .dxmt)
            included("DXVK \(LayerStore.dxvkVersion)", "Direct3D 11 through Vulkan, 64-bit games only. Included with Wine.", .dxvk)
        } header: {
            Text("Renderers")
        } footer: {
            Text(model.d3dMetalIsAdded
                ? "Games use Automatic unless you choose a renderer on their page. Automatic picks D3DMetal for 64-bit games and DXMT for 32-bit games. Direct3D 9 games use WineD3D, Wine’s built-in renderer."
                : "Games use Automatic unless you choose a renderer on their page. Automatic picks DXMT, or D3DMetal for 64-bit games once you add it. Direct3D 9 games use WineD3D, Wine’s built-in renderer.")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog("Remove D3DMetal?", isPresented: $isConfirmingRemoval) {
            Button("Remove", role: .destructive) { Task { await model.removeD3DMetal() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(removalMessage)
        }
    }

    // MARK: D3DMetal

    private var d3dMetal: some View {
        LabeledContent {
            if model.d3dMetalIsAdded {
                StateLabel("Added", .ok)
                Menu("More", systemImage: "ellipsis") {
                    Button("Replace…") { model.showD3DMetalSheet() }
                    Button("Show in Finder") { model.showD3DMetalInFinder() }
                    Divider()
                    Button("Remove…") { isConfirmingRemoval = true }
                }
                .labelStyle(.iconOnly)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(model.isBusy)
            } else {
                Button("Add…") { model.showD3DMetalSheet() }
                    .disabled(model.isBusy)
            }
        } label: {
            Label {
                Text(model.status?.d3dMetalVersion.map { "D3DMetal \($0)" } ?? "D3DMetal")
                Text(model.d3dMetalIsAdded
                    ? "Direct3D 11 and 12, 64-bit games only. From Apple’s Game Porting Toolkit. \(count(.d3dMetal))"
                    : "Direct3D 11 and 12, 64-bit games only. Free from Apple. Direct3D 12 games need it.")
            } icon: {
                ComponentTile(kind: .renderer, isOnThisMac: model.d3dMetalIsAdded)
            }
        }
    }

    /// Names the games it affects, as the board draws it.
    private var removalMessage: String {
        let names = model.games(drawnBy: .d3dMetal).map(\.name)
        let first = names.isEmpty
            ? "No installed game uses it."
            : "\(ListFormatter.localizedString(byJoining: names)) will switch to DXMT."
        return first + " Games that need Direct3D 12 won’t start. Tannin’s copy moves to the Trash, and your disk image isn’t changed."
    }

    // MARK: DXMT and DXVK

    private func included(_ title: String, _ what: String, _ renderer: GraphicsLayer) -> some View {
        LabeledContent {
            if hasEngine {
                StateLabel("Included", .ok)
            } else {
                Text("With Wine").foregroundStyle(.secondary)
            }
        } label: {
            Label {
                Text(title)
                Text(hasEngine ? "\(what) \(count(renderer))" : what)
            } icon: {
                ComponentTile(kind: .renderer, isOnThisMac: hasEngine)
            }
        }
    }

    private func count(_ renderer: GraphicsLayer) -> String {
        model.games(drawnBy: renderer).count.gamesPhrase
    }
}
