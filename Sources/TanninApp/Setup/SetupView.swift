import SwiftUI
import TanninCore
import UniformTypeIdentifiers

/// The first-run window: six steps from a bare Mac to Windows games installing from Steam.
/// Each step's state is read from disk, so the window can be closed and reopened at any point.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isChoosingToolkit = false
    /// This window's own sheet, so asking here does not also open one on the main window.
    @State private var isAddingSteamPlay = false

    /// A skipped step counts: it has been dealt with.
    private var doneCount: Int { Setup.Step.allCases.count { model.setup[$0]?.isSettled == true } }
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
                        SetupStepRow(step: step, isChoosingToolkit: $isChoosingToolkit, isAddingSteamPlay: $isAddingSteamPlay)
                    }
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
        .frame(minHeight: 650)
        .sheet(isPresented: $isAddingSteamPlay) {
            SteamPlaySheet()
        }
        .alert("That didn't work", isPresented: $model.isShowingErrorInSetup) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .fileImporter(isPresented: $isChoosingToolkit, allowedContentTypes: [.diskImage, .folder]) { result in
            if case let .success(url) = result {
                Task { await model.importToolkit(from: url) }
            }
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
