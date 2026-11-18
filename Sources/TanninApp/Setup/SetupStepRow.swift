import SwiftUI
import TanninCore

/// One line of the setup checklist: a mark, what the step is, and the one thing to do about it.
struct SetupStepRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let step: Setup.Step
    @Binding var isAddingSteamPlay: Bool

    private static let steamPage = URL(string: "https://store.steampowered.com/about/")!

    private var state: Setup.State { model.setup[step] ?? .waiting("Checking") }
    private var progress: SetupProgress? { model.setupProgress?.step == step ? model.setupProgress : nil }
    private var isRunning: Bool { progress != nil && progress?.isPaused == false }
    private var isWaiting: Bool {
        if case .waiting = state { return true }
        return false
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            mark
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(isWaiting ? .secondary : .primary)
                caption
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let progress, step != .rosetta {
                    bar(progress)
                        .padding(.top, 3)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.vertical, 2)
    }

    // MARK: Mark

    @ViewBuilder private var mark: some View {
        if state.isDone {
            StatusSymbol.ok.image.font(.title3)
        } else if isRunning {
            ProgressView().controlSize(.small)
        } else {
            StatusSymbol.pending.image.font(.title3).opacity(isWaiting ? 0.5 : 1)
        }
    }

    // MARK: Words

    private var title: String {
        switch step {
        case .rosetta: "Rosetta"
        case .steam: "Steam"
        case .engine: "Wine Engine"
        case .bridge: "Steam Bridge"
        case .steamPlay: "Add Steam Play to Steam"
        }
    }

    @ViewBuilder private var caption: some View {
        switch step {
        case .rosetta:
            Text(state.isDone
                ? "Lets this Mac run the Windows side of a game."
                : "Lets this Mac run the Windows side of a game. Installing it accepts Apple's licence for it.")
        case .steam:
            if state.isDone {
                Text("Found in Applications\(model.status?.steamBuild.map { ", build \($0)" } ?? "").")
            } else {
                Text("Not found in the Applications folder. Install it, then come back.")
            }
        case .engine:
            Text(downloadCaption(idle: state.isDone
                                     ? "Wine \(Pins.engineWine), with the DXMT and DXVK renderers inside."
                                     : "Wine \(Pins.engineWine), built from CodeWeavers' published source.",
                                 working: "Downloading Wine \(Pins.engineWine)."))
        case .bridge:
            Text(downloadCaption(idle: "Lets games talk to Steam. Built once the engine has downloaded.",
                                 working: "Downloading the Steam bridge."))
        case .steamPlay:
            Text("The only step that changes Steam. Steam quits once.")
        }
    }

    private func downloadCaption(idle: String, working: String) -> String {
        guard let progress else { return idle }
        guard let download = progress.download else { return progress.isPaused ? "Paused." : "Starting…" }
        if download.isVerifying { return "Checking the download and unpacking it…" }
        let received = download.received.megabytes
        let amount = download.total.map { "\(received) of \($0.megabytes)" } ?? received
        return progress.isPaused ? "Paused at \(amount)." : "\(working) \(amount)."
    }

    private func bar(_ progress: SetupProgress) -> some View {
        Group {
            if let fraction = progress.download?.fraction, progress.download?.isVerifying == false {
                ProgressView(value: fraction)
            } else if progress.isPaused {
                ProgressView(value: progress.download?.fraction ?? 0)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
        }
        .accessibilityLabel("\(title) download")
    }

    // MARK: Control

    @ViewBuilder private var control: some View {
        if let progress, step != .rosetta {
            if progress.isPaused {
                Button("Resume") { start() }
                    .disabled(model.isBusy)
            } else {
                Button("Pause") { model.pauseDownloads() }
                    .disabled(progress.download?.isVerifying == true)
            }
        } else {
            switch state {
            case let .done(detail):
                Text(doneWord(detail)).foregroundStyle(.secondary)
            case .waiting:
                if step == .steamPlay {
                    Button("Add Steam Play…") {}.disabled(true)
                } else {
                    Text("Waiting").foregroundStyle(.secondary)
                }
            case .ready:
                readyControl
            }
        }
    }

    private func doneWord(_ detail: String) -> String {
        switch step {
        case .rosetta, .engine: "Installed"
        case .steam: "Found"
        case .bridge: "In place"
        case .steamPlay: "On"
        }
    }

    @ViewBuilder private var readyControl: some View {
        switch step {
        case .rosetta:
            Button("Install") { start() }
                .disabled(model.isBusy)
        case .steam:
            Button("Get Steam") { openURL(Self.steamPage) }
        case .engine:
            Button("Download") { start() }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
        case .bridge:
            Button("Install") { start() }
                .disabled(model.isBusy)
        case .steamPlay:
            Button("Add Steam Play…") { isAddingSteamPlay = true }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
        }
    }

    private func start() {
        Task { await model.runDownloads(startingWith: step) }
    }
}
