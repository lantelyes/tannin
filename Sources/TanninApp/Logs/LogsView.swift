import AppKit
import SwiftUI
import TanninCore

struct LogsView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = LogFilter.all
    @State private var search = ""
    @State private var didCopy = false

    /// Newest first, so the latest Steam start is at the top without scrolling.
    private var lines: [LogLine] {
        model.logLines.reversed().filter { line in
            filter.includes(line)
                && (search.isEmpty || line.message.localizedStandardContains(search) || line.source.localizedStandardContains(search))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if lines.isEmpty {
                ContentUnavailableView {
                    Label(model.logLines.isEmpty ? "Nothing logged yet" : "No matching lines", systemImage: "doc.text")
                } description: {
                    Text(model.logLines.isEmpty
                        ? "The log fills in once Steam has started with Steam Play on."
                        : "Try a different filter or search.")
                }
                .frame(maxHeight: .infinity)
            } else {
                List(lines) { line in
                    LogRow(line: line)
                        .listRowSeparatorTint(Theme.line)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            footer
        }
        .background(Theme.card)
        .navigationTitle("Logs")
        .searchable(text: $search, prompt: "Search")
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

    private var footer: some View {
        HStack {
            Text("\(lines.count) lines from the Steam add-on's log")
                .foregroundStyle(Theme.secondary)
            Spacer()
            Button(didCopy ? "Copied" : "Copy Details for a Bug Report", action: copyReport)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.window)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
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
