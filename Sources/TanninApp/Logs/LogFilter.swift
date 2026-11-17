import TanninCore

enum LogFilter: String, CaseIterable, Identifiable {
    case all, warnings, errors

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .warnings: "Warnings"
        case .errors: "Errors"
        }
    }

    func includes(_ line: LogLine) -> Bool {
        switch self {
        case .all: true
        case .warnings: line.level != .info
        case .errors: line.level == .error
        }
    }
}
