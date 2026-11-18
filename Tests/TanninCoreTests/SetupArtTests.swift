import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import TanninCore

@Suite struct SetupArtTests {
    private let fm = FileManager.default

    /// A home folder of its own, with a folder beside it to serve pictures from.
    private func makeHome() throws -> (paths: Paths, served: URL) {
        let root = fm.temporaryDirectory.appending(path: "tannin-setup-art-\(UUID().uuidString)")
        let served = root.appending(path: "served")
        try fm.createDirectory(at: served, withIntermediateDirectories: true)
        return (Paths(home: root.appending(path: "home")), served)
    }

    /// A real picture, written by the system.
    private func writePicture(to file: URL, width: Int = 300, height: Int = 450) throws {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.3, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    private func art(_ paths: Paths, serving files: [URL]) -> SetupArt {
        let addresses = files.map(\.absoluteString)
        return SetupArt(paths: paths, sources: { _ in addresses }, protocols: "=file")
    }

    private func leftovers(_ paths: Paths) -> [String] {
        (try? fm.contentsOfDirectory(atPath: paths.setupArt.path)) ?? []
    }

    @Test func theSevenCoversAreFixedAndInOrder() {
        #expect(SetupArt.covers.map(\.appID) == ["1449560", "377160", "1174180", "1151640", "1190460", "782330", "1895880"])
        #expect(SetupArt.covers.map(\.name) == [
            "Metro Exodus", "Fallout 4", "Red Dead Redemption 2", "Horizon Zero Dawn", "Death Stranding", "DOOM Eternal",
            "Ratchet & Clank: Rift Apart",
        ])
    }

    @Test func everyCoverHasItsThreeColours() {
        // The 21 colours as decided on 2026-11-19, so a slip of the keyboard shows up here.
        let decided: [[UInt32]] = [
            [0x50535E, 0xA6A9B1, 0xA4A8B1], [0xCCCBC5, 0xBFC2BB, 0xA5AAA6], [0xC61613, 0x9D2218, 0x3D0E12], [0x434FCE, 0xADA9D7, 0x534841],
            [0x2E3A3B, 0x161918, 0x010102], [0x64443B, 0x8B4C2A, 0x613625], [0x5A4F78, 0x767999, 0x473567],
        ]
        #expect(SetupArt.covers.map { [$0.tint.top, $0.tint.middle, $0.tint.bottom] } == decided)
    }

    @Test func coversAreFetchedFromSteamOverHTTPSOnly() {
        for cover in SetupArt.covers {
            let sources = SetupArt.steamSources(for: cover)
            #expect(sources == [
                "https://shared.steamstatic.com/store_item_assets/steam/apps/\(cover.appID)/library_600x900.jpg",
                "https://cdn.cloudflare.steamstatic.com/steam/apps/\(cover.appID)/library_600x900.jpg",
            ])
        }
    }

    @Test func steamsOwnCopyComesBeforeTannins() throws {
        let (paths, _) = try makeHome()
        defer { try? fm.removeItem(at: paths.home.deletingLastPathComponent()) }
        let cover = SetupArt.covers[0]
        let art = SetupArt(paths: paths)
        #expect(art.local(cover) == nil)
        #expect(art.localFiles() == nil)

        try fm.createDirectory(at: paths.setupArt, withIntermediateDirectories: true)
        try writePicture(to: art.keptCopy(of: cover))
        #expect(art.local(cover) == art.keptCopy(of: cover))

        let steams = paths.steamLibraryCache.appending(path: "\(cover.appID)/library_600x900.jpg")
        try fm.createDirectory(at: steams.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writePicture(to: steams)
        #expect(art.local(cover) == steams)
        // One of seven is not the row.
        #expect(art.localFiles() == nil)
    }

    @Test func aPictureIsFetchedAndKept() throws {
        let (paths, served) = try makeHome()
        defer { try? fm.removeItem(at: paths.home.deletingLastPathComponent()) }
        let picture = served.appending(path: "cover.jpg")
        try writePicture(to: picture)
        let art = art(paths, serving: [picture])
        let cover = SetupArt.covers[2]

        let kept = try art.fetch(cover)
        #expect(kept == art.keptCopy(of: cover))
        #expect(try Data(contentsOf: kept) == Data(contentsOf: picture))
        #expect(leftovers(paths) == ["\(cover.appID).jpg"])
        #expect(art.local(cover) == kept)
    }

    @Test func theSecondSourceIsUsedWhenTheFirstHasNothing() throws {
        let (paths, served) = try makeHome()
        defer { try? fm.removeItem(at: paths.home.deletingLastPathComponent()) }
        let picture = served.appending(path: "cover.jpg")
        try writePicture(to: picture)
        let art = art(paths, serving: [served.appending(path: "gone.jpg"), picture])
        #expect(try art.fetch(SetupArt.covers[0]) == art.keptCopy(of: SetupArt.covers[0]))
    }

    @Test func allSevenAreFetchedTogetherAndThenFoundWithoutFetching() throws {
        let (paths, served) = try makeHome()
        defer { try? fm.removeItem(at: paths.home.deletingLastPathComponent()) }
        let picture = served.appending(path: "cover.jpg")
        try writePicture(to: picture)
        let fetching = art(paths, serving: [picture])
        #expect(fetching.files() == SetupArt.covers.map(fetching.keptCopy))
        // With nowhere to fetch from, the kept copies are enough.
        let offline = art(paths, serving: [])
        #expect(offline.localFiles() == SetupArt.covers.map(offline.keptCopy))
        #expect(offline.files() == offline.localFiles())
    }

    @Test func whatIsNotACoverIsRefusedAndNothingIsLeftBehind() throws {
        let (paths, served) = try makeHome()
        defer { try? fm.removeItem(at: paths.home.deletingLastPathComponent()) }
        let cover = SetupArt.covers[0]

        // Words, as a server's error page would be.
        let words = served.appending(path: "words.jpg")
        try Data("<html>Not found</html>".utf8).write(to: words)
        // A real picture with more after it than is ever kept.
        let large = served.appending(path: "large.jpg")
        try writePicture(to: large)
        let handle = try FileHandle(forWritingTo: large)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(count: Int(SetupArt.largestFile)))
        try handle.close()
        // A picture too small to be a cover.
        let tiny = served.appending(path: "tiny.jpg")
        try writePicture(to: tiny, width: 16, height: 24)
        // Nothing at all.
        let missing = served.appending(path: "missing.jpg")

        for source in [words, large, tiny, missing] {
            #expect(throws: SetupArtError.self, "\(source.lastPathComponent)") { try art(paths, serving: [source]).fetch(cover) }
            #expect(leftovers(paths).isEmpty, "\(source.lastPathComponent)")
        }
        #expect(art(paths, serving: [words]).files() == nil)
        #expect(leftovers(paths).isEmpty)
    }

    @Test func aRefusedFetchLeavesTheEarlierCopyAlone() throws {
        let (paths, served) = try makeHome()
        defer { try? fm.removeItem(at: paths.home.deletingLastPathComponent()) }
        let cover = SetupArt.covers[0]
        let picture = served.appending(path: "cover.jpg")
        try writePicture(to: picture)
        let kept = try art(paths, serving: [picture]).fetch(cover)
        let before = try Data(contentsOf: kept)

        let words = served.appending(path: "words.jpg")
        try Data("no".utf8).write(to: words)
        #expect(throws: SetupArtError.self) { try art(paths, serving: [words]).fetch(cover) }
        #expect(try Data(contentsOf: kept) == before)
        #expect(leftovers(paths) == ["\(cover.appID).jpg"])
    }
}
