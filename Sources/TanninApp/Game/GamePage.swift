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
    /// The move the user asked for and has not confirmed yet.
    @State private var pendingMove: PendingMove?
    @State private var isConfirmingMove = false
    @State private var isConfirmingRestore = false
    /// The fixed window chosen on the page, which may not be saved yet.
    @State private var draftWindow: FixedWindow.Size?

    init(game: LibraryGame) {
        self.game = game
        _draft = State(initialValue: SettingsDraft(game.settings))
        // The real value is set as soon as the page knows whether D3DMetal is there.
        _preset = State(initialValue: .custom)
    }

    private var hasChanges: Bool { draft.settings != game.settings.normalized || draftWindow != savedWindow }

    private var savedWindow: FixedWindow.Size? { model.fixedWindows[game.appID] }
    private var hasEnvironment: Bool { model.gamesWithEnvironment.contains(game.appID) }
    private var isRunning: Bool { model.runningGames.contains(game.appID) }

    /// A game's move to a Wine version, or with no version back to the default.
    private struct PendingMove {
        var spec: EngineSpec?
    }

    /// The renderer whose settings the page shows: the chosen one, or what Automatic comes to. Nil when that
    /// is not known yet, and for a Direct3D 9 game, which Wine draws itself.
    private var effectiveLayer: GraphicsLayer? {
        GraphicsLayer.inEffect(chosen: draft.layer, is32Bit: game.isInstalled ? game.is32Bit : nil, toolkitAdded: model.d3dMetalIsAdded,
                               lastRan: game.isInstalled ? model.layerUsage[game.appID] : nil)
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
            // Settings that belong to the renderer just left would do nothing, so they are not carried over.
            let trimmed = SettingsDraft(draft.settings.keeping(onlyWhatAppliesTo: effectiveLayer))
            if trimmed != draft { draft = trimmed }
        }
        .onChange(of: effectiveLayer, initial: true) { matchPreset() }
        .onChange(of: savedWindow, initial: true) { draftWindow = savedWindow }
        .onChange(of: game.launchOptions) {
            // Saved, or changed in Steam itself: show what Steam has now.
            draft = SettingsDraft(game.settings)
        }
        .confirmationDialog(moveTitle, isPresented: $isConfirmingMove, presenting: pendingMove) { move in
            Button(model.status?.steamRunning == true ? "Quit Steam and Move" : "Move") {
                Task { await model.moveGame(game.appID, to: move.spec) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Steam quits and reopens. Tannin first keeps a copy of this game's Windows environment, which holds its settings and may hold its saves, so you can put it back.")
        }
        .confirmationDialog(restoreTitle, isPresented: $isConfirmingRestore) {
            Button(model.status?.steamRunning == true ? "Quit Steam and Restore" : "Restore") {
                Task { await model.restoreGame(game.appID) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(restoreMessage)
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
            Text(SteamPlayView.removalMessage)
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

    /// The Wine version fetched from this page, once it is installed and the game is not on it yet.
    private var arrivedEngine: EngineSpec? {
        guard let wanted = model.wantedEngines[game.appID], model.gameEngines[game.appID]?.runsOn != wanted,
              model.engines.contains(where: { $0.spec == wanted && $0.isInstalled }) else { return nil }
        return wanted
    }

    private func requestMove(to spec: EngineSpec?) {
        pendingMove = PendingMove(spec: spec)
        isConfirmingMove = true
    }

    @ViewBuilder private var notices: some View {
        if let arrivedEngine {
            NoticeRow(symbol: .info, text: "\(arrivedEngine.title) is here. Move this game to it?") {
                Button("Not Now") { model.forgetWantedEngine(for: game.appID) }
                Button("Move…") { requestMove(to: arrivedEngine) }
                    .disabled(model.isBusy)
            }
        }
        if model.recentlyMoved.contains(game.appID), let engine = model.gameEngines[game.appID], model.environmentCopies[game.appID] != nil {
            NoticeRow(symbol: .info, text: "This game moved to \(engine.runsOn.title). A copy of its Windows environment from before is kept.") {
                Button("Restore…") { isConfirmingRestore = true }
                    .disabled(model.isBusy)
            }
        }
        if game.isInstalled, hasEnvironment, !isRunning, savedWindow == nil, model.refusedScreenSize.contains(game.appID) {
            NoticeRow(symbol: .warning, text: "This game asked for a screen size this Mac does not have, and stopped. A fixed window usually gets it going.") {
                Button("Use \(FixedWindow.Size.usual.description)") {
                    Task { await model.useFixedWindow(.usual, appID: game.appID) }
                }
                .disabled(model.isBusy)
            }
        }
        if game.isInstalled, !isRunning, !model.d3dMetalIsAdded, model.neededDirect3D12.contains(game.appID) {
            NoticeRow(symbol: .warning, text: "This game asked for Direct3D 12 and stopped. Only the D3DMetal renderer has it.") {
                Button("Add D3DMetal…") { model.showD3DMetalSheet() }
                    .disabled(model.isBusy)
            }
        }
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
            GameRunsOn(game: game, draft: $draft, requestMove: requestMove)
            GameRendererSettings(draft: $draft, renderer: effectiveLayer)
            Section {
                Toggle("Performance Overlay", isOn: $draft.performanceHUD)
                fixedWindowRow
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

    // MARK: Fixed window

    /// Shown for an installed game. It can only be set once the game has a Windows environment, which it gets at
    /// its first start, and not while the game is running.
    @ViewBuilder private var fixedWindowRow: some View {
        if game.isInstalled {
            Picker(selection: $draftWindow) {
                Text("Off").tag(FixedWindow.Size?.none)
                Divider()
                ForEach(offeredSizes) { size in
                    Text(size.description).tag(FixedWindow.Size?.some(size))
                }
            } label: {
                Text("Fixed Window")
                Text(fixedWindowCaption)
            }
            .disabled(!hasEnvironment || isRunning || model.isBusy)
        }
    }

    private var fixedWindowCaption: String {
        if !hasEnvironment { return "Available once the game has been started for the first time." }
        if isRunning { return "Quit the game to change this." }
        return "For old games that need a screen shape this Mac does not have. The game runs in a window of this size."
    }

    /// The sizes whose window fits this Mac's screen, and whichever one is set already.
    private var offeredSizes: [FixedWindow.Size] {
        let room = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1280, height: 720)
        return FixedWindow.sizes(fittingWidth: room.width, height: room.height, including: draftWindow ?? savedWindow)
    }

    // MARK: Moving between Wine versions

    private var defaultWine: String { model.engines.first(where: \.isDefault)?.spec.wine ?? Pins.engineWine }

    private var moveTitle: String {
        let target = pendingMove?.spec?.title ?? "the default, Wine \(defaultWine)"
        return "Move \(game.name) to \(target)?"
    }

    private var restoreTitle: String {
        guard let copy = model.environmentCopies[game.appID] else { return "Put back the copy?" }
        return "Put back the copy from \(copy.made.formatted(.dateTime.day().month(.wide).hour().minute()))?"
    }

    private var restoreMessage: String {
        guard let copy = model.environmentCopies[game.appID] else { return "" }
        return "It was made before this game moved from Wine \(copy.fromWine) to \(copy.toWine). Anything the game has saved in its Windows environment since then is replaced. Saves in Steam Cloud are not affected. Steam quits and reopens."
    }

    private var launchOptionsPreview: String {
        let options = draft.settings.launchOptions(merging: game.launchOptions, engine: model.engine(for: game.appID))
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
                if model.environmentCopies[game.appID] != nil {
                    Divider()
                    Button("Restore Windows Environment…") { isConfirmingRestore = true }
                        .disabled(model.isBusy)
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
        // Steam only has to quit when something kept in Steam changed.
        if model.savingNeedsSteamClosed(draft.settings, game: game) {
            isConfirmingQuit = true
        } else {
            save()
        }
    }

    private func save() {
        let settings = draft.settings
        let window = draftWindow
        Task { await model.save(settings, fixedWindow: window, appID: game.appID) }
    }
}
