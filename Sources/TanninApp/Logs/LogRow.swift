import SwiftUI
import TanninCore

struct LogRow: View {
    let line: LogLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(line.time)
                .foregroundStyle(Theme.secondary)
                .frame(width: 64, alignment: .leading)
            Text(levelWord)
                .font(.caption2.weight(.bold))
                .foregroundStyle(line.level == .info ? Theme.ok : Theme.card)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background {
                    // Info is outlined, warnings and errors are filled, so the level reads without colour.
                    if line.level == .info {
                        RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.ok)
                    } else {
                        RoundedRectangle(cornerRadius: 4).fill(line.level == .error ? Theme.broken : Theme.attention)
                    }
                }
                .frame(width: 48, alignment: .leading)
            Text(line.source)
                .foregroundStyle(Theme.secondary)
                .frame(width: 110, alignment: .leading)
                .lineLimit(1)
            Text(line.message)
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
        }
        .font(.callout.monospaced())
        .accessibilityElement(children: .combine)
    }

    private var levelWord: String {
        switch line.level {
        case .info: "INFO"
        case .warning: "WARN"
        case .error: "ERR"
        }
    }
}
