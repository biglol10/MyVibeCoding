#!/usr/bin/env swift
import AppKit
import Foundation

let fileManager = FileManager.default
let scriptPath = CommandLine.arguments[0].hasPrefix("/")
    ? CommandLine.arguments[0]
    : URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent(CommandLine.arguments[0]).path
let rootURL = URL(fileURLWithPath: scriptPath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let resourcesURL = rootURL.appendingPathComponent("Sources/MyMacFinder/Resources", isDirectory: true)
let iconsetURL = resourcesURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let previewURL = resourcesURL.appendingPathComponent("AppIcon.png")
let icnsURL = resourcesURL.appendingPathComponent("AppIcon.icns")

func color(_ hex: UInt32, alpha: CGFloat = 1.0) -> NSColor {
    let red = CGFloat((hex >> 16) & 0xff) / 255.0
    let green = CGFloat((hex >> 8) & 0xff) / 255.0
    let blue = CGFloat(hex & 0xff) / 255.0
    return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

func topRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
    NSRect(x: x, y: 1024 - y - height, width: width, height: height)
}

func fillGradient(_ path: NSBezierPath, colors: [NSColor], angle: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(colors: colors)?.draw(in: path, angle: angle)
    NSGraphicsContext.restoreGraphicsState()
}

func stroke(_ path: NSBezierPath, color: NSColor, lineWidth: CGFloat) {
    color.setStroke()
    path.lineWidth = lineWidth
    path.stroke()
}

func shadowFill(_ path: NSBezierPath, color: NSColor, blur: CGFloat, offset: NSSize) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = offset
    shadow.set()
    NSColor.black.withAlphaComponent(0.18).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
}

func roundedPath(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawRoundedGradient(
    rect: NSRect,
    radius: CGFloat,
    colors: [NSColor],
    angle: CGFloat,
    shadowColor: NSColor? = nil,
    shadowBlur: CGFloat = 0,
    shadowOffset: NSSize = .zero,
    strokeColor: NSColor? = nil,
    strokeWidth: CGFloat = 0
) {
    let path = roundedPath(rect, radius: radius)
    if let shadowColor {
        shadowFill(path, color: shadowColor, blur: shadowBlur, offset: shadowOffset)
    }
    fillGradient(path, colors: colors, angle: angle)
    if let strokeColor, strokeWidth > 0 {
        stroke(path, color: strokeColor, lineWidth: strokeWidth)
    }
}

func drawPane(rect: NSRect, front: Bool) {
    let radius: CGFloat = front ? 78 : 72
    drawRoundedGradient(
        rect: rect,
        radius: radius,
        colors: front ? [color(0xf8fafc), color(0xc4cad5)] : [color(0xe2e7ef), color(0x9fa8b8)],
        angle: 90,
        shadowColor: color(0x000000, alpha: front ? 0.32 : 0.24),
        shadowBlur: front ? 40 : 32,
        shadowOffset: NSSize(width: 0, height: -20),
        strokeColor: color(0xffffff, alpha: 0.42),
        strokeWidth: 5
    )

    let titleBar = topRect(x: rect.minX + 46, y: 1024 - rect.maxY + 52, width: rect.width - 92, height: 16)
    drawRoundedGradient(
        rect: titleBar,
        radius: 8,
        colors: [color(0x757d8d, alpha: 0.68), color(0x596171, alpha: 0.58)],
        angle: 0
    )

    for index in 0..<4 {
        let rowY = 1024 - rect.maxY + 120 + CGFloat(index * 74)
        let row = topRect(x: rect.minX + 54, y: rowY, width: rect.width - 108, height: 18)
        drawRoundedGradient(
            rect: row,
            radius: 9,
            colors: [color(0x6f7786, alpha: 0.42), color(0x515967, alpha: 0.32)],
            angle: 0
        )
    }
}

func drawFolder() {
    let tab = topRect(x: 256, y: 538, width: 104, height: 44)
    drawRoundedGradient(
        rect: tab,
        radius: 18,
        colors: [color(0x7ad0ff), color(0x35a8f4)],
        angle: 90,
        shadowColor: color(0x000000, alpha: 0.16),
        shadowBlur: 18,
        shadowOffset: NSSize(width: 0, height: -8)
    )

    let body = topRect(x: 226, y: 574, width: 226, height: 142)
    drawRoundedGradient(
        rect: body,
        radius: 28,
        colors: [color(0x52c2ff), color(0x1688dc)],
        angle: 90,
        shadowColor: color(0x000000, alpha: 0.24),
        shadowBlur: 24,
        shadowOffset: NSSize(width: 0, height: -12),
        strokeColor: color(0xffffff, alpha: 0.28),
        strokeWidth: 4
    )
}

func drawIconArtwork() {
    let baseRect = NSRect(x: 36, y: 36, width: 952, height: 952)
    let basePath = roundedPath(baseRect, radius: 214)

    shadowFill(basePath, color: color(0x000000, alpha: 0.36), blur: 54, offset: NSSize(width: 0, height: -24))
    fillGradient(basePath, colors: [color(0x1f222b), color(0x373b47), color(0x585c68)], angle: 90)

    NSGraphicsContext.saveGraphicsState()
    basePath.addClip()

    drawRoundedGradient(
        rect: topRect(x: -120, y: 100, width: 1260, height: 170),
        radius: 86,
        colors: [color(0xffffff, alpha: 0.14), color(0xffffff, alpha: 0.02)],
        angle: 0
    )

    drawPane(rect: topRect(x: 178, y: 262, width: 398, height: 518), front: false)
    drawPane(rect: topRect(x: 438, y: 204, width: 410, height: 566), front: true)

    let divider = topRect(x: 486, y: 288, width: 42, height: 382)
    drawRoundedGradient(
        rect: divider,
        radius: 21,
        colors: [color(0x2f333d, alpha: 0.74), color(0x1f222a, alpha: 0.58)],
        angle: 90
    )

    drawFolder()

    let accent = topRect(x: 184, y: 778, width: 656, height: 52)
    drawRoundedGradient(
        rect: accent,
        radius: 26,
        colors: [color(0xffb02e), color(0xff8a00)],
        angle: 0,
        shadowColor: color(0xff9f0a, alpha: 0.42),
        shadowBlur: 28,
        shadowOffset: NSSize(width: 0, height: -8),
        strokeColor: color(0xffffff, alpha: 0.22),
        strokeWidth: 4
    )

    stroke(basePath, color: color(0xffffff, alpha: 0.22), lineWidth: 8)
    stroke(basePath, color: color(0x000000, alpha: 0.18), lineWidth: 3)

    NSGraphicsContext.restoreGraphicsState()
}

func writePNG(size: Int, to url: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "AppIconGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create bitmap"])
    }

    bitmap.size = NSSize(width: size, height: size)

    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "AppIconGenerator", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create graphics context"])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.shouldAntialias = true
    context.imageInterpolation = .high

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let scale = CGFloat(size) / 1024.0
    let transform = NSAffineTransform()
    transform.scaleX(by: scale, yBy: scale)
    transform.concat()

    drawIconArtwork()

    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = bitmap.representation(using: .png, properties: [.compressionFactor: 0.95]) else {
        throw NSError(domain: "AppIconGenerator", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"])
    }

    try pngData.write(to: url, options: .atomic)
}

func runIconutil() throws {
    if fileManager.fileExists(atPath: icnsURL.path) {
        try fileManager.removeItem(at: icnsURL)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw NSError(domain: "AppIconGenerator", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
    }
}

try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
if fileManager.fileExists(atPath: iconsetURL.path) {
    try fileManager.removeItem(at: iconsetURL)
}
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

try writePNG(size: 1024, to: previewURL)

let iconsetFiles: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for file in iconsetFiles {
    try writePNG(size: file.size, to: iconsetURL.appendingPathComponent(file.name))
}

try runIconutil()

print("Generated app icon at \(icnsURL.path)")
