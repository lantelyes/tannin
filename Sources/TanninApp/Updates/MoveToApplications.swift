import AppKit
import TanninCore

/// The question asked at launch when Tannin is run from anywhere but an Applications folder, and the move itself.
///
/// macOS runs a freshly downloaded app from a hidden read-only copy, and an app cannot update itself from
/// there. Friends are not expected to know that, so Tannin offers to do what dragging it to Applications does.
@MainActor
enum MoveToApplications {
    private struct LocationUnknown: Error, CustomStringConvertible {
        let description = "Tannin couldn’t find where it’s stored."
    }

    private struct AlreadyOpenThere: Error, CustomStringConvertible {
        let description = "Another copy of Tannin is open from the Applications folder. Quit it first."
    }

    /// Only a copy that can update itself has a reason to ask, and a screenshot run never does.
    static func shouldOffer(bundle: Bundle = .main) -> Bool {
        guard Updates.hasFeed(bundle), Snapshotter.outputFolder == nil else { return false }
        return !AppLocation.isInApplicationsFolder(AppLocation.original(of: bundle.bundleURL) ?? bundle.bundleURL)
    }

    static func offerAtLaunch() {
        guard shouldOffer() else { return }
        NSApp.activate()
        if question().runModal() == .alertFirstButtonReturn {
            move()
        }
    }

    static func question(bundle: Bundle = .main) -> NSAlert {
        let location = AppLocation.original(of: bundle.bundleURL) ?? bundle.bundleURL
        let alert = NSAlert()
        alert.messageText = "Move Tannin to your Applications folder?"
        alert.informativeText = "\(place(of: location)) It needs to be in Applications to update itself."
        alert.addButton(withTitle: "Move to Applications Folder")
        alert.addButton(withTitle: "Not Now")
        return alert
    }

    /// "Tannin is in your Downloads folder."
    private static func place(of app: URL) -> String {
        let folder = app.deletingLastPathComponent().standardizedFileURL
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        return switch folder.path {
        case home.appending(path: "Downloads").path: "Tannin is in your Downloads folder."
        case home.appending(path: "Desktop").path: "Tannin is on your Desktop."
        case home.appending(path: "Documents").path: "Tannin is in your Documents folder."
        default: "Tannin is in the “\(FileManager.default.displayName(atPath: folder.path))” folder."
        }
    }

    private static func move(bundle: Bundle = .main) {
        do {
            guard let source = AppLocation.original(of: bundle.bundleURL) else { throw LocationUnknown() }
            let move = AppMove(source: source, into: AppMove.applicationsFolder())
            let destination = move.destination.standardizedFileURL.path
            let isOpenThere = NSWorkspace.shared.runningApplications.contains {
                $0.bundleURL?.standardizedFileURL.path == destination
            }
            guard !isOpenThere else { throw AlreadyOpenThere() }

            let placed = try move.place()
            // This copy is still running, so the copy in Applications has to be asked for as a second instance.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: placed.app, configuration: configuration) { _, error in
                let problem = error.map { String(describing: $0.localizedDescription) }
                Task { @MainActor in
                    if let problem {
                        move.undo(placed)
                        report(problem)
                    } else {
                        move.retireSource()
                        NSApp.terminate(nil)
                    }
                }
            }
        } catch {
            report(String(describing: error))
        }
    }

    private static func report(_ problem: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Tannin couldn’t move itself"
        alert.informativeText = "\(problem)\n\nQuit Tannin and drag it to the Applications folder yourself."
        alert.runModal()
    }
}
