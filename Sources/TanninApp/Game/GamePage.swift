import SwiftUI
import TanninCore

/// One game: its artwork, whether it can be played, and how it runs.
struct GamePage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let game: LibraryGame

    @State private var draft: SettingsDraft
    @State private var preset: GamePreset
    @State private var isConfirmingQuit = false
    @State private var isConfirmingRemoval = false
    @State private var isChoosingToolkit = false

    init(game: LibraryGame) {
        self.game = game
        _draft = State(initialValue: SettingsDraft(game.settings))
        // The real value is set as soon as the page knows whether Apple's toolkit is there.
        _preset = State(initialValue: .custom)
    }

    private var hasChanges: Bool { draft.settings != game.settings.normalized }

    /// A 32-bit or 64-bit game; unknown until it is installed.
    private var is32Bit: Bool? { game.isInstalled ? game.is32Bit : nil }
    private var toolkitAdded: Bool { model.status?.d3dMetalVersion != nil }

    /// The layer the game really gets: the chosen one, or what Automatic comes to. Nil when that is not known yet.
    private var effectiveLayer: GraphicsLayer? {
        draft.layer == .automatic ? GraphicsLayer.automaticChoice(is32Bit: is32Bit, toolkitAdded: toolkitAdded) : draft.layer
    }

    var body: some View {
        VStack(spacing: 0) {
            GameHero(game: game)
            header
            settings
        }
        .navigationTitle(game.name)
        .toolbar(removing: .title)
        // The artwork runs under the toolbar, so the toolbar draws nothing of its own behind its buttons.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar { toolbar }
        .onChange(of: preset) { applyPreset() }
        .onChange(of: draft) { matchPreset() }
        .onChange(of: draft.layer) {
            // Settings that belong to the layer just left would do nothing, so they are not carried over.
            let trimmed = SettingsDraft(draft.settings.keeping(onlyWhatAppliesTo: effectiveLayer))
            if trimmed != draft { draft = trimmed }
        }
        .onChange(of: effectiveLayer, initial: true) { matchPreset() }
        .onChange(of: game.launchOptions) {
            // Saved, or changed in Steam itself: show what Steam has now.
            draft = SettingsDraft(game.settings)
        }
        .fileImporter(isPresented: $isChoosingToolkit, allowedContentTypes: [.diskImage, .folder]) { result in
            if case let .success(url) = result {
                Task { await model.importToolkit(from: url) }
            }
        }
        .confirmationDialog("Quit Steam to save?", isPresented: $isConfirmingQuit) {
            Button("Quit Steam and Save") { save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Steam rewrites its settings when it quits, so it has to be closed first. Tannin reopens it afterwards.")
        }
        .confirmationDialog("Remove Steam Play from Steam?", isPresented: $isConfirmingRemoval) {
            Button("Remove Steam Play", role: .destructive) {
                Task { await model.removeSteamPlay() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(EngineView.removalMessage)
        }
    }

    // MARK: Under the artwork

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                GameStatusLine(game: game)
                Spacer(minLength: 12)
                Picker("Preset", selection: $preset) {
                    ForEach(GamePreset.offered(effective: effectiveLayer)) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .fixedSize()
                if hasChanges {
                    Button("Save Changes", action: requestSave)
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBusy)
                }
            }
            notices
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 2)
    }

    @ViewBuilder private var notices: some View {
        if game.isInstalled, let problem = model.problem {
            if problem == .steamUpdated {
                SteamMovedNotice { isConfirmingRemoval = true }
            } else {
                NoticeRow(symbol: problem.isWarning ? .warning : .info, text: problem.explanation) {
                    switch problem {
                    case .off:
                        Button("Add Steam Play…") { model.isShowingSteamPlaySheet = true }
                            .disabled(model.isBusy)
                    case .setupIncomplete:
                        Button("Continue Setup…") { openWindow(id: WindowID.setup) }
                    case .otherTool, .steamMissing, .steamUpdated:
                        EmptyView()
                    }
                }
            }
        }
    }

    // MARK: Settings

    private var settings: some View {
        Form {
            Section("Graphics") {
                layerPicker
                switch effectiveLayer {
                case .d3dMetal:
                    Toggle(isOn: $draft.rayTracing) {
                        Text("Ray Tracing")
                        Text("Looks better, costs frame rate. Off by default on M1 and M2.")
                    }
                    Toggle(isOn: $draft.metalFX) {
                        Text("MetalFX Upscaling")
                        Text("Lets the game's DLSS setting use Apple's upscaler.")
                    }
                case .dxmt:
                    Picker(selection: $draft.upscaling) {
                        ForEach(GameSettings.upscalingFactors, id: \.self) { factor in
                            Text(factor == 0 ? "Off" : "\(factor.formatted())×").tag(factor)
                        }
                    } label: {
                        Text("Upscaling")
                        Text("Enlarges the game's picture with MetalFX. Set a lower resolution in the game to gain speed.")
                    }
                case .dxvk:
                    Toggle(isOn: $draft.backgroundEffects) {
                        Text("Prepare Effects in the Background")
                        Text("Less stutter the first time an effect appears. It may show a moment late.")
                    }
                case .automatic, nil:
                    EmptyView()
                }
                Picker("Frame Cap", selection: $draft.frameCap) {
                    ForEach(SettingsDraft.frameCaps, id: \.self) { cap in
                        Text(cap == 0 ? "None" : "\(cap) fps").tag(cap)
                    }
                }
            }
            Section {
                if effectiveLayer == .d3dMetal {
                    Toggle(isOn: $draft.metal4) {
                        Text("Metal 4 Renderer")
                        Text("The default on macOS 27. Turn off to use Metal 3.")
                    }
                }
                Toggle("Performance Overlay", isOn: $draft.performanceHUD)
                LabeledContent("Launch Options") {
                    Text(launchOptionsPreview)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Advanced")
            } footer: {
                if !game.isInstalled {
                    Text("Settings you choose now are used once the game is installed.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Graphics layer

    /// The pop-up's entries: the layers, and without Apple's toolkit the way to add it.
    private enum LayerChoice: Hashable {
        case layer(GraphicsLayer)
        case addToolkit
    }

    private var layerPicker: some View {
        Picker(selection: layerChoice) {
            layerOption(.automatic, detail: automaticDetail)
            Divider()
            if toolkitAdded {
                layerOption(.d3dMetal, detail: is32Bit == true ? "64-bit games only" : GraphicsLayer.d3dMetal.summary)
                    .selectionDisabled(is32Bit == true)
            }
            layerOption(.dxmt, detail: GraphicsLayer.dxmt.summary)
            layerOption(.dxvk, detail: is32Bit == true ? "64-bit games only" : GraphicsLayer.dxvk.summary)
                .selectionDisabled(is32Bit == true)
            if !toolkitAdded {
                Divider()
                VStack {
                    Text("Add D3DMetal…")
                    Text("From Apple's Game Porting Toolkit")
                }
                .tag(LayerChoice.addToolkit)
            }
        } label: {
            Text("Graphics Layer")
            if let layerCaption {
                Text(layerCaption)
            }
        }
        .disabled(model.isBusy)
    }

    private func layerOption(_ layer: GraphicsLayer, detail: String) -> some View {
        VStack {
            Text(layer.title)
            Text(detail)
        }
        .tag(LayerChoice.layer(layer))
    }

    /// Choosing "Add D3DMetal…" opens the file panel and leaves the layer as it was.
    private var layerChoice: Binding<LayerChoice> {
        Binding {
            .layer(draft.layer)
        } set: { choice in
            switch choice {
            case let .layer(layer): draft.layer = layer
            case .addToolkit: isChoosingToolkit = true
            }
        }
    }

    /// What Automatic comes to, in the pop-up.
    private var automaticDetail: String {
        switch GraphicsLayer.automaticChoice(is32Bit: is32Bit, toolkitAdded: toolkitAdded) {
        case let layer?: "\(layer.title) for this game"
        case nil: "Tannin picks when the game is installed"
        }
    }

    /// Under the row: what Automatic uses for this game, and what the game ran on last time when its log says.
    private var layerCaption: String? {
        let ran = game.isInstalled ? model.layerUsage[game.appID] : nil
        let ranSentence = ran.map { "It ran on \($0.title) last time." }
        guard draft.layer == .automatic else { return ranSentence }
        if ran == .wineOwn {
            return "It ran on Wine's own layer last time, which is what Direct3D 9 games get."
        }
        let pick: String
        switch (toolkitAdded, is32Bit) {
        case (true, nil): pick = "Tannin picks when the game is installed."
        case (true, false?): pick = "D3DMetal for this 64-bit game."
        case (_, true?): pick = "DXMT for this 32-bit game."
        case (false, _): pick = "DXMT for this game. Direct3D 12 games need Apple's toolkit."
        }
        return [pick, ranSentence].compactMap(\.self).joined(separator: " ")
    }

    private var launchOptionsPreview: String {
        let options = draft.settings.launchOptions(merging: game.launchOptions)
        return options.isEmpty ? "None" : options
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        // With no title in the toolbar, this keeps the buttons at the trailing edge.
        ToolbarSpacer(.flexible)
        ToolbarItem(placement: .primaryAction) {
            if game.isInstalled {
                Button("Play", systemImage: "play.fill") { model.play(game) }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.glassProminent)
                    .disabled(!model.canPlay(game))
                    .help(model.canPlay(game) ? "Ask Steam to start this game" : "This game can't be started right now")
            } else {
                Button("Install in Steam", systemImage: "arrow.down.circle") { model.install(game) }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.glassProminent)
                    .disabled(model.problem != nil)
                    .help("Open Steam's install window for this game")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu("More", systemImage: "ellipsis") {
                Button("Show in Steam") { model.showInSteam(game) }
                if let folder = game.installFolder {
                    Button("Show Game Files in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([folder])
                    }
                }
                Divider()
                Button("Copy Launch Options") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(launchOptionsPreview == "None" ? "" : launchOptionsPreview, forType: .string)
                }
            }
        }
    }

    // MARK: Actions

    private func applyPreset() {
        guard let settings = preset.settings(layer: draft.layer, effective: effectiveLayer) else { return }
        let target = SettingsDraft(settings)
        if target != draft { draft = target }
    }

    private func matchPreset() {
        let matching = GamePreset(matching: draft.settings, effective: effectiveLayer)
        if preset != matching { preset = matching }
    }

    private func requestSave() {
        if model.status?.steamRunning == true {
            isConfirmingQuit = true
        } else {
            save()
        }
    }

    private func save() {
        let settings = draft.settings
        Task { await model.save(settings, appID: game.appID) }
    }
}
