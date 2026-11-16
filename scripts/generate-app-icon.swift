import AppKit

// Render the SkillDock card-stack mark at each native icon size, without bitmap upscaling.
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

    // Deep indigo tile with a soft teal glow behind the stack.
    let tile = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 190, yRadius: 190)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0.02, 0.03, 0.12, alpha: 0.35)
    shadow.shadowBlurRadius = 25
    shadow.shadowOffset = NSSize(width: 0, height: -13)
    shadow.set()
    color(0.10, 0.12, 0.32).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: color(0.05, 0.06, 0.18), ending: color(0.20, 0.20, 0.52))!.draw(in: tile, angle: 90)
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    NSGradient(colors: [color(0.30, 0.95, 0.80, alpha: 0.42), color(0.30, 0.95, 0.80, alpha: 0)])!
        .draw(fromCenter: point(512, 470), radius: 0, toCenter: point(512, 470), radius: 420, options: [])
    NSGraphicsContext.restoreGraphicsState()
    color(1, 1, 1, alpha: 0.14).setStroke()
    let rim = NSBezierPath(roundedRect: NSRect(x: 82, y: 82, width: 860, height: 860), xRadius: 188, yRadius: 188)
    rim.lineWidth = 3
    rim.stroke()

    // Three isometric skill cards, each with a lit top face and two shaded sides.
    func polygon(_ points: [NSPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: points[0])
        points.dropFirst().forEach { path.line(to: $0) }
        path.close()
        path.lineJoinStyle = .round
        path.lineWidth = 22
        return path
    }
    func slab(centerY cy: CGFloat, top: NSColor, bottom: NSColor, left: NSColor, right: NSColor) {
        let w: CGFloat = 228, h: CGFloat = 132, t: CGFloat = 30
        let faces: [(NSBezierPath, NSColor)] = [
            (polygon([point(512 - w, cy), point(512, cy + h), point(512, cy + h + t), point(512 - w, cy + t)]), left),
            (polygon([point(512, cy + h), point(512 + w, cy), point(512 + w, cy + t), point(512, cy + h + t)]), right)
        ]
        NSGraphicsContext.saveGraphicsState()
        let drop = NSShadow()
        drop.shadowColor = color(0.0, 0.02, 0.08, alpha: 0.45)
        drop.shadowBlurRadius = 30
        drop.shadowOffset = NSSize(width: 0, height: -18)
        drop.set()
        for (path, fill) in faces { fill.setFill(); fill.setStroke(); path.fill(); path.stroke() }
        NSGraphicsContext.restoreGraphicsState()
        let face = polygon([point(512, cy - h), point(512 + w, cy), point(512, cy + h), point(512 - w, cy)])
        top.setStroke()
        face.stroke()
        NSGradient(starting: bottom, ending: top)!.draw(in: face, angle: 90)
        NSGradient(starting: bottom, ending: top)!.draw(in: face, angle: 90)
        top.setStroke()
        face.stroke()
    }
    slab(centerY: 652, top: color(1.0, 0.62, 0.48), bottom: color(0.98, 0.44, 0.38),
         left: color(0.80, 0.30, 0.30), right: color(0.66, 0.22, 0.27))
    slab(centerY: 548, top: color(0.52, 0.80, 1.0), bottom: color(0.33, 0.62, 0.98),
         left: color(0.22, 0.45, 0.82), right: color(0.17, 0.34, 0.68))
    slab(centerY: 444, top: color(0.62, 1.0, 0.82), bottom: color(0.34, 0.90, 0.70),
         left: color(0.18, 0.66, 0.54), right: color(0.12, 0.52, 0.45))

    // A sparkle resting on the top card marks it as a skill.
    let sparkle = NSBezierPath()
    let sx: CGFloat = 512, sy: CGFloat = 430, r: CGFloat = 78, k: CGFloat = 15
    sparkle.move(to: point(sx, sy - r))
    sparkle.curve(to: point(sx + r, sy), controlPoint1: point(sx + k, sy - k), controlPoint2: point(sx + k, sy - k))
    sparkle.curve(to: point(sx, sy + r), controlPoint1: point(sx + k, sy + k), controlPoint2: point(sx + k, sy + k))
    sparkle.curve(to: point(sx - r, sy), controlPoint1: point(sx - k, sy + k), controlPoint2: point(sx - k, sy + k))
    sparkle.curve(to: point(sx, sy - r), controlPoint1: point(sx - k, sy - k), controlPoint2: point(sx - k, sy - k))
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = color(1, 1, 1, alpha: 0.85)
    glow.shadowBlurRadius = 26
    glow.shadowOffset = .zero
    glow.set()
    color(1, 1, 1).setFill()
    sparkle.fill()
    NSGraphicsContext.restoreGraphicsState()
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
