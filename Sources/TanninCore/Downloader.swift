import CryptoKit
import Foundation

public enum Hashing {
    /// SHA-256 of a file, streamed so large downloads don't have to fit in memory.
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The file's size as it is on disk right now.
    ///
    /// Asked of the file system each time. `URL.resourceValues` remembers its answer on the URL value, so a download
    /// watched through one URL appeared to stop growing, and a finished download was then judged too short.
    public static func fileSize(_ url: URL) -> Int64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value
    }
}

public enum DownloadError: Error, CustomStringConvertible {
    case allSourcesFailed(name: String, lastError: String)
    case wrongSize(name: String, expected: Int64, actual: Int64)
    case wrongHash(name: String, expected: String, actual: String)

    public var description: String {
        switch self {
        case let .allSourcesFailed(name, lastError):
            return "Could not download \(name). \(lastError)"
        case let .wrongSize(name, expected, actual):
            return "\(name) is \(actual) bytes, expected \(expected). The partial file was removed."
        case let .wrongHash(name, expected, actual):
            return "\(name) does not match its pinned SHA-256 (expected \(expected), got \(actual)). The file was removed."
        }
    }
}

/// Downloads pinned files. A file is only ever returned after its SHA-256 matches the pin.
/// How far a download has got.
public struct DownloadProgress: Sendable, Equatable {
    public let name: String
    public let received: Int64
    /// Nil when the pin does not state a size.
    public let total: Int64?
    /// True once the bytes are all here and the file is being checked against its hash.
    public let isVerifying: Bool

    public init(name: String, received: Int64, total: Int64?, isVerifying: Bool) {
        self.name = name
        self.received = received
        self.total = total
        self.isVerifying = isVerifying
    }

    public var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(1, Double(received) / Double(total))
    }
}

/// What a long step reports back while it works, and how it is stopped.
public struct WorkContext: Sendable {
    public var quiet: Bool
    public var progress: (@Sendable (DownloadProgress) -> Void)?
    public var cancellation: Cancellation?

    public init(quiet: Bool = false, progress: (@Sendable (DownloadProgress) -> Void)? = nil, cancellation: Cancellation? = nil) {
        self.quiet = quiet
        self.progress = progress
        self.cancellation = cancellation
    }

    /// For the command line: curl draws its own progress bar.
    public static let terminal = WorkContext()
}

public struct Downloader: Sendable {
    public let paths: Paths

    public init(paths: Paths = .live) { self.paths = paths }

    public func destination(for pin: Pin) -> URL { paths.downloads.appending(path: pin.name) }

    /// Returns the verified local copy, downloading (and resuming) as needed.
    public func fetch(_ pin: Pin, quiet: Bool = false) throws -> URL {
        try fetch(pin, WorkContext(quiet: quiet))
    }

    /// Returns the verified local copy, downloading (and resuming) as needed.
    ///
    /// With a progress callback, curl runs silently and the size of the partial file is reported a few times a
    /// second. Cancelling stops curl and throws `Cancelled`; the partial file stays, so the next call resumes it.
    public func fetch(_ pin: Pin, _ context: WorkContext) throws -> URL {
        let quiet = context.quiet || context.progress != nil
        let fm = FileManager.default
        try fm.createDirectory(at: paths.downloads, withIntermediateDirectories: true)
        let final = destination(for: pin)
        let partial = final.appendingPathExtension("part")

        if fm.fileExists(atPath: final.path) {
            if try Hashing.sha256(of: final) == pin.sha256 { return final }
            try fm.removeItem(at: final)
        }

        var lastError = "No source was tried."
        var downloaded = false
        for url in pin.urls {
            var arguments = ["--location", "--fail", "--retry", "3", "--continue-at", "-", "--output", partial.path]
            arguments.append(quiet ? "--silent" : "--progress-bar")
            arguments.append("--show-error")
            arguments.append(url)
            let watcher = context.progress.map { ProgressWatcher(file: partial, pin: pin, report: $0) }
            defer { watcher?.stop() }
            let result = try Shell.run("/usr/bin/curl", arguments, inherit: !quiet, cancellation: context.cancellation)
            if result.ok {
                downloaded = true
                break
            }
            lastError = "curl exited with status \(result.status) for \(url)."
        }
        guard downloaded else { throw DownloadError.allSourcesFailed(name: pin.name, lastError: lastError) }

        let size = Hashing.fileSize(partial) ?? 0
        context.progress?(DownloadProgress(name: pin.name, received: size, total: pin.size, isVerifying: true))
        try verify(partial, against: pin)
        try fm.moveItem(at: partial, to: final)
        return final
    }

    /// Checks size and hash; deletes the file and throws when either is wrong.
    public func verify(_ file: URL, against pin: Pin) throws {
        if let expected = pin.size, let actual = Hashing.fileSize(file), actual != expected {
            try? FileManager.default.removeItem(at: file)
            throw DownloadError.wrongSize(name: pin.name, expected: expected, actual: actual)
        }
        let actual = try Hashing.sha256(of: file)
        guard actual == pin.sha256 else {
            try? FileManager.default.removeItem(at: file)
            throw DownloadError.wrongHash(name: pin.name, expected: pin.sha256, actual: actual)
        }
    }
}

/// Reports the growing size of a partial download until stopped.
private final class ProgressWatcher: @unchecked Sendable {
    private let timer: DispatchSourceTimer

    init(file: URL, pin: Pin, report: @escaping @Sendable (DownloadProgress) -> Void) {
        timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: .milliseconds(250))
        timer.setEventHandler {
            let received = Hashing.fileSize(file) ?? 0
            report(DownloadProgress(name: pin.name, received: received, total: pin.size, isVerifying: false))
        }
        timer.resume()
    }

    func stop() {
        timer.cancel()
    }
}
