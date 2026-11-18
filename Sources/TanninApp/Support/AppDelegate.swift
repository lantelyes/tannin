import AppKit

/// The one thing that has to happen as the app finishes starting, before the user does anything in a window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MoveToApplications.offerAtLaunch()
    }
}
