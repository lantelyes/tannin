import CoreGraphics
import Foundation
import ImageIO

/// Loads game artwork from files on this Mac, scaled down to the size it is shown at.
enum ArtworkCache {
    private final class Box: @unchecked Sendable {
        let cache = NSCache<NSString, CGImage>()
    }

    private static let box = Box()

    private static func key(_ url: URL, _ pixels: Int) -> NSString { "\(url.path)#\(pixels)" as NSString }

    /// Off the main thread.
    /// - Parameter pixels: the longest side wanted, in pixels.
    static func image(at url: URL, pixels: Int) async -> CGImage? {
        if let cached = box.cache.object(forKey: key(url, pixels)) { return cached }
        return await Task.detached(priority: .userInitiated) { imageNow(at: url, pixels: pixels) }.value
    }

    /// On the calling thread, for the few pictures that have to be there before a window is first drawn.
    static func imageNow(at url: URL, pixels: Int) -> CGImage? {
        let key = key(url, pixels)
        if let cached = box.cache.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        box.cache.setObject(image, forKey: key)
        return image
    }
}
