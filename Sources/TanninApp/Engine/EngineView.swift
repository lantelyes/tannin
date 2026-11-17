import SwiftUI
import TanninCore
import UniformTypeIdentifiers

struct EngineView: View {
    @Environment(AppModel.self) private var model
    @State private var freeze = false
    @State private var isConfirmingRemoval = false
    @State private var isChoosingToolkit = false

    var body: some View {
        ScrollView {
            if let status = model.status {
                VStack(alignment: .leading, spacing: 16) {
                    steamPlay(status)
                    wine(status)
                    d3dMetal(status)
                    bridge(status)
                }
                .padding(24)
            } else {
                ProgressView("Checking this Mac…").padding(60)
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
            Text("Steam quits and is put back exactly as Valve ships it. Your games, saves and Steam account are not touched. Windows games stop being playable until you add Steam Play again.")
        }
        .fileImporter(isPresented: $isChoosingToolkit, allowedContentTypes: [.diskImage, .folder]) { result in
            if case let .success(url) = result {
                Task { await model.importToolkit(from: url) }
            }
        }
    }

    private func steamPlay(_ status: TanninStatus) -> some View {
        CardSection(title: "Steam Play in Steam") {
            CardRow(title: status.steamPlay == .on ? "On" : "Off",
                    caption: steamPlayCaption(status),
                    status: steamPlayKind(status)) {
                if let build = status.steamBuild { VersionChip(text: build) }
                if status.steamPlay == .on {
                    Button("Remove Steam Play") { isConfirmingRemoval = true }
                        .disabled(model.isBusy)
                } else {
                    Button("Add Steam Play") { model.isShowingSteamPlaySheet = true }
                        .buttonStyle(.primary)
                        .disabled(model.isBusy)
                }
            }
            CardRow(title: "Freeze Steam updates",
                    caption: "Keeps Steam on this build so Steam Play stays on.",
                    showsDivider: false) {
                Toggle("Freeze Steam updates", isOn: $freeze)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(model.isBusy)
            }
        }
    }

    private func steamPlayKind(_ status: TanninStatus) -> StatusKind {
        guard status.steamPlay == .on else { return .off }
        return status.addonLoaded == false ? .attention : .ok
    }

    private func steamPlayCaption(_ status: TanninStatus) -> String {
        switch status.steamPlay {
        case .off: "Steam is as Valve ships it."
        case .foreign: "Another tool is loaded into Steam."
        case .on:
            switch status.addonLoaded {
            case true?: "Loaded the last time Steam started."
            case false?: "Steam is newer than Tannin knows. Steam Play is off until Tannin catches up."
            case nil: "Not loaded yet. It loads the next time Steam starts."
            }
        }
    }

    private func wine(_ status: TanninStatus) -> some View {
        CardSection(title: "Wine engine") {
            CardRow(title: status.engineInstalled ? "Installed" : "Not installed",
                    caption: "Built from CodeWeavers' published Wine source. The download is checked against a pinned hash.",
                    status: status.engineInstalled ? .ok : .pending,
                    showsDivider: false) {
                VersionChip(text: status.engineWine)
            }
        }
    }

    private func d3dMetal(_ status: TanninStatus) -> some View {
        CardSection(title: "D3DMetal") {
            CardRow(title: status.d3dMetalVersion == nil ? "Not imported" : "From your Game Porting Toolkit",
                    caption: "Apple's graphics translator. Tannin checks Apple's signature before using it.",
                    status: status.d3dMetalVersion == nil ? .pending : .ok,
                    showsDivider: false) {
                if let version = status.d3dMetalVersion { VersionChip(text: version) }
                Button(status.d3dMetalVersion == nil ? "Choose Disk Image" : "Replace") { isChoosingToolkit = true }
                    .disabled(model.isBusy || !status.engineInstalled)
            }
        }
    }

    private func bridge(_ status: TanninStatus) -> some View {
        CardSection(title: "Steam bridge") {
            CardRow(title: status.runnerProblems.isEmpty ? "In place" : "Needs attention",
                    caption: status.runnerProblems.isEmpty
                        ? "Lets 64-bit games talk to Steam. Built on the NotProton project."
                        : status.runnerProblems.joined(separator: " "),
                    status: status.runnerProblems.isEmpty ? .ok : .attention,
                    showsDivider: false) {
                VersionChip(text: status.bridgeVersion)
            }
        }
    }
}
