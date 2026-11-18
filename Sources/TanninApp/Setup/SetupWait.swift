import SwiftUI
import TanninCore

/// The bar for the whole of setup, with a line under it saying what is happening and how much of the part in
/// hand has arrived. The same bar stays where it was when setup is paused or has stopped.
struct SetupWait: View {
    enum State: Equatable {
        case working, paused
        case failed(String)
    }

    let work: SetupWork
    let state: State

    var body: some View {
        VStack(spacing: 8) {
            bar
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if case .failed = state {
                    StatusSymbol.warning.image
                }
                Text(line)
                    .foregroundStyle(isFailed ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let amount {
                    Text(amount)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .frame(width: 460)
        .accessibilityElement(children: .combine)
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    @ViewBuilder private var bar: some View {
        if let fraction = work.fraction {
            ProgressView(value: fraction)
                .accessibilityLabel("Setup")
        } else if state == .working {
            // Rosetta is installed by macOS, which does not say how far along it is.
            ProgressView()
                .progressViewStyle(.linear)
                .accessibilityLabel("Setup")
        } else {
            ProgressView(value: 0)
                .accessibilityLabel("Setup")
        }
    }

    private var line: String {
        switch state {
        case let .failed(message): message
        case .paused: "Paused"
        case .working:
            switch work.stage {
            case .rosetta: "Installing Rosetta…"
            case .engineDownload: "Downloading Wine \(Pins.engineWine)"
            case .engineUnpack: "Checking Wine \(Pins.engineWine) and unpacking it…"
            case .bridgePrepare: "Preparing the Steam bridge…"
            case .bridgeDownload: "Downloading the Steam bridge"
            case .bridgeBuild: "Putting the Steam bridge together…"
            }
        }
    }

    private var amount: String? {
        guard let received = work.received, let total = work.total else { return nil }
        return "\(Int((Double(received) / 1_000_000).rounded())) of \(total.megabytes)"
    }
}
