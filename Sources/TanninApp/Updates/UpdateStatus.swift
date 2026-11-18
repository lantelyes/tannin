/// What Tannin knows about its own updates since it started.
enum UpdateStatus: Equatable {
    /// No check has finished yet.
    case unknown
    case checking
    case upToDate
    case available(version: String)
    /// The check could not be made, with the system's description of why.
    case failed(String)
}
