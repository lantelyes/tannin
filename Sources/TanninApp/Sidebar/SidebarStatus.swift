import SwiftUI
import TanninCore

/// The two lines at the foot of the sidebar: whether Steam Play is on, and what it is running on.
struct SidebarStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            mark
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var mark: some View {
        if model.status == nil {
            ProgressView().controlSize(.mini)
        } else if let problem = model.problem {
            if problem.isWarning {
                StatusSymbol.warning.image.font(.caption)
            } else {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        } else {
            Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
        }
    }

    private var title: String {
        guard model.status != nil else { return "Checking Steam…" }
        return model.problem?.title ?? "Steam Play is on"
    }

    private var detail: String {
        guard let status = model.status else { return " " }
        if let problem = model.problem { return problem.detail }
        return status.stackSummary
    }
}
