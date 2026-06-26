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
    case failedToCreateIconset
    case missingPNGFile(String)
}

func makeCanvas(side: CGFloat) -> Data {
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
    ) else { return Data() }
    bitmap.size = NSSize(width: side, height: side)

    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else { return Data() }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    defer { NSGraphicsContext.restoreGraphicsState() }

    let inset = side * 0.06
    let bounds = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let cornerRadius = side * 0.22
    let rounded = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)

    // Soft glow around the icon.
    for i in 0..<5 {
        let ringAlpha = 0.035 - Double(i) * 0.004
        if ringAlpha <= 0 { continue }
        NSColor(calibratedWhite: 1, alpha: ringAlpha).setStroke()
        let ring = NSBezierPath(roundedRect: NSRect(
            x: inset - CGFloat(i) * 0.6,
            y: inset - CGFloat(i) * 0.6,
            width: side - inset * 2 + CGFloat(i) * 1.2,
            height: side - inset * 2 + CGFloat(i) * 1.2
        ), xRadius: cornerRadius + CGFloat(i) * 0.6, yRadius: cornerRadius + CGFloat(i) * 0.6)
        ring.lineWidth = max(0.5, 1.2 - CGFloat(i) * 0.15)
        ring.stroke()
    }

    let background = NSGradient(
        starting: NSColor(calibratedRed: 0.14, green: 0.17, blue: 0.58, alpha: 1),
        ending: NSColor(calibratedRed: 0.36, green: 0.13, blue: 0.90, alpha: 1)
    ) ?? NSGradient(starting: NSColor.systemBlue, ending: NSColor.systemPurple)
    if let background {
        background.draw(in: rounded, angle: 135)
    }
    let highlight = NSGradient(
        starting: NSColor(calibratedWhite: 1, alpha: 0.22),
        ending: NSColor(calibratedWhite: 1, alpha: 0.01)
    ) ?? background
    if let highlight {
        highlight.draw(in: rounded, angle: -45)
    }

    NSColor(calibratedWhite: 1, alpha: 0.18).set()
    rounded.stroke()

    let contentInset = side * 0.17
    let sheet = NSBezierPath(
        roundedRect: NSRect(
            x: contentInset,
            y: contentInset,
            width: side - contentInset * 2,
            height: side - contentInset * 2
        ),
        xRadius: side * 0.12,
        yRadius: side * 0.12
    )
    let sheetGradient = NSGradient(
        starting: NSColor(calibratedWhite: 0.97, alpha: 0.98),
        ending: NSColor(calibratedWhite: 0.94, alpha: 0.92)
    ) ?? NSGradient(starting: NSColor.white, ending: NSColor(calibratedWhite: 0.93, alpha: 1))
    if let sheetGradient {
        sheetGradient.draw(in: sheet, angle: 90)
    } else {
        NSColor(calibratedWhite: 1, alpha: 0.95).setFill()
        sheet.fill()
    }
    NSColor(calibratedWhite: 1, alpha: 0.8).set()
    sheet.stroke()

    let titleHeight = side * 0.12
    let titleRect = NSRect(
        x: contentInset + side * 0.03,
        y: side - contentInset - titleHeight - side * 0.02,
        width: side - contentInset * 2 - side * 0.06,
        height: titleHeight
    )
    let title = NSBezierPath(
        roundedRect: titleRect,
        xRadius: titleHeight * 0.35,
        yRadius: titleHeight * 0.35
    )
    NSColor(calibratedRed: 0.15, green: 0.20, blue: 0.50, alpha: 0.95).setFill()
    title.fill()
    let titleOverlay = NSGradient(
        starting: NSColor(calibratedWhite: 1, alpha: 0.14),
        ending: NSColor(calibratedWhite: 1, alpha: 0.02)
    ) ?? sheetGradient
    if let titleOverlay {
        titleOverlay.draw(in: title, angle: 90)
    }

    let pageInset = side * 0.24
    let page = NSBezierPath(
        roundedRect: NSRect(
            x: pageInset,
            y: pageInset - side * 0.03,
            width: side - pageInset * 2,
            height: side - pageInset * 2
        ),
        xRadius: side * 0.05,
        yRadius: side * 0.05
    )
    NSColor(calibratedWhite: 1, alpha: 0.86).setFill()
    page.fill()
    NSColor(calibratedWhite: 0.98, alpha: 0.5).setStroke()
    page.lineWidth = 0.6
    page.stroke()

    let markerColor = NSColor(calibratedRed: 0.18, green: 0.24, blue: 0.48, alpha: 0.86)
    markerColor.set()

    let dotSize = side * 0.05
    let startY = side * 0.66
    let lineStart = side * 0.31
    for idx in 0..<4 {
        let y = startY + CGFloat(idx) * side * 0.08 * -1
        let lineLength = side * (0.28 + CGFloat(idx) * 0.03)
        let lineRect = NSRect(x: lineStart, y: y, width: lineLength, height: dotSize * 0.9)
        let line = NSBezierPath(roundedRect: lineRect, xRadius: dotSize * 0.45, yRadius: dotSize * 0.45)
        line.fill()

        let dot = NSBezierPath(ovalIn: NSRect(
            x: lineStart + lineLength + side * 0.04,
            y: y - side * 0.005,
            width: dotSize,
            height: dotSize
        ))
        dot.fill()
    }

    let dateWidth = side * 0.46
    let dateHeight = side * 0.25
    let dateY = side * 0.12
    let dateX = side - contentInset - dateWidth
    let dateBlock = NSBezierPath(
        roundedRect: NSRect(x: dateX, y: dateY, width: dateWidth, height: dateHeight),
        xRadius: side * 0.08,
        yRadius: side * 0.08
    )
    let dateGradient = NSGradient(
        starting: NSColor(calibratedRed: 0.18, green: 0.28, blue: 0.68, alpha: 0.95),
        ending: NSColor(calibratedRed: 0.05, green: 0.12, blue: 0.30, alpha: 0.95)
    ) ?? NSGradient(starting: NSColor(calibratedRed: 0.2, green: 0.25, blue: 0.6, alpha: 0.95), ending: NSColor(calibratedRed: 0.05, green: 0.1, blue: 0.25, alpha: 0.95))
    if let dateGradient {
        dateGradient.draw(in: dateBlock, angle: 45)
    } else {
        NSColor(calibratedRed: 0.17, green: 0.24, blue: 0.45, alpha: 0.95).setFill()
        dateBlock.fill()
    }
    NSColor(calibratedWhite: 1, alpha: 0.35).setStroke()
    dateBlock.lineWidth = 0.7
    dateBlock.fill()
    dateBlock.stroke()

    NSColor.white.set()
    let star = NSBezierPath()
    let cx = dateX + dateWidth * 0.77
    let cy = dateY + dateHeight * 0.5
    let rOuter = side * 0.028
    let rInner = rOuter * 0.46
    for i in 0..<10 {
        let angle = (Double(i) * .pi) / 5.0 - .pi / 2.0
        let r = i % 2 == 0 ? rOuter : rInner
        let x = cx + CGFloat(cos(angle)) * r
        let y = cy + CGFloat(sin(angle)) * r
        if i == 0 {
            star.move(to: CGPoint(x: x, y: y))
        } else {
            star.line(to: CGPoint(x: x, y: y))
        }
    }
    star.close()
    star.fill()

    // Clock ring detail for extra polish
    NSColor(calibratedWhite: 1, alpha: 0.9).setStroke()
    let timeCenter = CGPoint(x: contentInset + side * 0.31, y: side - contentInset - side * 0.25)
    let clockBase = NSBezierPath(ovalIn: NSRect(
        x: timeCenter.x - side * 0.055,
        y: timeCenter.y - side * 0.055,
        width: side * 0.11,
        height: side * 0.11
    ))
    NSColor(calibratedRed: 0.98, green: 0.98, blue: 1.0, alpha: 0.95).setFill()
    clockBase.fill()
    clockBase.lineWidth = side * 0.004
    clockBase.stroke()

    NSColor(calibratedRed: 0.2, green: 0.25, blue: 0.55, alpha: 0.9).setStroke()
    let hand = NSBezierPath()
    hand.move(to: timeCenter)
    hand.line(to: CGPoint(x: timeCenter.x - side * 0.02, y: timeCenter.y + side * 0.02))
    hand.lineWidth = side * 0.01
    hand.stroke()

    let hand2 = NSBezierPath()
    hand2.move(to: timeCenter)
    hand2.line(to: CGPoint(x: timeCenter.x + side * 0.03, y: timeCenter.y + side * 0.01))
    hand2.lineWidth = side * 0.006
    hand2.stroke()

    return bitmap.representation(using: .png, properties: [:]) ?? Data()
}

func savePNG(_ data: Data, to url: URL) throws {
    if data.isEmpty {
        throw IconRenderError.cannotEncodePNG(0)
    }
    try data.write(to: url, options: [.atomic])
}

func generateIconSet(at iconsetURL: URL) throws {
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
        ("icon_1024x1024.png", 1024),
    ]

    for (name, side) in specs {
        let imageData = makeCanvas(side: side)
        try savePNG(imageData, to: iconsetURL.appendingPathComponent(name))
    }
}

func writeIcns(from iconsetURL: URL, to outputURL: URL) throws {
    let entries: [(String, String)] = [
        ("ic11", "icon_16x16@2x.png"),
        ("ic12", "icon_32x32@2x.png"),
        ("ic07", "icon_64x64@2x.png"),
        ("ic13", "icon_128x128@2x.png"),
        ("ic08", "icon_256x256.png"),
        ("ic14", "icon_256x256@2x.png"),
        ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png"),
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
