import AppKit

// The artwork is full bleed. Apply the native icon silhouette and transparent
// margins here so every representation has the same sharp, clean boundary.
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources/Icon/AppIcon-Artwork.png")
guard let artwork = NSImage(contentsOf: source) else { fatalError("Missing icon artwork: \(source.path)") }
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.imageInterpolation = .high
        let transform = AffineTransform(scale: CGFloat(pixels) / 1024)
        (transform as NSAffineTransform).concat()
        let rect = NSRect(x: 74, y: 74, width: 876, height: 876)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 194, yRadius: 194)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
        shadow.shadowBlurRadius = 18; shadow.shadowOffset = NSSize(width: 0, height: -6); shadow.set()
        NSColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1).setFill(); shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        shape.addClip()
        artwork.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
        let rim = NSBezierPath(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), xRadius: 192.5, yRadius: 192.5)
        NSColor.white.withAlphaComponent(0.12).setStroke(); rim.lineWidth = 3; rim.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(name))
    }
}
