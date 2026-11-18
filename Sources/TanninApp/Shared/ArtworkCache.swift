import CoreGraphics
import Foundation
import ImageIO

/// Loads game artwork from Steam's cache folder, scaled down to the size it is shown at, off the main thread.
enum ArtworkCache {
    private final class Box: @unchecked Sendable {
        let cache = NSCache<NSString, CGImage>()
    }

    private static let box = Box()

    /// - Parameter pixels: the longest side wanted, in pixels.
    static func image(at url: URL, pixels: Int) async -> CGImage? {
        let key = "\(url.path)#\(pixels)" as NSString
        if let cached = box.cache.object(forKey: key) { return cached }
        let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
        if let image { box.cache.setObject(image, forKey: key) }
        return image
    }
}
