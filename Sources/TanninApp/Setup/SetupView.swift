import SwiftUI
import TanninCore

/// The first-run window: five steps from a bare Mac to Windows games installing from Steam.
/// Each step's state is read from disk, so the window can be closed and reopened at any point.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    /// This window's own sheet, so asking here does not also open one on the main window.
    @State private var isAddingSteamPlay = false

    private var doneCount: Int { Setup.Step.allCases.count { model.setup[$0]?.isDone == true } }
    private var isAllDone: Bool { doneCount == Setup.Step.allCases.count }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                Text("Set Up Tannin")
                    .font(.title2.bold())
                    .padding(.top, 4)
                Text("Tannin downloads about \(Self.downloadSize), then adds Steam Play to Steam so it can install and run Windows games. You can remove it at any time.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 430)
            }
            .padding(.top, 8)

            Form {
                Section {
                    ForEach(Setup.Step.allCases) { step in
                        SetupStepRow(step: step, isAddingSteamPlay: $isAddingSteamPlay)
                    }
                } footer: {
                    Text("Optional, at any time: add Apple's D3DMetal renderer under Engines & Renderers. Games that use Direct3D 12 need it.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            HStack {
                Text("\(doneCount) of \(Setup.Step.allCases.count) steps done")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if isAllDone {
                    Button("Done", action: finish)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else if model.needsSetupAtLaunch {
                    Button("Quit") { NSApp.terminate(nil) }
                } else {
                    Button("Close") { dismissWindow(id: WindowID.setup) }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 620)
        .frame(height: 610)
        .sheet(isPresented: $isAddingSteamPlay) {
            SteamPlaySheet()
        }
        .alert("That didn't work", isPresented: $model.isShowingErrorInSetup) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    /// The engine and the Steam Play kit together, rounded to something easy to read.
    private static var downloadSize: String {
        let bytes = (Pins.engine.size ?? 0) + (Pins.notProton.size ?? 0)
        let rounded = (Double(bytes) / 10_000_000).rounded() * 10
        return "\(Int(rounded)) MB"
    }

    private func finish() {
        openWindow(id: WindowID.main)
        dismissWindow(id: WindowID.setup)
    }
}
