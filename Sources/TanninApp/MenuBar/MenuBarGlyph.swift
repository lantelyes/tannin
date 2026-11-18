import AppKit

/// The menu bar mark: the icon's six-sided tile with the play triangle cut out of it.
/// A template image, so macOS colours it for a light or dark menu bar.
@MainActor
enum MenuBarGlyph {
    static let image: NSImage = {
        let size: CGFloat = 18
        // Drawn on a 16-unit square with y pointing down, as on the design canvas.
        let unit = size / 16
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * unit, y: y * unit) }

        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            let path = NSBezierPath()
            path.move(to: point(8, 1.1))
            for (x, y) in [(14, 4.55), (14, 11.45), (8, 14.9), (2, 11.45), (2, 4.55)] as [(CGFloat, CGFloat)] {
                path.line(to: point(x, y))
            }
            path.close()
            path.move(to: point(6.5, 5.5))
            path.line(to: point(6.5, 10.5))
            path.line(to: point(10.9, 8))
            path.close()
            // Even-odd, so the triangle is a hole in the tile.
            path.windingRule = .evenOdd
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
