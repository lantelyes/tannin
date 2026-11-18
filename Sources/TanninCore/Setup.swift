import Foundation

/// The steps that take a Mac from nothing to "Windows games install from Steam", in the order the app shows them.
/// Each step's state is read from what is on disk, so setup can be left and picked up again at any point.
public struct Setup: Sendable {
    public enum Step: String, CaseIterable, Sendable, Identifiable {
        case rosetta, steam, engine, toolkit, bridge, steamPlay

        public var id: String { rawValue }
    }

    public enum State: Sendable, Equatable {
        /// Finished, with a short description of what is in place.
        case done(String)
        /// Can be done now.
        case ready
        /// Needs something else first; the text says what.
        case waiting(String)

        public var isDone: Bool {
            if case .done = self { return true }
            return false
        }
    }

    public let paths: Paths
    /// Where macOS keeps Rosetta once it is installed. Replaceable so tests do not depend on this Mac.
    let rosetta: URL

    public init(paths: Paths = .live) {
        self.init(paths: paths, rosetta: URL(fileURLWithPath: "/Library/Apple/usr/share/rosetta/rosetta"))
    }

    init(paths: Paths, rosetta: URL) {
        self.paths = paths
        self.rosetta = rosetta
    }

    private var runnerIsBuilt: Bool {
        !Runner(paths: paths).verify().contains { $0.state == .broken }
    }

    public func state(of step: Step) -> State {
        let fm = FileManager.default
        switch step {
        case .rosetta:
            return fm.fileExists(atPath: rosetta.path) ? .done("Installed") : .ready
        case .steam:
            return SteamInstall(paths: paths).isInstalled ? .done("In Applications") : .ready
        case .engine:
            return Engine(paths: paths).isInstalled ? .done("Wine \(Pins.engineWine)") : .ready
        case .toolkit:
            if let toolkit = GPTK(paths: paths).imported().last { return .done("D3DMetal \(toolkit.version)") }
            return .ready
        case .bridge:
            guard Engine(paths: paths).isInstalled else { return .waiting("Needs the Wine engine first") }
            let toolkit = GPTK(paths: paths).imported().last
            let linked = D3DMetalLink(paths: paths).linkedVersion()
            if runnerIsBuilt, toolkit == nil || toolkit?.version == linked { return .done("NotProton \(Pins.notProtonVersion)") }
            return .ready
        case .steamPlay:
            switch SteamAddon(paths: paths).state() {
            case .on: return .done("On")
            case .foreign: return .waiting("Another tool is loaded into Steam")
            case .off: break
            }
            let earlier = Step.allCases.filter { $0 != .steamPlay }
            return earlier.allSatisfy { state(of: $0).isDone } ? .ready : .waiting("Needs the steps above first")
        }
    }

    public func states() -> [(step: Step, state: State)] {
        Step.allCases.map { ($0, state(of: $0)) }
    }

    /// True when everything is in place, whether or not Steam Play has been added to Steam yet.
    public var isReadyForSteamPlay: Bool {
        Step.allCases.filter { $0 != .steamPlay }.allSatisfy { state(of: $0).isDone }
    }

    // MARK: Doing the steps

    /// Asks macOS to install Rosetta. Apple's licence for it is accepted on the user's behalf, so the app says so
    /// next to the button that starts this.
    public func installRosetta(_ context: WorkContext = .terminal) throws {
        try Shell.check("/usr/sbin/softwareupdate", ["--install-rosetta", "--agree-to-license"],
                        inherit: !context.quiet && context.progress == nil, cancellation: context.cancellation)
    }

    public func installEngine(_ context: WorkContext = .terminal) throws {
        try Engine(paths: paths).install(context)
    }

    /// Imports D3DMetal from the user's own copy of Apple's toolkit and, if the runner is there, puts it to use.
    @discardableResult
    public func importToolkit(from source: URL) throws -> GPTK.Imported {
        let toolkit = try GPTK(paths: paths).importToolkit(from: source)
        if FileManager.default.fileExists(atPath: Runner(paths: paths).root.appending(path: "lib/wine").path) {
            try D3DMetalLink(paths: paths).link(toolkit)
        }
        return toolkit
    }

    /// Downloads the Steam add-on, bridge and Valve's client files, then assembles the runner Steam will launch.
    public func installBridge(_ context: WorkContext = .terminal) throws {
        let kit = NotProtonKit(paths: paths)
        try kit.unpack(context)
        try kit.stage()
        try kit.installValveFiles(context)
        try context.cancellation?.check()
        try Runner(paths: paths).build(patch: NtdllPatch(paths: paths))
        // The runner was rebuilt from a fresh copy of the engine, so put the imported D3DMetal back in.
        if let toolkit = try? GPTK(paths: paths).current() {
            try D3DMetalLink(paths: paths).link(toolkit)
        }
    }
}
