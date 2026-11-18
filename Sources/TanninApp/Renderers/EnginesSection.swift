import SwiftUI
import TanninCore

/// The Wine engines Tannin has tested, as a list: which are installed, which is the default, the games on each,
/// and the button that installs one. Only engines that come with this Tannin are listed.
struct EnginesSection: View {
    @Environment(AppModel.self) private var model
    @State private var removing: EngineRow?
    @State private var isRemoving = false
    @State private var makingDefault: EngineRow?
    @State private var isMakingDefault = false

    var body: some View {
        Section("Engines") {
            ForEach(model.engines) { row in
                LabeledContent {
                    control(row)
                } label: {
                    Label {
                        Text(row.spec.title)
                        caption(row)
                    } icon: {
                        ComponentTile(kind: .engine, isOnThisMac: row.isInstalled)
                    }
                }
            }
        }
        .confirmationDialog(removing.map { "Remove \($0.spec.title)?" } ?? "", isPresented: $isRemoving, presenting: removing) { row in
            Button("Remove", role: .destructive) { Task { await model.removeEngine(row.spec) } }
            Button("Cancel", role: .cancel) {}
        } message: { row in
            Text(removalMessage(row))
        }
        .confirmationDialog(makingDefault.map { "Make \($0.spec.title) the default?" } ?? "", isPresented: $isMakingDefault, presenting: makingDefault) { row in
            Button(model.status?.steamRunning == true ? "Quit Steam and Make Default" : "Make Default") {
                Task { await model.makeDefaultEngine(row.spec) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Games that have no Wine version of their own move to it. Tannin first keeps a copy of each game's Windows environment, so a game can be put back. Steam has to be closed for this; Tannin reopens it afterwards.")
        }
    }

    private func progress(_ row: EngineRow) -> EngineProgress? {
        model.engineProgress?.spec == row.spec ? model.engineProgress : nil
    }

    /// The engine setup installs is not offered here before setup has: setup builds the Steam bridge around it.
    private var setupHasInstalledAnEngine: Bool { model.status?.engineInstalled == true }

    // MARK: Pieces of a row

    @ViewBuilder private func caption(_ row: EngineRow) -> some View {
        if let progress = progress(row) {
            Text(progress.caption())
            if let fraction = progress.fraction {
                ProgressView(value: fraction)
                    .accessibilityLabel("\(row.spec.title) download")
            }
        } else if row.isInstalled {
            Text(installedCaption(row))
        } else if row.spec == .newest, !setupHasInstalledAnEngine {
            Text("\(row.spec.note) Setup downloads it.")
        } else {
            Text("\(row.spec.note) \(row.spec.downloadSize) to download.")
        }
    }

    private func installedCaption(_ row: EngineRow) -> String {
        var facts = [row.games.count.gamesPhrase]
        if let size = row.size { facts.append(size.formatted(.byteCount(style: .file))) }
        let line = facts.joined(separator: " · ")
        return row.isDefault ? "The default. " + line : line
    }

    @ViewBuilder private func control(_ row: EngineRow) -> some View {
        if let progress = progress(row) {
            if progress.isPaused {
                Button("Resume") { Task { await model.installEngine(row.spec) } }
                    .disabled(model.isBusy)
            } else {
                Button("Pause") { model.pauseDownloads() }
                    .disabled(progress.download?.isVerifying == true)
            }
        } else if !row.isInstalled {
            if row.spec == .newest, !setupHasInstalledAnEngine {
                Text("Not installed").foregroundStyle(.secondary)
            } else {
                Button("Install") { Task { await model.installEngine(row.spec) } }
                    .disabled(model.isBusy || !setupHasInstalledAnEngine)
            }
        } else {
            StateLabel("Installed", .ok)
            Menu("More", systemImage: "ellipsis") {
                Button("Make Default") {
                    makingDefault = row
                    isMakingDefault = true
                }
                .disabled(row.isDefault)
                Button("Show in Finder") { model.showEngineInFinder(row.spec) }
                Divider()
                Button("Remove…") {
                    removing = row
                    isRemoving = true
                }
                .disabled(row.isDefault || row.spec == .newest)
            }
            .labelStyle(.iconOnly)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(model.isBusy)
        }
    }

    /// Names the games that will move, as the board draws it.
    private func removalMessage(_ row: EngineRow) -> String {
        let fallback = model.engines.first(where: \.isDefault)?.spec.title ?? "the default"
        let names = row.games.compactMap { model.library.game($0)?.name }
        var parts: [String] = []
        if !names.isEmpty {
            let list = ListFormatter.localizedString(byJoining: names)
            parts.append("\(list) \(names.count == 1 ? "uses" : "use") it and will move to \(fallback). Tannin keeps a copy of \(names.count == 1 ? "its" : "each one's") Windows environment first, and Steam quits and reopens.")
        }
        parts.append("The engine goes to the Trash.")
        return parts.joined(separator: " ")
    }
}
