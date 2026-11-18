import SwiftUI
import TanninCore
import UniformTypeIdentifiers

/// What Tannin has put on this Mac and into Steam, and the few things that can be changed about it.
struct EngineView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var freeze = false
    @State private var isConfirmingRemoval = false
    @State private var isChoosingToolkit = false

    static let removalMessage = "Steam quits and is put back exactly as Valve ships it. Your games, saves and Steam account are not touched. Windows games stop being playable until you add Steam Play again."

    var body: some View {
        Group {
            if let status = model.status {
                Form {
                    if model.problem == .setupIncomplete {
                        Section {
                            LabeledContent {
                                Button("Continue Setup…") { openWindow(id: WindowID.setup) }
                                    .buttonStyle(.borderedProminent)
                            } label: {
                                Text("Setup isn't finished")
                                Text("Some of what Tannin needs is not on this Mac yet.")
                            }
                        }
                    }
                    if model.hasUpkeepToShow {
                        UpkeepSection()
                    }
                    steamPlay(status)
                    WineEnginesSection()
                    graphics(status)
                    bridge(status)
                }
                .formStyle(.grouped)
            } else {
                ProgressView("Checking this Mac…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Engine")
        .onChange(of: model.status?.updateFreeze, initial: true) { _, isOn in
            freeze = isOn ?? false
        }
        .onChange(of: freeze) { _, wanted in
            guard let current = model.status?.updateFreeze, current != wanted else { return }
            Task { await model.setUpdateFreeze(wanted) }
        }
        .confirmationDialog("Remove Steam Play from Steam?", isPresented: $isConfirmingRemoval) {
            Button("Remove Steam Play", role: .destructive) {
                Task { await model.removeSteamPlay() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.removalMessage)
        }
        .fileImporter(isPresented: $isChoosingToolkit, allowedContentTypes: [.diskImage, .folder]) { result in
            if case let .success(url) = result {
                Task { await model.importToolkit(from: url) }
            }
        }
    }

    private func steamPlay(_ status: TanninStatus) -> some View {
        Section {
            LabeledContent {
                if model.activity != nil {
                    ProgressView().controlSize(.small)
                }
                if status.steamPlay == .on {
                    Button("Remove Steam Play…") { isConfirmingRemoval = true }
                        .disabled(model.isBusy)
                } else if status.steamPlay == .off {
                    Button("Add Steam Play…") { model.isShowingSteamPlaySheet = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBusy || model.problem == .setupIncomplete || model.problem == .steamMissing)
                }
            } label: {
                Label {
                    Text(steamPlayTitle(status))
                    Text(steamPlayCaption(status))
                } icon: {
                    steamPlaySymbol(status).image
                }
            }
            Toggle(isOn: $freeze) {
                Text("Freeze Steam Updates")
                Text("Keeps Steam on this build so Steam Play stays on.")
            }
            .disabled(model.isBusy)
        } header: {
            Text("Steam Play")
        } footer: {
            Text("Removing Steam Play puts Steam back exactly as Valve ships it. Your games, saves and Steam account are not touched.")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func steamPlayTitle(_ status: TanninStatus) -> String {
        switch status.steamPlay {
        case .on: status.addonLoaded == false ? "Steam Play is off" : "Steam Play is on"
        case .off: "Steam Play is off"
        case .foreign: "Another tool is loaded into Steam"
        }
    }

    private func steamPlaySymbol(_ status: TanninStatus) -> StatusSymbol {
        switch status.steamPlay {
        case .on: status.addonLoaded == false ? .warning : .ok
        case .off: .pending
        case .foreign: .warning
        }
    }

    private func steamPlayCaption(_ status: TanninStatus) -> String {
        let build = status.steamBuild.map { " Steam build \($0)." } ?? ""
        switch status.steamPlay {
        case .off: return "Steam is as Valve ships it." + build
        case let .foreign(value): return "Tannin will not replace it. Remove the other tool first. (\(value))"
        case .on:
            switch status.addonLoaded {
            case true?: return "Loaded the last time Steam started." + build
            case false?: return "Steam updated itself, so Steam Play is off until Tannin supports the new build." + build
            case nil: return "Not loaded yet. It loads the next time Steam starts." + build
            }
        }
    }

    private func graphics(_ status: TanninStatus) -> some View {
        Section("Graphics Layers") {
            LabeledContent {
                Button(status.d3dMetalVersion == nil ? "Choose Disk Image…" : "Replace…") { isChoosingToolkit = true }
                    .disabled(model.isBusy)
            } label: {
                Text(status.d3dMetalVersion.map { "D3DMetal \($0)" } ?? "D3DMetal is not added")
                Text(status.d3dMetalVersion == nil
                    ? "Apple's layer, for Direct3D 12 games. From your own copy of the Game Porting Toolkit, free with an Apple account."
                    : "Apple's layer, from your Game Porting Toolkit. Apple's signature is valid.")
            }
            LabeledContent {
                state("Included", .ok)
            } label: {
                Text("DXMT \(LayerStore.dxmtVersion)")
                Text("Direct3D 10 and 11. Comes inside the Wine engine.")
            }
            LabeledContent {
                state("Included", .ok)
            } label: {
                Text("DXVK \(LayerStore.dxvkVersion)")
                Text("Direct3D 11 through Vulkan. Comes inside the Wine engine.")
            }
        }
    }

    private func bridge(_ status: TanninStatus) -> some View {
        Section("Steam Bridge") {
            LabeledContent {
                if !status.engineInstalled {
                    state("Not installed", .pending)
                } else if status.runnerProblems.isEmpty {
                    state("In place", .ok)
                } else {
                    state("Needs attention", .warning)
                }
            } label: {
                Text("Steam Bridge \(status.bridgeVersion)")
                Text(status.runnerProblems.isEmpty || !status.engineInstalled
                    ? "Lets games talk to Steam. Built on the NotProton project."
                    : status.runnerProblems.joined(separator: " "))
            }
        }
    }

    private func state(_ text: String, _ symbol: StatusSymbol) -> some View {
        HStack(spacing: 5) {
            symbol.image
            Text(text)
        }
        .accessibilityElement(children: .combine)
    }
}
