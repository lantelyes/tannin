import Foundation

enum SidebarItem: String, CaseIterable, Identifiable {
    case overview, games, engine, logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .games: "Games"
        case .engine: "Engine"
        case .logs: "Logs"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.33percent"
        case .games: "gamecontroller"
        case .engine: "cpu"
        case .logs: "doc.text"
        }
    }
}
