import SwiftUI
import TanninCore

/// "Runs On": the two things a game runs on, side by side. Each pop-up lists everything Tannin can use for
/// the game; what is not on this Mac yet says so, and choosing it leads to getting it.
struct GameRunsOn: View {
    @Environment(AppModel.self) private var model
    let game: LibraryGame
    @Binding var draft: SettingsDraft
    /// Asks to move the game to an installed Wine version, or with nil back to the default. The page confirms
    /// it, because Steam has to quit and a copy is made first.
    let requestMove: (EngineSpec?) -> Void

    /// The Wine version picked that is not installed, while the question about fetching it is up.
    @State private var fetching: EngineSpec?
    @State private var isConfirmingFetch = false
    /// True from choosing D3DMetal while it is not on the Mac until the sheet that adds it has closed.
    @State private var wantsD3DMetal = false

    private var is32Bit: Bool? { game.isInstalled ? game.is32Bit : nil }
    private var d3dMetalIsAdded: Bool { model.d3dMetalIsAdded }

    var body: some View {
        Section("Runs On") {
            wineVersionRow
                .confirmationDialog(fetching.map { "Install \($0.title)?" } ?? "", isPresented: $isConfirmingFetch, presenting: fetching) { spec in
                    Button("Install") { Task { await model.fetchEngine(spec, for: game.appID) } }
                    Button("Cancel", role: .cancel) {}
                } message: { spec in
                    Text("\(spec.downloadSize) to download. Steam stays open while it downloads. When it is here, Tannin asks before it moves \(game.name) to it.")
                }
            rendererRow
                .onChange(of: d3dMetalIsAdded) { _, added in
                    // Added from this game's pop-up: the game gets what was picked, and it waits for Save Changes.
                    if added, wantsD3DMetal { draft.layer = .d3dMetal }
                }
                .onChange(of: model.isShowingD3DMetalSheet) { _, isShown in
                    if !isShown { wantsD3DMetal = false }
                }
        }
    }

    // MARK: Wine version

    /// The pop-up's entries: follow the default, or one engine.
    private enum WineChoice: Hashable {
        case followDefault
        case pinned(EngineSpec)

        var spec: EngineSpec? {
            if case let .pinned(spec) = self { return spec }
            return nil
        }
    }

    private var defaultEngine: EngineSpec { model.engines.first(where: \.isDefault)?.spec ?? .newest }
    private var engine: GameEngine { model.gameEngines[game.appID] ?? GameEngine(pin: nil, runsOn: defaultEngine) }

    private func isInstalled(_ spec: EngineSpec) -> Bool { model.engines.contains { $0.spec == spec && $0.isInstalled } }

    /// The download this row is waiting for: a version fetched from here, or the one the game is set to.
    private var download: EngineProgress? {
        guard let progress = model.engineProgress else { return nil }
        let awaited = model.wantedEngines[game.appID] ?? (engine.pinIsInstalled ? nil : engine.pin)
        return progress.spec == awaited ? progress : nil
    }

    @ViewBuilder private var wineVersionRow: some View {
        if !game.isInstalled {
            LabeledContent {
                Text("Default (\(defaultEngine.wine))")
            } label: {
                Text("Wine Version")
                Text("Can be chosen once the game is installed.")
            }
        } else if let download {
            LabeledContent {
                if download.isPaused {
                    Button("Resume") { Task { await model.installEngine(download.spec) } }
                        .disabled(model.isBusy)
                } else {
                    Button("Pause") { model.pauseDownloads() }
                        .disabled(download.download?.isVerifying == true)
                }
            } label: {
                Text("Wine Version")
                Text(download.caption(working: "Downloading \(download.spec.title)"))
                if let fraction = download.fraction {
                    ProgressView(value: fraction)
                        .accessibilityLabel("\(download.spec.title) download")
                }
            }
        } else if let pin = engine.pin, !engine.pinIsInstalled {
            LabeledContent {
                Button("Install") { Task { await model.installEngine(pin) } }
                    .disabled(model.isBusy)
                winePicker
                    .labelsHidden()
                    .fixedSize()
            } label: {
                Label {
                    Text("Wine Version")
                    Text("\(pin.title) is not installed. This game uses \(engine.runsOn.wine) until it is.")
                } icon: {
                    StatusSymbol.warning.image
                }
            }
        } else {
            winePicker
        }
    }

    private var winePicker: some View {
        Picker(selection: wineChoice) {
            Text("Default (\(defaultEngine.wine))").tag(WineChoice.followDefault)
            Divider()
            ForEach(model.engines) { row in
                if row.isInstalled {
                    Text(row.spec.title).tag(WineChoice.pinned(row.spec))
                } else {
                    PopUpEntry(row.spec.title, detail: "\(row.spec.downloadSize) to download")
                        .tag(WineChoice.pinned(row.spec))
                    // Another engine is built around what setup installs, so there has to be one first.
                    .selectionDisabled(model.status?.engineInstalled != true)
                }
            }
        } label: {
            Text("Wine Version")
            if engine.pin != nil {
                Text("Set for this game only.")
            }
        }
        .disabled(model.isBusy)
    }

    /// Choosing a version does not apply it. An installed one is confirmed by the page, because Steam has to
    /// quit and a copy is made; one that is not installed is fetched first, and the page asks afterwards.
    private var wineChoice: Binding<WineChoice> {
        Binding {
            engine.pin.map(WineChoice.pinned) ?? .followDefault
        } set: { choice in
            guard choice.spec != engine.pin else { return }
            if let spec = choice.spec, !isInstalled(spec) {
                fetching = spec
                isConfirmingFetch = true
            } else {
                requestMove(choice.spec)
            }
        }
    }

    // MARK: Renderer

    /// The pop-up's entries: the renderers, and without D3DMetal on the Mac the way to add it.
    private enum RendererChoice: Hashable {
        case renderer(GraphicsLayer)
        case addD3DMetal
    }

    /// D3DMetal is what the game is set to, and it is not on this Mac.
    private var d3dMetalIsMissing: Bool { draft.layer == .d3dMetal && !d3dMetalIsAdded }

    @ViewBuilder private var rendererRow: some View {
        if d3dMetalIsMissing {
            LabeledContent {
                Button("Add…") { addD3DMetal() }
                    .disabled(model.isBusy)
                rendererPicker
                    .labelsHidden()
                    .fixedSize()
            } label: {
                Label {
                    Text("Renderer")
                    Text("D3DMetal is not on this Mac, so this game uses DXMT. Add it, or choose another renderer.")
                } icon: {
                    StatusSymbol.warning.image
                }
            }
        } else {
            rendererPicker
        }
    }

    private var rendererPicker: some View {
        Picker(selection: rendererChoice) {
            option(.automatic, detail: automaticDetail)
            Divider()
            if d3dMetalIsAdded {
                option(.d3dMetal, detail: is32Bit == true ? "64-bit games only" : GraphicsLayer.d3dMetal.summary)
                    .selectionDisabled(is32Bit == true)
            }
            option(.dxmt, detail: GraphicsLayer.dxmt.summary)
            option(.dxvk, detail: is32Bit == true ? "64-bit games only" : GraphicsLayer.dxvk.summary)
                .selectionDisabled(is32Bit == true)
            if !d3dMetalIsAdded {
                // What is not on the Mac comes last, and says so.
                if is32Bit == true {
                    option(.d3dMetal, detail: "64-bit games only")
                        .selectionDisabled()
                } else if d3dMetalIsMissing {
                    option(.d3dMetal, detail: "Apple's. Not on this Mac yet")
                } else {
                    PopUpEntry("D3DMetal", detail: "Apple's. Not on this Mac yet")
                        .badge(Text("Add…"))
                        .tag(RendererChoice.addD3DMetal)
                }
            }
        } label: {
            Text("Renderer")
            if let caption {
                Text(caption)
            }
        }
        .disabled(model.isBusy)
    }

    private func option(_ renderer: GraphicsLayer, detail: String) -> some View {
        PopUpEntry(renderer.title, detail: detail)
            .tag(RendererChoice.renderer(renderer))
    }

    /// Choosing D3DMetal while it is not on the Mac opens the sheet that adds it and leaves the renderer as it
    /// was; it becomes D3DMetal once the sheet has added it.
    private var rendererChoice: Binding<RendererChoice> {
        Binding {
            .renderer(draft.layer)
        } set: { choice in
            switch choice {
            case let .renderer(renderer): draft.layer = renderer
            case .addD3DMetal: addD3DMetal()
            }
        }
    }

    private func addD3DMetal() {
        wantsD3DMetal = true
        model.showD3DMetalSheet()
    }

    /// What Automatic comes to, in the pop-up.
    private var automaticDetail: String {
        switch GraphicsLayer.automaticChoice(is32Bit: is32Bit, toolkitAdded: d3dMetalIsAdded) {
        case let renderer?: "\(renderer.title) for this game"
        case nil: "Tannin picks when the game is installed"
        }
    }

    /// Under the row: what Automatic uses for this game, and what the game ran on last time when its log says.
    private var caption: String? {
        let ran = game.isInstalled ? model.layerUsage[game.appID] : nil
        let ranSentence = ran.map { "It ran on \($0.title) last time." }
        guard draft.layer == .automatic else { return ranSentence }
        if ran == .wineOwn {
            return "It ran on Wine's own drawing last time, which is what Direct3D 9 games get."
        }
        let pick: String
        switch (d3dMetalIsAdded, is32Bit) {
        case (true, nil): pick = "Tannin picks when the game is installed."
        case (true, false?): pick = "D3DMetal for this 64-bit game."
        case (_, true?): pick = "DXMT for this 32-bit game."
        case (false, false?): pick = "DXMT for this 64-bit game. Direct3D 12 games need D3DMetal."
        case (false, nil): pick = "DXMT for this game. Direct3D 12 games need D3DMetal."
        }
        return [pick, ranSentence].compactMap(\.self).joined(separator: " ")
    }
}
