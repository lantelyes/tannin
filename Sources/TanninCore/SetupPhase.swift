import Foundation

/// What a setup step that takes time is doing right now.
public struct SetupProgress: Sendable, Equatable {
    public var step: Setup.Step
    /// The download in hand, once one has reported in.
    public var download: DownloadProgress?
    /// True when the user paused it; the partial download is kept.
    public var isPaused: Bool

    public init(step: Setup.Step, download: DownloadProgress? = nil, isPaused: Bool = false) {
        self.step = step
        self.download = download
        self.isPaused = isPaused
    }
}

/// A setup step that stopped, with a sentence for the person looking at it and where it had got to.
public struct SetupFailure: Sendable, Equatable {
    public let progress: SetupProgress
    public let message: String

    public init(progress: SetupProgress, message: String) {
        self.progress = progress
        self.message = message
    }

    public init(_ error: any Error, during progress: SetupProgress) {
        var progress = progress
        progress.isPaused = false
        switch error {
        case DownloadError.allSourcesFailed:
            // The partial file stays, so the amount that arrived is still true.
            message = "The download stopped. Check your connection."
        case DownloadError.wrongSize, DownloadError.wrongHash:
            progress.download = nil
            message = "The download did not arrive whole, so it was removed."
        default:
            progress.download = nil
            message = progress.step == .rosetta
                ? "macOS could not install Rosetta. Check your connection."
                : String(describing: error)
        }
        self.progress = progress
    }
}

/// How adding Steam Play from the setup window is going.
public enum SteamPlayAdd: Sendable, Equatable {
    case idle
    case adding
    /// macOS did not let Tannin change Steam.app.
    case refused
    case failed(String)

    public init(_ error: any Error) {
        if case SteamAddonError.notPermitted = error {
            self = .refused
        } else {
            self = .failed(String(describing: error))
        }
    }
}

/// The part of the wait that setup is in.
public struct SetupWork: Sendable, Equatable {
    public enum Stage: Sendable, Equatable {
        case rosetta
        case engineDownload
        /// The engine has arrived and is being checked and unpacked.
        case engineUnpack
        /// The bridge step has started and no download has reported yet.
        case bridgePrepare
        case bridgeDownload
        /// Everything has arrived and the runner is being assembled.
        case bridgeBuild
    }

    public let stage: Stage
    /// How far the whole job is, from 0 to 1. Nil while only Rosetta is being installed, which reports nothing.
    public let fraction: Double?
    /// Bytes of the part in hand that have arrived, and how many it has. For the bridge, its three files count as one.
    public let received: Int64?
    public let total: Int64?

    /// Whether stopping now leaves something that can be picked up again.
    public var canPause: Bool {
        stage == .engineDownload || stage == .bridgeDownload || stage == .bridgePrepare
    }
}

/// The one moment the setup window is in, worked out from what is on disk and what is running.
public enum SetupPhase: Sendable, Equatable {
    /// Nothing has been read from disk yet.
    case checking
    case steamMissing
    /// Nothing is running. `fraction` is how much of the job an earlier run already did.
    case before(needsRosetta: Bool, bytesLeft: Int64, fraction: Double)
    case working(SetupWork)
    case paused(SetupWork)
    case failed(String, SetupWork)
    case readyForSteamPlay
    /// Something that is not Tannin's is loaded into Steam; Tannin will not replace it.
    case foreignTool
    case addingSteamPlay
    case steamPlayRefused
    case steamPlayFailed(String)
    case done

    public init(states: [Setup.Step: Setup.State], progress: SetupProgress?, failure: SetupFailure?, steamPlay: SteamPlayAdd) {
        func isDone(_ step: Setup.Step) -> Bool { states[step]?.isDone == true }
        if states.isEmpty {
            self = .checking
        } else if isDone(.steamPlay) {
            self = .done
        } else if steamPlay == .adding {
            self = .addingSteamPlay
        } else if let progress {
            let work = Setup.work(progress)
            self = progress.isPaused ? .paused(work) : .working(work)
        } else if !isDone(.steam) {
            self = .steamMissing
        } else if let failure {
            self = .failed(failure.message, Setup.work(failure.progress))
        } else if Setup.required.allSatisfy(isDone) {
            if case .waiting = states[.steamPlay] {
                // With everything else in place, the only thing Steam Play waits for is the other tool to go.
                self = .foreignTool
            } else {
                switch steamPlay {
                case .refused: self = .steamPlayRefused
                case let .failed(message): self = .steamPlayFailed(message)
                case .idle, .adding: self = .readyForSteamPlay
                }
            }
        } else {
            let missing = Setup.Step.allCases.filter { !isDone($0) }
            let left = missing.flatMap(Setup.downloads(for:)).reduce(Int64(0)) { $0 + ($1.size ?? 0) }
            let total = Setup.downloadBytes
            self = .before(needsRosetta: !isDone(.rosetta), bytesLeft: left,
                           fraction: total > 0 ? Setup.downloadShare * Double(total - left) / Double(total) : 0)
        }
    }

    /// How many of `count` covers are in colour, as a number that moves smoothly: 2.5 is two covers and half of
    /// the third. The downloads bring in all but the last; Steam Play brings in the last.
    public func lit(of count: Int) -> Double {
        let most = Double(max(0, count - 1))
        switch self {
        case .checking, .steamMissing: return 0
        case let .before(_, _, fraction): return fraction * most
        case let .working(work), let .paused(work), let .failed(_, work): return (work.fraction ?? 0) * most
        case .readyForSteamPlay, .foreignTool, .addingSteamPlay, .steamPlayRefused, .steamPlayFailed: return most
        case .done: return Double(count)
        }
    }
}

extension Setup {
    /// What each step downloads, in the order it is fetched.
    public static func downloads(for step: Step) -> [Pin] {
        switch step {
        case .engine: [Pins.engine]
        case .bridge: [Pins.notProton, Pins.valveLinux, Pins.valveWin64]
        case .rosetta, .steam, .steamPlay: []
        }
    }

    /// Everything setup downloads on a Mac that has none of it.
    public static var downloadBytes: Int64 {
        Step.allCases.flatMap(downloads(for:)).reduce(0) { $0 + ($1.size ?? 0) }
    }

    /// The share of the bar that the downloads fill. The rest is kept back for assembling the bridge at the end,
    /// so the bar is not full while work is still going on.
    public static let downloadShare = 0.94

    /// Where a running or stopped step stands within the whole job.
    static func work(_ progress: SetupProgress) -> SetupWork {
        guard progress.step != .rosetta else {
            return SetupWork(stage: .rosetta, fraction: nil, received: nil, total: nil)
        }
        let everything = Step.allCases.flatMap(downloads(for:))
        let mine = downloads(for: progress.step)
        let total = Double(max(1, downloadBytes))
        func size(_ pins: some Sequence<Pin>) -> Int64 { pins.reduce(0) { $0 + ($1.size ?? 0) } }
        // Everything fetched by the steps before this one.
        let before = size(everything.prefix { pin in !mine.contains { $0.name == pin.name } })

        guard let download = progress.download, let index = mine.firstIndex(where: { $0.name == download.name }) else {
            return SetupWork(stage: progress.step == .engine ? .engineDownload : .bridgePrepare,
                             fraction: downloadShare * Double(before) / total, received: nil, total: nil)
        }
        let received = size(mine[..<index]) + min(download.received, mine[index].size ?? download.received)
        let fraction = downloadShare * Double(before + received) / total
        if download.isVerifying, index == mine.count - 1 {
            // The last file of the step is here: what follows is unpacking or assembling, which reports nothing.
            return SetupWork(stage: progress.step == .engine ? .engineUnpack : .bridgeBuild, fraction: fraction, received: nil, total: nil)
        }
        return SetupWork(stage: progress.step == .engine ? .engineDownload : .bridgeDownload,
                         fraction: fraction, received: received, total: size(mine))
    }
}
