import Foundation
import ImageIO
import Synchronization

public enum SetupArtError: Error, CustomStringConvertible {
    case notFetched(name: String, lastError: String)

    public var description: String {
        switch self {
        case let .notFetched(name, lastError): "Could not fetch the cover of \(name). \(lastError)"
        }
    }
}

/// The seven covers across the top of the setup window: always these, in this order, for everyone.
///
/// Tannin carries none of the pictures. Each is looked for in Steam's own library cache on this Mac, then in the
/// copy Tannin kept from last time, and only then fetched from Steam's public servers and kept. They are the one
/// download that is not pinned to a hash: when Valve replaces a cover, the new one is shown.
public struct SetupArt: Sendable {
    /// Three colours of a cover, from its top, its middle and its bottom, each as 0xRRGGBB. They fill the cover's
    /// place while the picture is on its way.
    ///
    /// Taken once from each picture: the cover reduced to two columns of three pixels, and the columns averaged.
    /// They are changed only with a Tannin update, so after Valve replaces a cover its tint is a little off.
    public struct Tint: Sendable, Equatable {
        public let top: UInt32
        public let middle: UInt32
        public let bottom: UInt32

        public init(_ top: UInt32, _ middle: UInt32, _ bottom: UInt32) {
            self.top = top
            self.middle = middle
            self.bottom = bottom
        }
    }

    public struct Cover: Sendable, Equatable, Identifiable {
        public let appID: String
        public let name: String
        public let tint: Tint

        public var id: String { appID }
    }

    /// Left to right. The row is wider than the window, so the first and the last are cropped by it.
    public static let covers: [Cover] = [
        Cover(appID: "1449560", name: "Metro Exodus", tint: Tint(0x50535E, 0xA6A9B1, 0xA4A8B1)),
        Cover(appID: "377160", name: "Fallout 4", tint: Tint(0xCCCBC5, 0xBFC2BB, 0xA5AAA6)),
        Cover(appID: "1174180", name: "Red Dead Redemption 2", tint: Tint(0xC61613, 0x9D2218, 0x3D0E12)),
        Cover(appID: "1151640", name: "Horizon Zero Dawn", tint: Tint(0x434FCE, 0xADA9D7, 0x534841)),
        Cover(appID: "1190460", name: "Death Stranding", tint: Tint(0x2E3A3B, 0x161918, 0x010102)),
        Cover(appID: "782330", name: "DOOM Eternal", tint: Tint(0x64443B, 0x8B4C2A, 0x613625)),
        Cover(appID: "1895880", name: "Ratchet & Clank: Rift Apart", tint: Tint(0x5A4F78, 0x767999, 0x473567)),
    ]

    /// Where Steam serves a cover from, the first tried first. All seven were there on 2026-11-19.
    public static func steamSources(for cover: Cover) -> [String] {
        [
            "https://shared.steamstatic.com/store_item_assets/steam/apps/\(cover.appID)/library_600x900.jpg",
            "https://cdn.cloudflare.steamstatic.com/steam/apps/\(cover.appID)/library_600x900.jpg",
        ]
    }

    /// Nothing larger is kept. The seven are between 40 and 110 KB each.
    public static let largestFile: Int64 = 2 * 1024 * 1024

    public let paths: Paths
    private let sources: @Sendable (Cover) -> [String]
    /// What curl may fetch from, in its own notation. Only the tests use anything but https.
    private let protocols: String

    public init(paths: Paths = .live) {
        self.init(paths: paths, sources: Self.steamSources, protocols: "=https")
    }

    init(paths: Paths, sources: @escaping @Sendable (Cover) -> [String], protocols: String) {
        self.paths = paths
        self.sources = sources
        self.protocols = protocols
    }

    // MARK: On this Mac

    /// The copy Tannin keeps once it has fetched a cover.
    public func keptCopy(of cover: Cover) -> URL {
        paths.setupArt.appending(path: "\(cover.appID).jpg")
    }

    /// The cover as it is on this Mac already: Steam's own copy when Steam has one, otherwise Tannin's.
    public func local(_ cover: Cover) -> URL? {
        if let steams = GameArt(appID: cover.appID, paths: paths).cover { return steams }
        let kept = keptCopy(of: cover)
        return FileManager.default.fileExists(atPath: kept.path) ? kept : nil
    }

    /// All seven, in order, when every one of them is on this Mac. Nothing is fetched.
    public func localFiles() -> [URL]? {
        let files = Self.covers.compactMap(local)
        return files.count == Self.covers.count ? files : nil
    }

    // MARK: Fetching

    /// All seven, in order, fetching those this Mac does not have, several at once. Nil when any could not be had;
    /// the ones that did arrive are kept for the next try.
    public func files() -> [URL]? {
        let covers = Self.covers
        let found = Mutex<[Int: URL]>([:])
        DispatchQueue.concurrentPerform(iterations: covers.count) { index in
            guard let file = local(covers[index]) ?? (try? fetch(covers[index])) else { return }
            found.withLock { $0[index] = file }
        }
        let files = found.withLock { byIndex in covers.indices.compactMap { byIndex[$0] } }
        return files.count == covers.count ? files : nil
    }

    /// Fetches one cover and keeps it. A file is only kept when it is a picture of a sensible size; anything else
    /// is removed.
    @discardableResult
    public func fetch(_ cover: Cover) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: paths.setupArt, withIntermediateDirectories: true)
        let final = keptCopy(of: cover)
        let partial = final.appendingPathExtension("part")
        defer { try? fm.removeItem(at: partial) }

        var lastError = "No source was tried."
        for source in sources(cover) {
            try? fm.removeItem(at: partial)
            let result = try Shell.run("/usr/bin/curl", [
                "--fail", "--silent", "--show-error", "--location",
                "--proto", protocols, "--proto-redir", "=https",
                "--max-filesize", String(Self.largestFile),
                "--connect-timeout", "10", "--max-time", "30",
                "--output", partial.path, source,
            ])
            guard result.ok else {
                lastError = "curl exited with status \(result.status) for \(source)."
                continue
            }
            guard Self.isCover(partial) else {
                lastError = "What \(source) sent is not a cover picture."
                continue
            }
            try? fm.removeItem(at: final)
            try fm.moveItem(at: partial, to: final)
            return final
        }
        throw SetupArtError.notFetched(name: cover.name, lastError: lastError)
    }

    /// Whether a file is a picture a cover could be: small enough to keep, and read by the system as an image
    /// between 100 and 4096 pixels each way.
    static func isCover(_ file: URL) -> Bool {
        guard let size = Hashing.fileSize(file), size > 0, size <= largestFile,
              let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return false }
        return (100...4096).contains(width) && (100...4096).contains(height)
    }
}
