import SwiftUI
import TanninCore

/// The Wine engines Tannin has tested, as a list: which are installed, which is the default, the games on each,
/// and the button that installs one. Only engines that come with this Tannin are listed.
struct WineEnginesSection: View {
    @Environment(AppModel.self) private var model
    @State private var removing: EngineRow?
    @State private var makingDefault: EngineRow?

    var body: some View {
        Section(model.engines.count > 1 ? "Wine Engines" : "Wine Engine") {
            ForEach(model.engines) { row in
                LabeledContent {
                    control(row)
                } label: {
                    Label {
                        Text(row.spec.title)
                        caption(row)
                    } icon: {
                        mark(row)
                    }
                }
            }
        }
        .confirmationDialog(removing.map { "Remove \($0.spec.title)?" } ?? "", isPresented: isRemoving, presenting: removing) { row in
            Button("Remove", role: .destructive) { Task { await model.removeEngine(row.spec) } }
            Button("Cancel", role: .cancel) {}
        } message: { row in
            Text(removalMessage(row))
        }
        .confirmationDialog(makingDefault.map { "Make \($0.spec.title) the default?" } ?? "", isPresented: isMakingDefault, presenting: makingDefault) { row in
            Button(model.status?.steamRunning == true ? "Quit Steam and Make Default" : "Make Default") {
                Task { await model.makeDefaultEngine(row.spec) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Games that have no Wine version of their own move to it. Tannin first keeps a copy of each game's Windows environment, so a game can be put back. Steam has to be closed for this; Tannin reopens it afterwards.")
        }
    }

    private var isRemoving: Binding<Bool> {
        Binding { removing != nil } set: { if !$0 { removing = nil } }
    }

    private var isMakingDefault: Binding<Bool> {
        Binding { makingDefault != nil } set: { if !$0 { makingDefault = nil } }
    }

    private func progress(_ row: EngineRow) -> EngineProgress? {
        model.engineProgress?.spec == row.spec ? model.engineProgress : nil
    }

    // MARK: Pieces of a row

    @ViewBuilder private func mark(_ row: EngineRow) -> some View {
        if let progress = progress(row), !progress.isPaused {
            ProgressView().controlSize(.small)
        } else if row.isInstalled {
            StatusSymbol.ok.image
        } else {
            StatusSymbol.download.image
        }
    }

    @ViewBuilder private func caption(_ row: EngineRow) -> some View {
        if let progress = progress(row) {
            Text(downloadCaption(progress, row: row))
            if let fraction = progress.download?.fraction, progress.download?.isVerifying == false || progress.isPaused {
                ProgressView(value: fraction)
                    .accessibilityLabel("\(row.spec.title) download")
            }
        } else if row.isInstalled {
            Text(installedCaption(row))
        } else {
            Text("\(row.spec.note) \((row.spec.pin.size ?? 0).formatted(.byteCount(style: .file))) to download.")
        }
    }

    private func installedCaption(_ row: EngineRow) -> String {
        var facts = [row.games.count == 1 ? "1 game" : "\(row.games.count) games"]
        if let size = row.size { facts.append(size.formatted(.byteCount(style: .file))) }
        let line = facts.joined(separator: " · ")
        guard model.engines.count(where: \.isInstalled) > 1 else { return line + ". Built from CodeWeavers' published source." }
        return row.isDefault ? "The default. " + line : line
    }

    private func downloadCaption(_ progress: EngineProgress, row: EngineRow) -> String {
        guard let download = progress.download else { return progress.isPaused ? "Paused." : "Starting…" }
        if download.isVerifying { return "Checking the download and unpacking it…" }
        let received = download.received.formatted(.byteCount(style: .file, allowedUnits: .mb))
        let amount = download.total.map { "\(received) of \($0.formatted(.byteCount(style: .file, allowedUnits: .mb)))" } ?? received
        return progress.isPaused ? "Paused at \(amount)." : "Downloading. \(amount)."
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
            Button("Install") { Task { await model.installEngine(row.spec) } }
                .disabled(model.isBusy || model.status?.engineInstalled != true)
        } else if model.engines.count(where: \.isInstalled) > 1 {
            if row.isDefault {
                Text("Default").foregroundStyle(.secondary)
            }
            Menu("More", systemImage: "ellipsis") {
                Button("Make Default") { makingDefault = row }
                    .disabled(row.isDefault)
                Button("Show in Finder") { model.showEngineInFinder(row.spec) }
                Divider()
                Button("Remove…") { removing = row }
                    .disabled(row.isDefault || row.spec == .newest)
            }
            .labelStyle(.iconOnly)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(model.isBusy)
        } else {
            HStack(spacing: 5) {
                StatusSymbol.ok.image
                Text("Installed")
            }
            .accessibilityElement(children: .combine)
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
