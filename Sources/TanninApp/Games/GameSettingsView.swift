import SwiftUI
import TanninCore

struct GameSettingsView: View {
    @Environment(AppModel.self) private var model
    let game: WindowsGame

    @State private var draft: SettingsDraft
    @State private var preset: GamePreset
    @State private var isConfirmingQuit = false

    init(game: WindowsGame) {
        self.game = game
        _draft = State(initialValue: SettingsDraft(game.settings))
        _preset = State(initialValue: GamePreset(matching: game.settings))
    }

    /// The game as Steam has it now, which changes after a save.
    private var current: WindowsGame { model.games.first { $0.id == game.id } ?? game }
    private var hasChanges: Bool { draft.settings != current.settings.normalized }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Preset", selection: $preset) {
                    ForEach(GamePreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 460)

                graphics
                advanced

                HStack {
                    Text("Changes apply the next time the game starts.")
                        .foregroundStyle(Theme.secondary)
                    Spacer()
                    Button("Save", action: requestSave)
                        .buttonStyle(.primary)
                        .disabled(!hasChanges || model.isBusy)
                }
            }
            .padding(24)
        }
        .background(Theme.window)
        .navigationTitle(game.name)
        .onChange(of: preset) { applyPreset() }
        .onChange(of: draft) { preset = GamePreset(matching: draft.settings) }
        .confirmationDialog("Quit Steam to save?", isPresented: $isConfirmingQuit) {
            Button("Quit Steam and Save") { save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Steam rewrites its settings when it quits, so it has to be closed first. Tannin reopens it afterwards.")
        }
    }

    private var graphics: some View {
        CardSection(title: "Graphics") {
            CardRow(title: "Graphics layer", caption: "D3DMetal is Apple's translator. Best for DirectX 12 games.") {
                Text("D3DMetal").foregroundStyle(Theme.secondary)
            }
            CardRow(title: "Ray tracing", caption: "Off by default on M1 and M2. Looks better, costs frame rate.") {
                changedBadge(draft.rayTracing != GameSettings.Default.rayTracing)
                Toggle("Ray tracing", isOn: $draft.rayTracing).labelsHidden().toggleStyle(.switch)
            }
            CardRow(title: "MetalFX upscaling", caption: "Lets the game's DLSS setting use Apple's upscaler.") {
                changedBadge(draft.metalFX != GameSettings.Default.metalFX)
                Toggle("MetalFX upscaling", isOn: $draft.metalFX).labelsHidden().toggleStyle(.switch)
            }
            CardRow(title: "Frame cap", showsDivider: false) {
                changedBadge(draft.frameCap != GameSettings.Default.frameCap)
                Picker("Frame cap", selection: $draft.frameCap) {
                    ForEach(SettingsDraft.frameCaps, id: \.self) { cap in
                        Text(cap == 0 ? "None" : "\(cap) fps").tag(cap)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var advanced: some View {
        CardSection(title: "Advanced") {
            CardRow(title: "Metal 4 renderer", caption: "The default on macOS 27. Turn off to use Metal 3.") {
                changedBadge(draft.metal4 != GameSettings.Default.metal4)
                Toggle("Metal 4 renderer", isOn: $draft.metal4).labelsHidden().toggleStyle(.switch)
            }
            CardRow(title: "Show performance overlay") {
                changedBadge(draft.performanceHUD != GameSettings.Default.performanceHUD)
                Toggle("Show performance overlay", isOn: $draft.performanceHUD).labelsHidden().toggleStyle(.switch)
            }
            CardRow(title: "Launch options",
                    caption: "What Tannin writes into this game's launch options in Steam.",
                    showsDivider: false) {
                Text(preview)
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.chip, in: .rect(cornerRadius: 6))
            }
        }
    }

    private var preview: String {
        let options = draft.settings.launchOptions(merging: current.launchOptions)
        return options.isEmpty ? "none" : options
    }

    @ViewBuilder private func changedBadge(_ changed: Bool) -> some View {
        if changed {
            Text("Changed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.accentText) }
        }
    }

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
