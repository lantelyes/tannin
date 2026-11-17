// Draws Tannin's app icon, the polyphenol ring in amber on iron-gall ink, as a 1024 px PNG.
// Usage: swift scripts/make-icon.swift <output.png>
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

func color(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

// The macOS icon shape: a rounded square inset from the canvas edge.
let inset: CGFloat = 100
let tile = CGRect(x: inset, y: inset, width: CGFloat(side) - 2 * inset, height: CGFloat(side) - 2 * inset)
let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

context.saveGState()
context.addPath(shape)
context.clip()
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0x2B3449), color(0x141925)] as CFArray, locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
context.restoreGState()

// The glyph is specified on a 100-unit square with y pointing down, as in the design canvas.
let unit = tile.width / 100
func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: tile.minX + x * unit, y: tile.maxY - y * unit)
}

let amber = color(0xE0A552)
let pale = color(0xF3DDB8)
context.setLineJoin(.round)
context.setLineCap(.round)

// Six-sided ring.
let hexagon: [(CGFloat, CGFloat)] = [(50, 23), (73.4, 36.5), (73.4, 63.5), (50, 77), (26.6, 63.5), (26.6, 36.5)]
context.setStrokeColor(amber)
context.setLineWidth(6.5 * unit)
context.move(to: point(hexagon[0].0, hexagon[0].1))
for vertex in hexagon.dropFirst() { context.addLine(to: point(vertex.0, vertex.1)) }
context.closePath()
context.strokePath()

// Two side groups that make it read as a molecule.
for (from, to, dot) in [((73.4, 36.5), (82.0, 31.5), (84.0, 30.3)), ((26.6, 63.5), (18.0, 68.5), (16.0, 69.7))] as [((CGFloat, CGFloat), (CGFloat, CGFloat), (CGFloat, CGFloat))] {
    context.move(to: point(from.0, from.1))
    context.addLine(to: point(to.0, to.1))
    context.strokePath()
    let centre = point(dot.0, dot.1)
    context.setFillColor(amber)
    context.fillEllipse(in: CGRect(x: centre.x - 5.2 * unit, y: centre.y - 5.2 * unit, width: 10.4 * unit, height: 10.4 * unit))
}

// Inner ring.
context.setStrokeColor(pale)
context.setLineWidth(4 * unit)
let centre = point(50, 50)
context.strokeEllipse(in: CGRect(x: centre.x - 11.5 * unit, y: centre.y - 11.5 * unit, width: 23 * unit, height: 23 * unit))

guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("could not encode PNG") }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
