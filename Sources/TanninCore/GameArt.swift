import Foundation

/// A game's artwork as Steam has already downloaded it for its own library. Tannin fetches nothing itself.
public struct GameArt: Sendable, Hashable {
    /// Wide banner without the title, used across the top of a game's page.
    public let hero: URL?
    /// Portrait cover with the title on it.
    public let cover: URL?
    /// Small landscape image with the title on it.
    public let header: URL?
    /// The title on a clear background.
    public let logo: URL?

    public static let none = GameArt(hero: nil, cover: nil, header: nil, logo: nil)

    public init(hero: URL?, cover: URL?, header: URL?, logo: URL?) {
        self.hero = hero
        self.cover = cover
        self.header = header
        self.logo = logo
    }

    /// Looks in Steam's library cache folder for this app.
    public init(appID: String, paths: Paths) {
        let fm = FileManager.default
        let folder = paths.steamLibraryCache.appending(path: appID)
        // Steam keeps the images either directly in the app's folder or one folder down, under a name made
        // from the image's hash. The file names themselves are the same either way.
        var files: [String: URL] = [:]
        let top = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        for name in top {
            let url = folder.appending(path: name)
            if name.contains(".") {
                files[name] = url
            } else {
                for inner in ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).sorted() where files[inner] == nil {
                    files[inner] = url.appending(path: inner)
                }
            }
        }
        func first(_ names: String...) -> URL? {
            names.lazy.compactMap { files[$0] }.first
        }
        self.init(
            hero: first("library_hero.jpg", "library_hero.png"),
            cover: first("library_600x900.jpg", "library_600x900.png", "library_capsule.jpg"),
            header: first("library_header.jpg", "header.jpg", "library_header.png"),
            logo: first("logo.png")
        )
    }

    /// The best image for a small square thumbnail.
    public var thumbnail: URL? { cover ?? header ?? hero }
    /// The best image for the top of a game's page.
    public var banner: URL? { hero ?? header }
}
