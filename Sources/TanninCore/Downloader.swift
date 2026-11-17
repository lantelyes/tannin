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

    public static func fileSize(_ url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize.map(Int64.init)
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
public struct Downloader: Sendable {
    public let paths: Paths

    public init(paths: Paths = .live) { self.paths = paths }

    public func destination(for pin: Pin) -> URL { paths.downloads.appending(path: pin.name) }

    /// Returns the verified local copy, downloading (and resuming) as needed.
    public func fetch(_ pin: Pin, quiet: Bool = false) throws -> URL {
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
            let result = try Shell.run("/usr/bin/curl", arguments, inherit: !quiet)
            if result.ok {
                downloaded = true
                break
            }
            lastError = "curl exited with status \(result.status) for \(url)."
        }
        guard downloaded else { throw DownloadError.allSourcesFailed(name: pin.name, lastError: lastError) }

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
