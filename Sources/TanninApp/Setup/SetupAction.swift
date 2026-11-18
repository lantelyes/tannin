import SwiftUI
import TanninCore

/// The middle of the setup window: the one thing to do next, or what is happening now.
struct SetupAction: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let phase: SetupPhase
    @Binding var isAddingSteamPlay: Bool
    /// What the last screen's button does.
    let finish: () -> Void

    private static let steamPage = URL(string: "https://store.steampowered.com/about/")!
    /// The page of System Settings where an app is allowed to change other apps.
    private static let appManagement = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")!

    var body: some View {
        VStack(spacing: 10) {
            switch phase {
            case .checking:
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Checking this Mac")

            case .steamMissing:
                SetupNotice(title: "Steam is not in your Applications folder", detail: "Install Steam and sign in, then come back.") {
                    Button("Get Steam") { openURL(Self.steamPage) }
                }

            case let .before(needsRosetta, bytesLeft, fraction):
                start(fraction > 0 ? "Continue" : "Set Up")
                Text(startCaption(needsRosetta: needsRosetta, bytesLeft: bytesLeft, isContinuing: fraction > 0))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 400)

            case let .working(work):
                SetupWait(work: work, state: .working)

            case let .paused(work):
                SetupWait(work: work, state: .paused)
                Button("Resume", action: run)
                    .controlSize(.large)
                    .disabled(model.isBusy)

            case let .failed(message, work):
                SetupWait(work: work, state: .failed(message))
                Button("Try Again", action: run)
                    .controlSize(.large)
                    .disabled(model.isBusy)

            case .readyForSteamPlay:
                SteamPlayCard(isAddingSteamPlay: $isAddingSteamPlay)

            case .foreignTool:
                SetupNotice(title: "Another tool is loaded into Steam", detail: "Tannin will not replace it. Remove the other tool first, then come back.")

            case .addingSteamPlay:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Adding Steam Play…").fontWeight(.semibold)
                        Text("Steam is quitting. It opens again by itself.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)

            case .steamPlayRefused:
                SetupNotice(title: "macOS did not let Tannin change Steam",
                            detail: "Allow Tannin under Privacy & Security, App Management, then add Steam Play again.") {
                    Button("Open Settings") { openURL(Self.appManagement) }
                }
                SteamPlayCard(isAddingSteamPlay: $isAddingSteamPlay)

            case let .steamPlayFailed(message):
                SetupNotice(title: "Steam Play was not added", detail: message)
                SteamPlayCard(isAddingSteamPlay: $isAddingSteamPlay)

            case .done:
                Button(model.library.all.isEmpty ? "Done" : "Show My Games", action: finish)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.extraLarge)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func start(_ label: String) -> some View {
        Button(label, action: run)
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
            .disabled(model.isBusy)
    }

    private func startCaption(needsRosetta: Bool, bytesLeft: Int64, isContinuing: Bool) -> String {
        if needsRosetta {
            "Also installs Rosetta, Apple's translator for the Windows side of a game. Setting up accepts Apple's licence for it."
        } else if isContinuing {
            "The Wine engine is already on this Mac. \(bytesLeft.megabytes) is left to download."
        } else {
            "Rosetta and Steam are already on this Mac."
        }
    }

    private func run() {
        Task { await model.runSetup() }
    }
}
