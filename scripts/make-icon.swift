// Draws Tannin's app icon as a 1024 px PNG: a blue six-sided tile with a play triangle, on a light macOS tile.
// This is option D, "Hex Play", from the design canvas. Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let side = 1024
guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.png>\n".utf8))
    exit(2)
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext else {
    fatalError("could not create a drawing surface")
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ top: UInt32, _ bottom: UInt32) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(top), color(bottom)] as CFArray, locations: [0, 1])!
}

/// A convex polygon grown outward by `radius`, with corners of that radius.
func rounded(_ points: [CGPoint], radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let centre = CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                         y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
    /// The unit vector pointing out of the polygon across the edge from `a` to `b`.
    func normal(_ a: CGPoint, _ b: CGPoint) -> CGVector {
        let length = hypot(b.x - a.x, b.y - a.y)
        var n = CGVector(dx: (b.y - a.y) / length, dy: -(b.x - a.x) / length)
        let middle = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        if n.dx * (middle.x - centre.x) + n.dy * (middle.y - centre.y) < 0 { n = CGVector(dx: -n.dx, dy: -n.dy) }
        return n
    }
    for index in points.indices {
        let previous = points[(index + points.count - 1) % points.count]
        let vertex = points[index]
        let next = points[(index + 1) % points.count]
        let before = normal(previous, vertex)
        let after = normal(vertex, next)
        let start = CGPoint(x: vertex.x + before.dx * radius, y: vertex.y + before.dy * radius)
        if index == 0 { path.move(to: start) } else { path.addLine(to: start) }
        // Turn the short way round the corner.
        let turnsLeft = before.dx * after.dy - before.dy * after.dx > 0
        path.addArc(center: vertex, radius: radius, startAngle: atan2(before.dy, before.dx),
                    endAngle: atan2(after.dy, after.dx), clockwise: !turnsLeft)
    }
    path.closeSubpath()
    return path
}

// Everything below is drawn in the design canvas's coordinates: 1024 units, y pointing down.
context.translateBy(x: 0, y: CGFloat(side))
context.scaleBy(x: 1, y: -1)

// The macOS icon shape: a rounded square inset from the canvas edge, with the soft shadow system icons carry.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tileShape = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: color(0x000000, alpha: 0.28))
context.addPath(tileShape)
context.setFillColor(color(0xFFFFFF))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(tileShape)
context.clip()
context.drawLinearGradient(gradient(0xFFFFFF, 0xE3E8F0), start: CGPoint(x: 0, y: tile.minY), end: CGPoint(x: 0, y: tile.maxY), options: [])
context.restoreGState()

// A hairline so the light tile keeps its edge on a white background.
context.addPath(CGPath(roundedRect: tile.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 184.5, cornerHeight: 184.5, transform: nil))
context.setStrokeColor(color(0x000000, alpha: 0.10))
context.setLineWidth(3)
context.strokePath()

// Six-sided tile: a soft shadow just below it, then the blue itself.
let hexagon: [CGPoint] = [
    CGPoint(x: 512, y: 262), CGPoint(x: 728.5, y: 387), CGPoint(x: 728.5, y: 637),
    CGPoint(x: 512, y: 762), CGPoint(x: 295.5, y: 637), CGPoint(x: 295.5, y: 387),
]
context.addPath(rounded(hexagon.map { CGPoint(x: $0.x, y: $0.y + 16) }, radius: 32))
context.setFillColor(color(0x0A46B4, alpha: 0.20))
context.fillPath()

context.saveGState()
context.addPath(rounded(hexagon, radius: 32))
context.clip()
context.drawLinearGradient(gradient(0x3F9DFF, 0x0A5ADB), start: CGPoint(x: 0, y: 230), end: CGPoint(x: 0, y: 800), options: [])
context.restoreGState()

// Play.
context.addPath(rounded([CGPoint(x: 458, y: 410), CGPoint(x: 634, y: 512), CGPoint(x: 458, y: 614)], radius: 17))
context.setFillColor(color(0xFFFFFF))
context.fillPath()

guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("could not encode PNG") }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
