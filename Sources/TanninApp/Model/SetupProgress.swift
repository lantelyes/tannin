import TanninCore

/// What a setup step that downloads something is doing right now.
struct SetupProgress: Equatable {
    var step: Setup.Step
    var download: DownloadProgress?
    /// True when the user paused it; the partial download is kept.
    var isPaused = false
}
