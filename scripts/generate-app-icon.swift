import AppKit

// Render the SkillDock stack mark at each native icon size, without bitmap upscaling.
guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift scripts/generate-app-icon.swift native/Resources")
}

let fileManager = FileManager.default
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
let iconset = fileManager.temporaryDirectory.appendingPathComponent("SkillDock-\(UUID().uuidString).iconset", isDirectory: true)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: iconset) }

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
    NSPoint(x: x, y: 1024 - y)
}

func renderIcon(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not create icon canvas")
    }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.shouldAntialias = true
    let transform = AffineTransform(scale: CGFloat(pixels) / 1024)
    (transform as NSAffineTransform).concat()

    let tile = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 190, yRadius: 190)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0.015, 0.10, 0.07, alpha: 0.28)
    shadow.shadowBlurRadius = 25
    shadow.shadowOffset = NSSize(width: 0, height: -13)
    shadow.set()
    color(0.43, 0.80, 0.67).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    let surface = NSGradient(starting: color(0.34, 0.74, 0.61), ending: color(0.54, 0.87, 0.75))!
    surface.draw(in: tile, angle: 90)
    let rim = NSBezierPath(roundedRect: NSRect(x: 82, y: 82, width: 860, height: 860), xRadius: 188, yRadius: 188)
    color(0.84, 1.0, 0.92, alpha: 0.26).setStroke()
    rim.lineWidth = 3
    rim.stroke()

    let ink = color(0.065, 0.165, 0.145)
    let top = NSBezierPath()
    top.move(to: point(512, 270))
    top.line(to: point(756, 414))
    top.line(to: point(512, 558))
    top.line(to: point(268, 414))
    top.close()
    ink.setFill()
    ink.setStroke()
    top.fill()
    top.lineWidth = 16
    top.lineJoinStyle = .round
    top.stroke()

    for y: CGFloat in [504, 601] {
        let layer = NSBezierPath()
        layer.move(to: point(268, y))
        layer.line(to: point(512, y + 144))
        layer.line(to: point(756, y))
        layer.lineWidth = 52
        layer.lineCapStyle = .round
        layer.lineJoinStyle = .round
        ink.setStroke()
        layer.stroke()
    }
    context.flushGraphics()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode icon")
    }
    return png
}

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, pixels) in sizes {
    let png = try renderIcon(pixels: pixels)
    try png.write(to: iconset.appendingPathComponent(name))
    if pixels == 1024 { try png.write(to: output.appendingPathComponent("SkillDock.png")) }
}

let package = Process()
package.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
package.arguments = ["-c", "icns", "-o", output.appendingPathComponent("SkillDock.icns").path, iconset.path]
try package.run()
package.waitUntilExit()
guard package.terminationStatus == 0 else { fatalError("Icon packaging failed") }
print("Generated \(output.appendingPathComponent("SkillDock.icns").path)")
