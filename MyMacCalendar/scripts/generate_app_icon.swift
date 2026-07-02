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
    static let graphiteTop = NSColor(calibratedRed: 0.170, green: 0.175, blue: 0.188, alpha: 1)
    static let graphiteMid = NSColor(calibratedRed: 0.078, green: 0.088, blue: 0.110, alpha: 1)
    static let graphiteBottom = NSColor(calibratedRed: 0.028, green: 0.034, blue: 0.046, alpha: 1)
    static let paperTop = NSColor(calibratedRed: 0.990, green: 0.992, blue: 0.998, alpha: 1)
    static let paperBottom = NSColor(calibratedRed: 0.858, green: 0.878, blue: 0.925, alpha: 1)
    static let ink = NSColor(calibratedRed: 0.100, green: 0.112, blue: 0.135, alpha: 1)
    static let mutedInk = NSColor(calibratedRed: 0.405, green: 0.440, blue: 0.510, alpha: 1)
    static let calendarRed = NSColor(calibratedRed: 1.000, green: 0.235, blue: 0.215, alpha: 1)
    static let calendarRedDeep = NSColor(calibratedRed: 0.730, green: 0.055, blue: 0.070, alpha: 1)
    static let eventBlue = NSColor(calibratedRed: 0.220, green: 0.410, blue: 0.920, alpha: 1)
    static let eventIndigo = NSColor(calibratedRed: 0.405, green: 0.300, blue: 0.940, alpha: 1)
    static let widgetTop = NSColor(calibratedRed: 0.080, green: 0.103, blue: 0.148, alpha: 1)
    static let widgetBottom = NSColor(calibratedRed: 0.025, green: 0.034, blue: 0.052, alpha: 1)
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

    let outerInset = side * 0.062
    let outerRect = NSRect(x: outerInset, y: outerInset, width: side - outerInset * 2, height: side - outerInset * 2)
    let outerRadius = side * 0.205
    let outerPath = roundedRect(outerRect, radius: outerRadius)

    NSGraphicsContext.saveGraphicsState()
    drawShadow(color: NSColor.black.withAlphaComponent(0.42), blur: side * 0.040, y: -side * 0.020)
    NSGradient(colors: [
        Palette.graphiteTop,
        Palette.graphiteMid,
        Palette.graphiteBottom
    ])?.draw(in: outerPath, angle: -92)
    NSGraphicsContext.restoreGraphicsState()

    let rimPath = roundedRect(outerRect.insetBy(dx: side * 0.010, dy: side * 0.010), radius: outerRadius * 0.94)
    stroke(outerPath, NSColor.white.withAlphaComponent(0.22), width: max(1, side * 0.0022))
    stroke(rimPath, NSColor.white.withAlphaComponent(0.095), width: max(1, side * 0.0017))

    let topSheenRect = NSRect(x: outerRect.minX + side * 0.030, y: outerRect.maxY - side * 0.238, width: outerRect.width - side * 0.060, height: side * 0.168)
    let topSheen = roundedRect(topSheenRect, radius: side * 0.070)
    NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.115),
        NSColor.white.withAlphaComponent(0.000)
    ])?.draw(in: topSheen, angle: -92)

    let paperRect = NSRect(x: side * 0.165, y: side * 0.176, width: side * 0.670, height: side * 0.680)
    let paperPath = roundedRect(paperRect, radius: side * 0.108)
    NSGraphicsContext.saveGraphicsState()
    drawShadow(color: NSColor.black.withAlphaComponent(0.38), blur: side * 0.038, y: -side * 0.018)
    NSGradient(colors: [Palette.paperTop, Palette.paperBottom])?.draw(in: paperPath, angle: 92)
    NSGraphicsContext.restoreGraphicsState()
    stroke(paperPath, NSColor.white.withAlphaComponent(0.62), width: max(1, side * 0.002))
    stroke(roundedRect(paperRect.insetBy(dx: side * 0.008, dy: side * 0.008), radius: side * 0.098), NSColor.black.withAlphaComponent(0.070), width: max(0.7, side * 0.0012))

    let headerRect = NSRect(x: paperRect.minX, y: paperRect.maxY - side * 0.180, width: paperRect.width, height: side * 0.180)
    NSGraphicsContext.saveGraphicsState()
    paperPath.addClip()
    NSGradient(colors: [
        NSColor(calibratedRed: 1.000, green: 0.360, blue: 0.330, alpha: 1),
        Palette.calendarRed,
        Palette.calendarRedDeep
    ])?.draw(in: headerRect, angle: -90)
    NSColor.white.withAlphaComponent(0.120).setFill()
    NSRect(x: headerRect.minX, y: headerRect.maxY - headerRect.height * 0.43, width: headerRect.width, height: headerRect.height * 0.43).fill()
    NSGraphicsContext.restoreGraphicsState()

    let ringY = headerRect.maxY - side * 0.070
    for x in [paperRect.minX + paperRect.width * 0.29, paperRect.minX + paperRect.width * 0.71] {
        let ringRect = NSRect(x: x - side * 0.023, y: ringY - side * 0.023, width: side * 0.046, height: side * 0.046)
        fill(oval(ringRect), NSColor.white.withAlphaComponent(0.94))
        fill(oval(ringRect.insetBy(dx: side * 0.011, dy: side * 0.011)), Palette.calendarRedDeep.withAlphaComponent(0.55))
    }

    let gridRect = NSRect(
        x: paperRect.minX + side * 0.074,
        y: paperRect.minY + side * 0.134,
        width: paperRect.width - side * 0.148,
        height: paperRect.height - side * 0.302
    )
    let cols = 7
    let rows = 5
    let cellW = gridRect.width / CGFloat(cols)
    let cellH = gridRect.height / CGFloat(rows)
    if side >= 64 {
        let lineColor = NSColor(calibratedRed: 0.230, green: 0.270, blue: 0.360, alpha: 0.145)
        for col in 0...cols {
            let x = gridRect.minX + CGFloat(col) * cellW
            let path = NSBezierPath()
            path.move(to: CGPoint(x: x, y: gridRect.minY))
            path.line(to: CGPoint(x: x, y: gridRect.maxY))
            stroke(path, lineColor, width: max(0.5, side * 0.0010))
        }
        for row in 0...rows {
            let y = gridRect.minY + CGFloat(row) * cellH
            let path = NSBezierPath()
            path.move(to: CGPoint(x: gridRect.minX, y: y))
            path.line(to: CGPoint(x: gridRect.maxX, y: y))
            stroke(path, lineColor, width: max(0.5, side * 0.0010))
        }
    }

    let dateRect = NSRect(x: paperRect.minX + side * 0.100, y: paperRect.minY + side * 0.214, width: paperRect.width - side * 0.200, height: side * 0.230)
    drawText("30", in: dateRect, size: side * 0.214, weight: .black, color: Palette.ink)

    if side >= 128 {
        drawText("JUN", in: NSRect(x: paperRect.minX, y: paperRect.minY + side * 0.462, width: paperRect.width, height: side * 0.055), size: side * 0.036, weight: .semibold, color: Palette.mutedInk)
    }

    let eventHeight = side * 0.042
    let eventY = paperRect.minY + side * 0.108
    let event1 = roundedRect(NSRect(
        x: paperRect.minX + side * 0.118,
        y: eventY,
        width: paperRect.width * 0.575,
        height: eventHeight
    ), radius: eventHeight * 0.50)
    let event2 = roundedRect(NSRect(
        x: paperRect.minX + side * 0.118,
        y: eventY - side * 0.060,
        width: paperRect.width * 0.405,
        height: eventHeight
    ), radius: eventHeight * 0.50)
    fill(event1, Palette.eventBlue.withAlphaComponent(0.94))
    fill(event2, Palette.eventIndigo.withAlphaComponent(0.90))

    let widgetRect = NSRect(x: side * 0.495, y: side * 0.104, width: side * 0.345, height: side * 0.205)
    let widgetPath = roundedRect(widgetRect, radius: side * 0.067)
    NSGraphicsContext.saveGraphicsState()
    drawShadow(color: NSColor.black.withAlphaComponent(0.42), blur: side * 0.030, y: -side * 0.012)
    NSGradient(colors: [Palette.widgetTop, Palette.widgetBottom])?.draw(in: widgetPath, angle: 92)
    NSGraphicsContext.restoreGraphicsState()
    stroke(widgetPath, NSColor.white.withAlphaComponent(0.20), width: max(0.7, side * 0.0017))

    let widgetAccent = roundedRect(NSRect(
        x: widgetRect.minX + side * 0.036,
        y: widgetRect.minY + side * 0.052,
        width: side * 0.016,
        height: side * 0.108
    ), radius: side * 0.009)
    fill(widgetAccent, Palette.calendarRed)

    let textLine1 = roundedRect(NSRect(
        x: widgetRect.minX + side * 0.074,
        y: widgetRect.minY + side * 0.133,
        width: widgetRect.width * 0.560,
        height: side * 0.022
    ), radius: side * 0.013)
    let textLine2 = roundedRect(NSRect(
        x: widgetRect.minX + side * 0.074,
        y: widgetRect.minY + side * 0.083,
        width: widgetRect.width * 0.690,
        height: side * 0.020
    ), radius: side * 0.011)
    fill(textLine1, NSColor.white.withAlphaComponent(0.84))
    fill(textLine2, NSColor.white.withAlphaComponent(0.34))

    let alertDot = NSRect(x: widgetRect.maxX - side * 0.074, y: widgetRect.maxY - side * 0.078, width: side * 0.040, height: side * 0.040)
    fill(oval(alertDot), Palette.calendarRed)
    fill(oval(alertDot.insetBy(dx: side * 0.012, dy: side * 0.012)), NSColor.white.withAlphaComponent(0.82))

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
