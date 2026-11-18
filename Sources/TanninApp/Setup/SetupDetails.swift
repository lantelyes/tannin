import SwiftUI
import TanninCore

/// The five things setup needs, one line each, for anyone who wants to see them.
struct SetupDetails: View {
    @Environment(AppModel.self) private var model
    let phase: SetupPhase

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Setup.Step.allCases) { step in
                if step != Setup.Step.allCases.first { Divider().padding(.horizontal, 12) }
                HStack(spacing: 10) {
                    mark(step)
                        .frame(width: 16)
                    Text(name(step))
                    Spacer(minLength: 12)
                    Text(value(step))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .frame(height: 33)
                .accessibilityElement(children: .combine)
            }
        }
        .background(.fill.quaternary, in: .rect(cornerRadius: 10))
    }

    private func isDone(_ step: Setup.Step) -> Bool { model.setup[step]?.isDone == true }

    /// What setup is doing to this step right now, if it is the one in hand.
    private func stage(_ step: Setup.Step) -> (stage: SetupWork.Stage, isRunning: Bool)? {
        let found: (SetupWork, Bool)? = switch phase {
        case let .working(work): (work, true)
        case let .paused(work), let .failed(_, work): (work, false)
        default: nil
        }
        guard let (work, isRunning) = found else { return nil }
        let owner: Setup.Step = switch work.stage {
        case .rosetta: .rosetta
        case .engineDownload, .engineUnpack: .engine
        case .bridgePrepare, .bridgeDownload, .bridgeBuild: .bridge
        }
        return owner == step ? (work.stage, isRunning) : nil
    }

    @ViewBuilder private func mark(_ step: Setup.Step) -> some View {
        if isDone(step) {
            StatusSymbol.ok.image
        } else if stage(step)?.isRunning == true {
            ProgressView().controlSize(.small)
        } else if step == .steamPlay, phase == .foreignTool {
            StatusSymbol.warning.image
        } else {
            StatusSymbol.pending.image
        }
    }

    private func name(_ step: Setup.Step) -> String {
        switch step {
        case .rosetta: "Rosetta"
        case .steam: "Steam"
        case .engine: "Wine engine"
        case .bridge: "Steam bridge"
        case .steamPlay: "Steam Play"
        }
    }

    private func value(_ step: Setup.Step) -> String {
        if let (stage, isRunning) = stage(step), !isDone(step) {
            guard isRunning else { return phase.isPaused ? "Paused" : "Stopped" }
            return switch stage {
            case .rosetta: "Installing"
            case .engineDownload, .bridgeDownload, .bridgePrepare: "Downloading"
            case .engineUnpack: "Unpacking"
            case .bridgeBuild: "Putting together"
            }
        }
        switch step {
        case .rosetta:
            return isDone(step) ? "Installed" : "Not installed"
        case .steam:
            guard isDone(step) else { return "Not found" }
            return "In Applications" + (model.status?.steamBuild.map { ", build \($0)" } ?? "")
        case .engine:
            return isDone(step) ? "Wine \(Pins.engineWine)" : toDownload(step)
        case .bridge:
            if isDone(step) { return "In place" }
            // While the engine is on its way the bridge is simply next.
            return stage(.engine) != nil ? "After the engine" : toDownload(step)
        case .steamPlay:
            if isDone(step) { return "On" }
            switch phase {
            case .foreignTool: return "Another tool is loaded into Steam"
            case .readyForSteamPlay, .steamPlayRefused, .steamPlayFailed: return "Ready to add"
            case .addingSteamPlay: return "Adding"
            default: return "Asks you first"
            }
        }
    }

    private func toDownload(_ step: Setup.Step) -> String {
        let bytes = Setup.downloads(for: step).reduce(Int64(0)) { $0 + ($1.size ?? 0) }
        return "\(bytes.megabytes) to download"
    }
}
