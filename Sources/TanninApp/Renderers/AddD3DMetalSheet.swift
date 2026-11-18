import SwiftUI
import TanninCore
import UniformTypeIdentifiers

/// Adding D3DMetal, the one renderer that is not downloaded by Tannin: where to get Apple's toolkit, then
/// the disk image. The sheet stays up while Tannin checks it, closes once D3DMetal is added, and says in
/// place what went wrong when it was not. Replacing a version uses the same sheet.
struct AddD3DMetalSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isChoosing = false
    @State private var isDropTarget = false

    static let applePage = URL(string: "https://developer.apple.com/download/all/?q=game%20porting%20toolkit")!

    private var present: String? { model.status?.d3dMetalVersion }
    private var checking: String? {
        if case let .checking(name) = model.d3dMetalAdd { return name }
        return nil
    }
    private var problem: String? {
        if case let .failed(reason) = model.d3dMetalAdd { return reason }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ComponentTile(kind: .renderer, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(present == nil ? "Add D3DMetal" : "Replace D3DMetal")
                        .font(.headline)
                    Text(present.map { "D3DMetal \($0) is on this Mac. Another Game Porting Toolkit disk image takes its place." }
                        ?? "Apple's renderer comes in the Game Porting Toolkit, a free download with an Apple account.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 0) {
                step(1, "Download the toolkit from Apple", "The newest “Game Porting Toolkit” disk image.") {
                    Button("Open Apple’s Page", systemImage: "arrow.up.right") { openURL(Self.applePage) }
                        .labelStyle(.titleAndIcon)
                }
                Divider().padding(.leading, 42)
                if let checking {
                    step(2, "Checking Apple's signature…", checking, isFileName: true) {
                        ProgressView().controlSize(.small)
                    }
                } else {
                    step(2, "Choose the disk image", "Or drop it on this window.") {
                        Button(problem == nil ? "Choose…" : "Choose Another…") { isChoosing = true }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .background(.quaternary.opacity(isDropTarget ? 1 : 0.5), in: .rect(cornerRadius: 10))

            if let problem {
                NoticeRow(symbol: .warning, text: problem)
            }

            Text("Tannin takes only D3DMetal out of it and checks Apple's signature first.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(checking != nil)
            }
        }
        .padding(20)
        .frame(width: 460)
        .interactiveDismissDisabled(checking != nil)
        .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.diskImage, .folder]) { result in
            if case let .success(url) = result { add(url) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard checking == nil, let url = urls.first else { return false }
            add(url)
            return true
        } isTargeted: { isDropTarget = $0 }
    }

    private func add(_ url: URL) {
        Task { await model.addD3DMetal(from: url) }
    }

    private func step<Trailing: View>(_ number: Int, _ title: String, _ detail: String, isFileName: Bool = false,
                                      @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Text(number, format: .number)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .frame(width: 20, height: 20)
                .background(.quaternary, in: .circle)
                .accessibilityLabel("Step \(number)")
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    // A long file name is cut in the middle; a sentence wraps.
                    .lineLimit(isFileName ? 1 : nil)
                    .truncationMode(.middle)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            trailing()
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}
