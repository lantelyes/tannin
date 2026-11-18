import Foundation
import Observation
import Sparkle

/// Tannin's own updates: a thin layer over Sparkle that views can observe.
///
/// Sparkle does the work and shows its standard windows. This type adds what Tannin's own screens
/// need: the state of the last check, and a check that shows no window.
@Observable @MainActor
final class Updates: NSObject {
    private(set) var status: UpdateStatus = .unknown
    private(set) var lastChecked: Date?
    /// False while Sparkle is busy, and always false when updating is not set up for this copy.
    private(set) var canCheck = false

    /// The version of this copy of Tannin, as shown to people.
    let currentVersion: String
    /// Sparkle refuses to update an app that is not in an Applications folder.
    let isInApplications: Bool

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    /// Updating only exists in a built `Tannin.app` that carries a feed address. A debug run, a test
    /// or a screenshot run has neither, so Sparkle is never started there.
    init(bundle: Bundle = .main, isTakingScreenshots: Bool = Snapshotter.outputFolder != nil) {
        currentVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        isInApplications = Self.isInApplicationsFolder(bundle.bundleURL)
        super.init()

        let hasFeed = bundle.object(forInfoDictionaryKey: "SUFeedURL") is String
        guard hasFeed, bundle.bundleURL.pathExtension == "app", !isTakingScreenshots else { return }

        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        lastChecked = controller.updater.lastUpdateCheckDate
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let value = change.newValue ?? false
            Task { @MainActor in self?.canCheck = value }
        }
    }

    /// Whether this copy can update itself at all.
    var isAvailable: Bool { controller != nil }

    /// The daily check. Tannin always asks before it installs anything.
    var checksAutomatically: Bool {
        get {
            access(keyPath: \.checksAutomatically)
            return controller?.updater.automaticallyChecksForUpdates ?? false
        }
        set {
            withMutation(keyPath: \.checksAutomatically) {
                controller?.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    /// "Check for Updates…": Sparkle's own windows report the result.
    func checkNow() {
        guard let controller, controller.updater.canCheckForUpdates else { return }
        status = .checking
        controller.checkForUpdates(nil)
    }

    /// Looks for an update without showing any window. The result arrives in `status`.
    func checkQuietly() {
        guard let updater = controller?.updater, updater.canCheckForUpdates, !updater.sessionInProgress else { return }
        status = .checking
        updater.checkForUpdateInformation()
    }

    static func isInApplicationsFolder(_ bundleURL: URL) -> Bool {
        let folder = bundleURL.deletingLastPathComponent().standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications").path
        return folder == "/Applications" || folder == home
    }
}

extension Updates: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        status = .available(version: item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        status = .upToDate
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        lastChecked = updater.lastUpdateCheckDate
        guard let error = error as NSError? else {
            if status == .checking { status = .upToDate }
            return
        }
        // "No update" and "the user closed the window" both end a cycle with an error; neither is a failure.
        let quietCodes = [Int(SUError.noUpdateError.rawValue), Int(SUError.installationCanceledError.rawValue)]
        if error.domain == SUSparkleErrorDomain, quietCodes.contains(error.code) {
            if status == .checking { status = .upToDate }
        } else if case .available = status {
            // An update was found; a later error in the same cycle does not change that.
        } else {
            status = .failed(error.localizedDescription)
        }
    }
}
