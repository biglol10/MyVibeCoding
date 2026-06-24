import AppKit
import Foundation

struct IconOutput {
    let filename: String
    let pixels: Int
}

let outputs: [IconOutput] = [
    IconOutput(filename: "icon_16x16.png", pixels: 16),
    IconOutput(filename: "icon_16x16@2x.png", pixels: 32),
    IconOutput(filename: "icon_32x32.png", pixels: 32),
    IconOutput(filename: "icon_32x32@2x.png", pixels: 64),
    IconOutput(filename: "icon_128x128.png", pixels: 128),
    IconOutput(filename: "icon_128x128@2x.png", pixels: 256),
    IconOutput(filename: "icon_256x256.png", pixels: 256),
    IconOutput(filename: "icon_256x256@2x.png", pixels: 512),
    IconOutput(filename: "icon_512x512.png", pixels: 512),
    IconOutput(filename: "icon_512x512@2x.png", pixels: 1_024)
]

let fileManager = FileManager.default
let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let resourcesURL = rootURL.appendingPathComponent("Resources", isDirectory: true)
let iconsetURL = resourcesURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let icnsURL = resourcesURL.appendingPathComponent("AppIcon.icns")

try? fileManager.removeItem(at: iconsetURL)
try? fileManager.removeItem(at: icnsURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for output in outputs {
    let bitmap = makeIcon(pixelSize: output.pixels)
    try writePNG(bitmap, to: iconsetURL.appendingPathComponent(output.filename))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()

guard iconutil.terminationStatus == 0 else {
    throw NSError(
        domain: "CaptureStudioIconGenerator",
        code: Int(iconutil.terminationStatus),
        userInfo: [NSLocalizedDescriptionKey: "iconutil failed to create AppIcon.icns"]
    )
}

print("Generated \(icnsURL.path)")

private func makeIcon(pixelSize: Int) -> NSBitmapImageRep {
    let side = CGFloat(pixelSize)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Could not create bitmap context")
    }

    bitmap.size = NSSize(width: side, height: side)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    defer { NSGraphicsContext.restoreGraphicsState() }

    guard let context = NSGraphicsContext.current?.cgContext else {
        fatalError("Could not access graphics context")
    }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: side, height: side).fill()

    let tileRect = NSRect(
        x: side * 0.075,
        y: side * 0.075,
        width: side * 0.85,
        height: side * 0.85
    )
    let tilePath = NSBezierPath(
        roundedRect: tileRect,
        xRadius: side * 0.19,
        yRadius: side * 0.19
    )

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = side * 0.035
    shadow.shadowOffset = NSSize(width: 0, height: -side * 0.018)
    shadow.set()
    color(10, 14, 28).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [
        color(17, 20, 54),
        color(54, 49, 178),
        color(10, 148, 214),
        color(22, 221, 196)
    ])?.draw(in: tilePath, angle: 42)

    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    let prismPath = NSBezierPath()
    prismPath.move(to: NSPoint(x: side * 0.10, y: side * 0.74))
    prismPath.curve(
        to: NSPoint(x: side * 0.90, y: side * 0.40),
        controlPoint1: NSPoint(x: side * 0.36, y: side * 0.98),
        controlPoint2: NSPoint(x: side * 0.70, y: side * 0.77)
    )
    prismPath.line(to: NSPoint(x: side * 0.98, y: side * 0.55))
    prismPath.curve(
        to: NSPoint(x: side * 0.15, y: side * 0.89),
        controlPoint1: NSPoint(x: side * 0.72, y: side * 0.90),
        controlPoint2: NSPoint(x: side * 0.38, y: side * 1.04)
    )
    prismPath.close()
    NSGradient(colors: [
        color(255, 70, 188, 0.34),
        color(122, 92, 255, 0.16),
        color(41, 246, 220, 0.10)
    ])?.draw(in: prismPath, angle: 24)

    NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.34),
        NSColor.white.withAlphaComponent(0.06),
        NSColor.clear
    ])?.draw(
        in: NSRect(x: side * 0.13, y: side * 0.58, width: side * 0.72, height: side * 0.28),
        angle: -18
    )

    let glowPath = NSBezierPath(ovalIn: NSRect(x: side * 0.15, y: side * 0.07, width: side * 0.82, height: side * 0.72))
    NSGradient(colors: [
        color(54, 235, 216, 0.30),
        color(255, 88, 195, 0.08),
        NSColor.clear
    ])?.draw(in: glowPath, angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    let glassRect = NSRect(x: side * 0.285, y: side * 0.345, width: side * 0.43, height: side * 0.31)
    let glassPath = NSBezierPath(
        roundedRect: glassRect,
        xRadius: side * 0.075,
        yRadius: side * 0.075
    )
    color(5, 12, 28, 0.34).setFill()
    glassPath.fill()
    NSGradient(colors: [
        color(152, 242, 255, 0.90),
        color(79, 142, 255, 0.84),
        color(117, 71, 238, 0.82)
    ])?.draw(in: glassPath, angle: 55)

    color(255, 255, 255, 0.52).setStroke()
    glassPath.lineWidth = max(1, side * 0.013)
    glassPath.stroke()

    let highlight = NSBezierPath(
        roundedRect: NSRect(x: side * 0.34, y: side * 0.555, width: side * 0.24, height: side * 0.045),
        xRadius: side * 0.02,
        yRadius: side * 0.02
    )
    color(255, 255, 255, 0.48).setFill()
    highlight.fill()

    drawCaptureCorners(side: side)
    drawLensDetail(side: side)
    drawRecordDot(side: side)

    return bitmap
}

private func drawCaptureCorners(side: CGFloat) {
    let rect = NSRect(x: side * 0.225, y: side * 0.245, width: side * 0.55, height: side * 0.515)
    let length = side * 0.145
    let strokeWidth = max(1.5, side * 0.038)

    color(246, 253, 255, 0.98).setStroke()

    let corners: [[NSPoint]] = [
        [
            NSPoint(x: rect.minX + length, y: rect.maxY),
            NSPoint(x: rect.minX, y: rect.maxY),
            NSPoint(x: rect.minX, y: rect.maxY - length)
        ],
        [
            NSPoint(x: rect.maxX - length, y: rect.maxY),
            NSPoint(x: rect.maxX, y: rect.maxY),
            NSPoint(x: rect.maxX, y: rect.maxY - length)
        ],
        [
            NSPoint(x: rect.minX, y: rect.minY + length),
            NSPoint(x: rect.minX, y: rect.minY),
            NSPoint(x: rect.minX + length, y: rect.minY)
        ],
        [
            NSPoint(x: rect.maxX, y: rect.minY + length),
            NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.maxX - length, y: rect.minY)
        ]
    ]

    for corner in corners {
        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = strokeWidth
        path.move(to: corner[0])
        path.line(to: corner[1])
        path.line(to: corner[2])
        path.stroke()
    }
}

private func drawLensDetail(side: CGFloat) {
    let center = NSPoint(x: side * 0.50, y: side * 0.50)
    let outerRect = NSRect(x: center.x - side * 0.078, y: center.y - side * 0.078, width: side * 0.156, height: side * 0.156)
    let innerRect = NSRect(x: center.x - side * 0.041, y: center.y - side * 0.041, width: side * 0.082, height: side * 0.082)

    color(255, 255, 255, 0.48).setStroke()
    let outer = NSBezierPath(ovalIn: outerRect)
    outer.lineWidth = max(1, side * 0.012)
    outer.stroke()

    color(255, 255, 255, 0.82).setFill()
    NSBezierPath(ovalIn: innerRect).fill()
}

private func drawRecordDot(side: CGFloat) {
    let center = NSPoint(x: side * 0.688, y: side * 0.307)
    let glowRect = NSRect(x: center.x - side * 0.135, y: center.y - side * 0.135, width: side * 0.27, height: side * 0.27)
    let dotRect = NSRect(x: center.x - side * 0.092, y: center.y - side * 0.092, width: side * 0.184, height: side * 0.184)
    let shineRect = NSRect(x: center.x - side * 0.035, y: center.y + side * 0.026, width: side * 0.052, height: side * 0.034)

    NSGradient(colors: [
        color(255, 94, 109, 0.58),
        color(255, 75, 183, 0.14),
        NSColor.clear
    ])?.draw(in: NSBezierPath(ovalIn: glowRect), angle: 90)

    NSGradient(colors: [
        color(255, 142, 119),
        color(255, 52, 82),
        color(187, 24, 83)
    ])?.draw(in: NSBezierPath(ovalIn: dotRect), angle: 52)

    color(255, 255, 255, 0.62).setFill()
    NSBezierPath(ovalIn: shineRect).fill()
}

private func writePNG(_ imageRep: NSBitmapImageRep, to url: URL) throws {
    guard
        let pngData = imageRep.representation(using: .png, properties: [.compressionFactor: 0.95])
    else {
        throw NSError(
            domain: "CaptureStudioIconGenerator",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG for \(url.lastPathComponent)"]
        )
    }

    try pngData.write(to: url)
}

private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}
