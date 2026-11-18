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

    init(game: LibraryGame) {
        self.game = game
        _draft = State(initialValue: SettingsDraft(game.settings))
        _preset = State(initialValue: GamePreset(matching: game.settings))
    }

    private var hasChanges: Bool { draft.settings != game.settings.normalized }

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
        .onChange(of: draft) { preset = GamePreset(matching: draft.settings) }
        .onChange(of: game.launchOptions) {
            // Saved, or changed in Steam itself: show what Steam has now.
            draft = SettingsDraft(game.settings)
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
                    ForEach(GamePreset.allCases) { preset in
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
            NoticeRow(symbol: problem.isWarning ? .warning : .info, text: problem.explanation) {
                switch problem {
                case .steamUpdated:
                    Button("Show Logs") { model.selection = .logs }
                    Button("Remove Steam Play…") { isConfirmingRemoval = true }
                        .disabled(model.isBusy)
                case .off:
                    Button("Add Steam Play…") { model.isShowingSteamPlaySheet = true }
                        .disabled(model.isBusy)
                case .setupIncomplete:
                    Button("Continue Setup…") { openWindow(id: WindowID.setup) }
                case .otherTool, .steamMissing:
                    EmptyView()
                }
            }
        }
        if game.is32Bit == true {
            NoticeRow(symbol: .info,
                      text: "This is a 32-bit game. For now it runs without the Steam overlay, achievements and cloud saves.")
        }
    }

    // MARK: Settings

    private var settings: some View {
        Form {
            Section("Graphics") {
                LabeledContent("Graphics Layer", value: "D3DMetal")
                Toggle(isOn: $draft.rayTracing) {
                    Text("Ray Tracing")
                    Text("Looks better, costs frame rate. Off by default on M1 and M2.")
                }
                Toggle(isOn: $draft.metalFX) {
                    Text("MetalFX Upscaling")
                    Text("Lets the game's DLSS setting use Apple's upscaler.")
                }
                Picker("Frame Cap", selection: $draft.frameCap) {
                    ForEach(SettingsDraft.frameCaps, id: \.self) { cap in
                        Text(cap == 0 ? "None" : "\(cap) fps").tag(cap)
                    }
                }
            }
            Section {
                Toggle(isOn: $draft.metal4) {
                    Text("Metal 4 Renderer")
                    Text("The default on macOS 27. Turn off to use Metal 3.")
                }
                Toggle("Performance Overlay", isOn: $draft.performanceHUD)
                LabeledContent("Launch Options") {
                    Text(launchOptionsPreview)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
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
        guard let settings = preset.settings else { return }
        let target = SettingsDraft(settings)
        if target != draft { draft = target }
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
