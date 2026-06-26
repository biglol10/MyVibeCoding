#!/usr/bin/env swift
import AppKit
import Foundation

let scriptPath = URL(fileURLWithPath: CommandLine.arguments[0])
let scriptsDir = scriptPath.deletingLastPathComponent()
let rootDir = scriptsDir.deletingLastPathComponent()
let resourcesDir = rootDir.appendingPathComponent("Resources")
let iconsetDir = resourcesDir.appendingPathComponent("MyMacCalendar.iconset")
let iconPath = resourcesDir.appendingPathComponent("AppIcon.icns")

enum IconRenderError: Error {
    case cannotCreateImage
    case cannotEncodePNG(Int)
    case missingPNGFile(String)
}

private struct Palette {
    static let ink = NSColor(calibratedRed: 0.070, green: 0.075, blue: 0.090, alpha: 1)
    static let ink2 = NSColor(calibratedRed: 0.130, green: 0.145, blue: 0.185, alpha: 1)
    static let purple = NSColor(calibratedRed: 0.300, green: 0.185, blue: 0.760, alpha: 1)
    static let blue = NSColor(calibratedRed: 0.090, green: 0.320, blue: 0.900, alpha: 1)
    static let paper = NSColor(calibratedRed: 0.965, green: 0.970, blue: 0.990, alpha: 1)
    static let paperShade = NSColor(calibratedRed: 0.855, green: 0.875, blue: 0.925, alpha: 1)
    static let calendarRed = NSColor(calibratedRed: 1.000, green: 0.230, blue: 0.205, alpha: 1)
    static let eventBlue = NSColor(calibratedRed: 0.250, green: 0.435, blue: 0.920, alpha: 1)
    static let eventViolet = NSColor(calibratedRed: 0.810, green: 0.350, blue: 0.950, alpha: 1)
}

private func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

private func oval(_ rect: NSRect) -> NSBezierPath {
    NSBezierPath(ovalIn: rect)
}

private func fill(_ path: NSBezierPath, _ color: NSColor) {
    color.setFill()
    path.fill()
}

private func stroke(_ path: NSBezierPath, _ color: NSColor, width: CGFloat = 1) {
    color.setStroke()
    path.lineWidth = width
    path.stroke()
}

private func drawShadow(color: NSColor, blur: CGFloat, x: CGFloat = 0, y: CGFloat = 0) {
    let shadow = NSShadow()
    shadow.shadowColor = color
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: x, height: y)
    shadow.set()
}

private func drawText(_ text: String, in rect: NSRect, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let textSize = attributed.size()
    attributed.draw(in: NSRect(
        x: rect.midX - textSize.width / 2,
        y: rect.midY - textSize.height / 2 - size * 0.035,
        width: textSize.width,
        height: textSize.height
    ))
}

private func makeCanvas(side: CGFloat) throws -> Data {
    let pixelSize = max(1, Int(ceil(side)))
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
        throw IconRenderError.cannotCreateImage
    }
    bitmap.size = NSSize(width: side, height: side)

    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw IconRenderError.cannotCreateImage
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    defer { NSGraphicsContext.restoreGraphicsState() }

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: side, height: side).fill()

    let outerInset = side * 0.060
    let outerRect = NSRect(x: outerInset, y: outerInset, width: side - outerInset * 2, height: side - outerInset * 2)
    let outerRadius = side * 0.214
    let outerPath = roundedRect(outerRect, radius: outerRadius)

    NSGraphicsContext.saveGraphicsState()
    drawShadow(color: NSColor.black.withAlphaComponent(0.35), blur: side * 0.035, y: -side * 0.018)
    let baseGradient = NSGradient(colors: [Palette.ink, Palette.ink2, Palette.purple, Palette.blue])
    baseGradient?.draw(in: outerPath, angle: 135)
    NSGraphicsContext.restoreGraphicsState()

    let glowRect = outerRect.insetBy(dx: side * 0.012, dy: side * 0.012)
    let glowPath = roundedRect(glowRect, radius: outerRadius * 0.92)
    NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.26),
        NSColor.white.withAlphaComponent(0.020)
    ])?.draw(in: glowPath, angle: 70)
    stroke(outerPath, NSColor.white.withAlphaComponent(0.28), width: max(1, side * 0.0022))

    let glassOrb1 = oval(NSRect(x: side * 0.145, y: side * 0.660, width: side * 0.280, height: side * 0.280))
    NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.150),
        NSColor.white.withAlphaComponent(0.000)
    ])?.draw(in: glassOrb1, angle: -45)

    let paperRect = NSRect(x: side * 0.185, y: side * 0.175, width: side * 0.630, height: side * 0.665)
    let paperPath = roundedRect(paperRect, radius: side * 0.112)
    NSGraphicsContext.saveGraphicsState()
    drawShadow(color: NSColor.black.withAlphaComponent(0.32), blur: side * 0.035, y: -side * 0.018)
    NSGradient(colors: [Palette.paper, Palette.paperShade])?.draw(in: paperPath, angle: 92)
    NSGraphicsContext.restoreGraphicsState()
    stroke(paperPath, NSColor.white.withAlphaComponent(0.55), width: max(1, side * 0.002))

    let headerRect = NSRect(x: paperRect.minX, y: paperRect.maxY - side * 0.175, width: paperRect.width, height: side * 0.175)
    let headerPath = roundedRect(headerRect, radius: side * 0.110)
    NSGradient(colors: [
        NSColor(calibratedRed: 1.0, green: 0.335, blue: 0.305, alpha: 1),
        Palette.calendarRed
    ])?.draw(in: headerPath, angle: 90)

    let headerClip = NSBezierPath(rect: NSRect(x: headerRect.minX, y: headerRect.minY, width: headerRect.width, height: headerRect.height * 0.58))
    NSColor(calibratedRed: 0.760, green: 0.090, blue: 0.100, alpha: 0.24).setFill()
    headerClip.fill()

    let ringY = headerRect.maxY - side * 0.070
    for x in [paperRect.minX + paperRect.width * 0.29, paperRect.minX + paperRect.width * 0.71] {
        let ringRect = NSRect(x: x - side * 0.026, y: ringY - side * 0.026, width: side * 0.052, height: side * 0.052)
        fill(oval(ringRect), NSColor.white.withAlphaComponent(0.92))
        fill(oval(ringRect.insetBy(dx: side * 0.012, dy: side * 0.012)), Palette.calendarRed.withAlphaComponent(0.64))
    }

    let gridRect = NSRect(
        x: paperRect.minX + side * 0.072,
        y: paperRect.minY + side * 0.164,
        width: paperRect.width - side * 0.144,
        height: paperRect.height - side * 0.296
    )
    let cols = 7
    let rows = 5
    let cellW = gridRect.width / CGFloat(cols)
    let cellH = gridRect.height / CGFloat(rows)
    let lineColor = NSColor(calibratedRed: 0.255, green: 0.300, blue: 0.395, alpha: 0.145)

    for col in 0...cols {
        let x = gridRect.minX + CGFloat(col) * cellW
        let path = NSBezierPath()
        path.move(to: CGPoint(x: x, y: gridRect.minY))
        path.line(to: CGPoint(x: x, y: gridRect.maxY))
        stroke(path, lineColor, width: max(0.5, side * 0.0011))
    }
    for row in 0...rows {
        let y = gridRect.minY + CGFloat(row) * cellH
        let path = NSBezierPath()
        path.move(to: CGPoint(x: gridRect.minX, y: y))
        path.line(to: CGPoint(x: gridRect.maxX, y: y))
        stroke(path, lineColor, width: max(0.5, side * 0.0011))
    }

    let todayCenter = CGPoint(x: gridRect.minX + cellW * 4.50, y: gridRect.minY + cellH * 1.98)
    let todaySize = side * 0.172
    let todayRect = NSRect(
        x: todayCenter.x - todaySize / 2,
        y: todayCenter.y - todaySize / 2,
        width: todaySize,
        height: todaySize
    )
    NSGraphicsContext.saveGraphicsState()
    drawShadow(color: Palette.calendarRed.withAlphaComponent(0.40), blur: side * 0.025)
    fill(oval(todayRect), Palette.calendarRed)
    NSGraphicsContext.restoreGraphicsState()
    drawText("26", in: todayRect, size: side * 0.076, weight: .black, color: NSColor.white)

    let eventHeight = side * 0.046
    let event1 = roundedRect(NSRect(
        x: gridRect.minX + cellW * 3.18,
        y: gridRect.minY + cellH * 0.08,
        width: cellW * 2.20,
        height: eventHeight
    ), radius: eventHeight * 0.50)
    let event2 = roundedRect(NSRect(
        x: gridRect.minX + cellW * 3.18,
        y: gridRect.minY - cellH * 0.34,
        width: cellW * 1.72,
        height: eventHeight
    ), radius: eventHeight * 0.50)
    fill(event1, Palette.eventBlue.withAlphaComponent(0.92))
    fill(event2, Palette.eventViolet.withAlphaComponent(0.90))

    let widgetRect = NSRect(x: side * 0.405, y: side * 0.095, width: side * 0.440, height: side * 0.255)
    let widgetPath = roundedRect(widgetRect, radius: side * 0.067)
    NSGraphicsContext.saveGraphicsState()
    drawShadow(color: NSColor.black.withAlphaComponent(0.38), blur: side * 0.030, y: -side * 0.010)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.095, green: 0.120, blue: 0.180, alpha: 0.97),
        NSColor(calibratedRed: 0.040, green: 0.055, blue: 0.082, alpha: 0.97)
    ])?.draw(in: widgetPath, angle: 92)
    NSGraphicsContext.restoreGraphicsState()
    stroke(widgetPath, NSColor.white.withAlphaComponent(0.18), width: max(0.7, side * 0.0017))

    let widgetAccent = roundedRect(NSRect(
        x: widgetRect.minX + side * 0.045,
        y: widgetRect.minY + side * 0.066,
        width: side * 0.018,
        height: side * 0.132
    ), radius: side * 0.009)
    fill(widgetAccent, Palette.calendarRed)

    let textLine1 = roundedRect(NSRect(
        x: widgetRect.minX + side * 0.082,
        y: widgetRect.minY + side * 0.156,
        width: widgetRect.width * 0.55,
        height: side * 0.026
    ), radius: side * 0.013)
    let textLine2 = roundedRect(NSRect(
        x: widgetRect.minX + side * 0.082,
        y: widgetRect.minY + side * 0.103,
        width: widgetRect.width * 0.70,
        height: side * 0.022
    ), radius: side * 0.011)
    fill(textLine1, NSColor.white.withAlphaComponent(0.84))
    fill(textLine2, NSColor.white.withAlphaComponent(0.34))

    let sparkleCenter = CGPoint(x: widgetRect.maxX - side * 0.083, y: widgetRect.minY + side * 0.128)
    let sparkle = NSBezierPath()
    let outer = side * 0.040
    let inner = outer * 0.42
    for i in 0..<8 {
        let angle = CGFloat(i) * .pi / 4 - .pi / 2
        let r = i % 2 == 0 ? outer : inner
        let point = CGPoint(x: sparkleCenter.x + cos(angle) * r, y: sparkleCenter.y + sin(angle) * r)
        if i == 0 {
            sparkle.move(to: point)
        } else {
            sparkle.line(to: point)
        }
    }
    sparkle.close()
    fill(sparkle, NSColor.white.withAlphaComponent(0.95))

    guard let png = bitmap.representation(using: .png, properties: [:]), png.isEmpty == false else {
        throw IconRenderError.cannotEncodePNG(pixelSize)
    }
    return png
}

private func savePNG(_ data: Data, to url: URL) throws {
    if data.isEmpty {
        throw IconRenderError.cannotEncodePNG(0)
    }
    try data.write(to: url, options: [.atomic])
}

private func generateIconSet(at iconsetURL: URL) throws {
    try? FileManager.default.removeItem(at: iconsetURL)
    try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

    let specs: [(String, CGFloat)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_64x64.png", 64),
        ("icon_64x64@2x.png", 128),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
        ("icon_1024x1024.png", 1024)
    ]

    for (name, side) in specs {
        let imageData = try makeCanvas(side: side)
        try savePNG(imageData, to: iconsetURL.appendingPathComponent(name))
    }
}

private func writeIcns(from iconsetURL: URL, to outputURL: URL) throws {
    let entries: [(String, String)] = [
        ("ic11", "icon_16x16@2x.png"),
        ("ic12", "icon_32x32@2x.png"),
        ("ic07", "icon_64x64@2x.png"),
        ("ic13", "icon_128x128@2x.png"),
        ("ic08", "icon_256x256.png"),
        ("ic14", "icon_256x256@2x.png"),
        ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png")
    ]

    var payload = Data()
    for (type, fileName) in entries {
        let pngURL = iconsetURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: pngURL.path) else {
            throw IconRenderError.missingPNGFile(fileName)
        }

        let pngData = try Data(contentsOf: pngURL)
        let typeData = type.data(using: .ascii)!
        var length = UInt32(pngData.count + 8).bigEndian
        var blockHeader = Data()
        blockHeader.append(typeData)
        withUnsafeBytes(of: &length) { bytes in
            blockHeader.append(contentsOf: bytes)
        }
        payload.append(blockHeader)
        payload.append(pngData)
    }

    var output = Data("icns".utf8)
    var totalLength = UInt32(payload.count + 8).bigEndian
    withUnsafeBytes(of: &totalLength) { bytes in
        output.append(contentsOf: bytes)
    }
    output.append(payload)
    try output.write(to: outputURL, options: [.atomic])
}

do {
    try? FileManager.default.removeItem(at: iconPath)
    try? FileManager.default.removeItem(at: iconsetDir)

    try generateIconSet(at: iconsetDir)
    try writeIcns(from: iconsetDir, to: iconPath)
    print("Created: \(iconPath.path)")
} catch {
    fputs("Failed to generate icon: \(error)\n", stderr)
    exit(1)
}
