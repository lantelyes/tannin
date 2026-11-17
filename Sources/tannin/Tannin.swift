import ArgumentParser
import TanninCore

@main
struct Tannin: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tannin",
        abstract: "Free Steam Play for Mac: Windows games from the native Steam client.",
        version: "0.1.0",
        subcommands: [DoctorCommand.self]
    )
}

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check whether this Mac is ready. Changes nothing unless --probe-steam is given."
    )

    @Flag(name: .long, help: "Also test whether macOS lets Tannin change Steam.app (creates and removes one empty file inside it).")
    var probeSteam = false

    func run() throws {
        let checks = Doctor().run(probeSteam: probeSteam)
        let width = checks.map(\.name.count).max() ?? 0
        for check in checks {
            let label = "[\(check.state.rawValue)]".padding(toLength: 12, withPad: " ", startingAt: 0)
            let name = check.name.padding(toLength: width + 2, withPad: " ", startingAt: 0)
            print("\(label)\(name)\(check.detail)")
        }
        if checks.contains(where: { $0.state == .broken }) {
            throw ExitCode(1)
        }
    }
}
