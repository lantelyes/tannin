import Foundation

/// Where an app really is on disk.
///
/// macOS runs a freshly downloaded app from a hidden, read-only copy until the app has been moved in
/// Finder ("App Translocation"). The path the app sees for itself is then not the one the user sees.
public enum AppLocation {
    public static func isTranslocated(_ bundle: URL) -> Bool {
        bundle.path.contains("/AppTranslocation/")
    }

    /// The app's place as the user sees it, or nil when macOS will not say where a hidden copy came from.
    public static func original(of bundle: URL) -> URL? {
        guard isTranslocated(bundle) else { return bundle }
        // The function is in the Security framework but not in its public headers, so it is looked up
        // by name when needed. The public-domain LetsMove helper has done the same since macOS 10.12.
        guard let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY) else { return nil }
        defer { dlclose(security) }
        guard let symbol = dlsym(security, "SecTranslocateCreateOriginalPathForURL") else { return nil }
        typealias CreateOriginalPath = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        let createOriginalPath = unsafeBitCast(symbol, to: CreateOriginalPath.self)
        return createOriginalPath(bundle as CFURL, nil)?.takeRetainedValue() as URL?
    }

    public static func isInApplicationsFolder(_ bundle: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let folder = bundle.deletingLastPathComponent().standardizedFileURL.path
        return folder == "/Applications" || folder == home.appending(path: "Applications").standardizedFileURL.path
    }
}
