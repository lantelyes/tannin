import AppKit
import SwiftUI
import TanninCore

/// The Steam add-on's log, newest first: the only place that says whether Steam Play loaded and why not.
struct LogsView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = LogFilter.all
    @State private var search = ""
    @State private var selection: LogLine.ID?
    @State private var didCopy = false

    private var lines: [LogLine] {
        model.logLines.reversed().filter { line in
            filter.includes(line)
                && (search.isEmpty || line.message.localizedStandardContains(search) || line.source.localizedStandardContains(search))
        }
    }

    var body: some View {
        let lines = lines
        Group {
            if lines.isEmpty {
                ContentUnavailableView {
                    Label(model.logLines.isEmpty ? "Nothing Logged Yet" : "No Matching Lines", systemImage: "doc.text")
                } description: {
                    Text(model.logLines.isEmpty
                        ? "The log fills in once Steam has started with Steam Play on."
                        : "Try a different filter or search.")
                }
            } else {
                Table(lines, selection: $selection) {
                    TableColumn("Time") { line in
                        Text(line.time).monospacedDigit()
                    }
                    .width(min: 60, ideal: 70, max: 90)
                    TableColumn("Source") { line in
                        Text(line.source)
                    }
                    .width(min: 80, ideal: 120, max: 180)
                    TableColumn("Message") { line in
                        HStack(spacing: 5) {
                            if line.level == .warning { StatusSymbol.warning.image }
                            if line.level == .error {
                                Image(systemName: "xmark.octagon.fill")
                                    .foregroundStyle(.red)
                                    .accessibilityLabel("Error")
                            }
                            Text(line.message)
                                .lineLimit(1)
                                .help(line.message)
                        }
                    }
                }
                .alternatingRowBackgrounds()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer(count: lines.count) }
        .navigationTitle("Logs")
        .searchable(text: $search, placement: .toolbar, prompt: "Search")
        .toolbar {
            ToolbarItem {
                Picker("Show", selection: $filter) {
                    ForEach(LogFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func footer(count: Int) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text("^[\(count) line](inflect: true) from the Steam add-on's log")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([model.logFile])
                }
                .disabled(model.logLines.isEmpty)
                Button(didCopy ? "Copied" : "Copy Details for a Bug Report", action: copyReport)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func copyReport() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(model.bugReport(), forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }
}
