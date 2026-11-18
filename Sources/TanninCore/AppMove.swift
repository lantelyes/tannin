import Foundation

public enum AppMoveError: Error, CustomStringConvertible {
    case notAnApp(URL)
    case alreadyThere(URL)

    public var description: String {
        switch self {
        case let .notAnApp(url): "There is no app at \(url.path)."
        case let .alreadyThere(url): "The app is already at \(url.path)."
        }
    }
}

/// Puts a copy of an app into an Applications folder, with a way back until the copy has been opened.
///
/// The order is chosen so that a failure at any point leaves things as they were: the app is copied
/// under a temporary name first, an older copy is only set aside once that copy is complete, and the
/// app that was copied from is left alone until the caller says the new copy works.
public struct AppMove: Sendable {
    /// Sets an older copy aside and says where it went, so it can be put back.
    public typealias Retire = @Sendable (URL) throws -> URL?

    public struct Placed: Sendable {
        public let app: URL
        /// Where the copy that was already there went, if there was one.
        let replaced: URL?
    }

    public let source: URL
    public let folder: URL
    private let retire: Retire

    public init(source: URL, into folder: URL, retire: @escaping Retire = AppMove.moveToTrash) {
        self.source = source
        self.folder = folder
        self.retire = retire
    }

    public var destination: URL { folder.appending(path: source.lastPathComponent) }

    /// `/Applications` when this account may write there, otherwise the Applications folder in the home folder.
    public static func applicationsFolder(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let shared = URL(fileURLWithPath: "/Applications")
        return FileManager.default.isWritableFile(atPath: shared.path) ? shared : home.appending(path: "Applications")
    }

    public static let moveToTrash: Retire = { url in
        var trashed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        return trashed as URL?
    }

    /// Copies the app into the folder and clears the mark macOS puts on downloads, which the copy would
    /// otherwise carry with it. An older copy in the folder is set aside.
    public func place() throws -> Placed {
        let files = FileManager.default
        guard source.pathExtension == "app", files.fileExists(atPath: source.path) else {
            throw AppMoveError.notAnApp(source)
        }
        guard source.standardizedFileURL.path != destination.standardizedFileURL.path else {
            throw AppMoveError.alreadyThere(destination)
        }
        try files.createDirectory(at: folder, withIntermediateDirectories: true)

        let staging = folder.appending(path: ".\(source.lastPathComponent).moving-\(UUID().uuidString)")
        var replaced: URL?
        do {
            try files.copyItem(at: source, to: staging)
            _ = try? Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staging.path])
            if files.fileExists(atPath: destination.path) {
                replaced = try retire(destination)
            }
            try files.moveItem(at: staging, to: destination)
        } catch {
            try? files.removeItem(at: staging)
            if let replaced, !files.fileExists(atPath: destination.path) {
                try? files.moveItem(at: replaced, to: destination)
            }
            throw error
        }
        return Placed(app: destination, replaced: replaced)
    }

    /// Takes the new copy away again and puts back the one it replaced.
    public func undo(_ placed: Placed) {
        let files = FileManager.default
        try? files.removeItem(at: placed.app)
        if let replaced = placed.replaced {
            try? files.moveItem(at: replaced, to: placed.app)
        }
    }

    /// Sets aside the app that was copied from, once the new copy is known to open.
    public func retireSource() {
        _ = try? retire(source)
    }
}
