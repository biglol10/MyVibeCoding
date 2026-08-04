import AppKit
import CoreImage
import Foundation

public protocol ImageRenderServicing: Sendable {
    func renderPNG(basePNGData: Data, layers: [EditorLayer]) throws -> Data
}

public enum ImageRenderError: LocalizedError, Equatable {
    case imageDecodeFailed
    case bitmapCreationFailed
    case pngEncodingFailed

    public var errorDescription: String? {
        switch self {
        case .imageDecodeFailed:
            return "captured image could not be decoded."
        case .bitmapCreationFailed:
            return "edited image bitmap could not be created."
        case .pngEncodingFailed:
            return "edited image could not be encoded."
        }
    }
}

public struct AppKitImageRenderService: ImageRenderServicing {
    public init() {}

    public func renderPNG(basePNGData: Data, layers: [EditorLayer]) throws -> Data {
        guard let image = NSImage(data: basePNGData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            throw ImageRenderError.imageDecodeFailed
        }

        let width = cgImage.width
        let height = cgImage.height
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )

        guard let bitmap else {
            throw ImageRenderError.bitmapCreationFailed
        }

        let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.current?.cgContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let canvasHeight = CGFloat(height)
        for layer in layers {
            draw(layer, baseImage: cgImage, canvasHeight: canvasHeight)
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw ImageRenderError.pngEncodingFailed
        }

        return data
    }

    private func draw(_ layer: EditorLayer, baseImage: CGImage, canvasHeight: CGFloat) {
        switch layer {
        case .rectangle(let shape):
            drawShape(appKitRect(shape.frame, canvasHeight: canvasHeight), style: shape.style, oval: false)
        case .ellipse(let shape):
            drawShape(appKitRect(shape.frame, canvasHeight: canvasHeight), style: shape.style, oval: true)
        case .freehand(let freehand):
            drawPolyline(appKitPoints(freehand.points, canvasHeight: canvasHeight), style: freehand.style, alpha: 1)
        case .highlighter(let highlighter):
            drawPolyline(appKitPoints(highlighter.points, canvasHeight: canvasHeight), style: highlighter.style, alpha: 0.35)
        case .arrow(let arrow):
            drawArrow(arrow, canvasHeight: canvasHeight)
        case .text(let text):
            drawText(text, canvasHeight: canvasHeight)
        case .redaction(let redaction):
            drawRedaction(redaction, baseImage: baseImage, canvasHeight: canvasHeight)
        }
    }

    private func drawShape(_ frame: CGRect, style: LayerStyle, oval: Bool) {
        style.fillColor.nsColor.setFill()
        style.strokeColor.nsColor.setStroke()
        let path = oval ? NSBezierPath(ovalIn: frame) : NSBezierPath(rect: frame)
        path.lineWidth = style.lineWidth
        path.fill()
        path.stroke()
    }

    private func drawPolyline(_ points: [CGPoint], style: LayerStyle, alpha: CGFloat) {
        guard points.count > 1 else {
            return
        }

        let path = NSBezierPath()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.line(to: point)
        }
        path.lineWidth = style.lineWidth
        style.strokeColor.nsColor.withAlphaComponent(alpha).setStroke()
        path.stroke()
    }

    private func drawArrow(_ arrow: ArrowLayer, canvasHeight: CGFloat) {
        let start = appKitPoint(arrow.start, canvasHeight: canvasHeight)
        let end = appKitPoint(arrow.end, canvasHeight: canvasHeight)
        arrow.style.strokeColor.nsColor.setStroke()
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength: CGFloat = 12
        let left = CGPoint(
            x: end.x - headLength * cos(angle - .pi / 6),
            y: end.y - headLength * sin(angle - .pi / 6)
        )
        let right = CGPoint(
            x: end.x - headLength * cos(angle + .pi / 6),
            y: end.y - headLength * sin(angle + .pi / 6)
        )
        path.move(to: end)
        path.line(to: left)
        path.move(to: end)
        path.line(to: right)
        path.lineWidth = arrow.style.lineWidth
        path.stroke()
    }

    private func drawText(_ text: TextLayer, canvasHeight: CGFloat) {
        let frame = appKitRect(text.frame, canvasHeight: canvasHeight)
        text.style.fillColor.nsColor.setFill()
        frame.fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: text.fontSize),
            .foregroundColor: text.style.strokeColor.nsColor
        ]
        text.text.draw(in: frame.insetBy(dx: 6, dy: 4), withAttributes: attributes)
    }

    private func drawRedaction(_ redaction: RedactionLayer, baseImage: CGImage, canvasHeight: CGFloat) {
        let frame = appKitRect(redaction.frame, canvasHeight: canvasHeight)
        switch redaction.mode {
        case .solid:
            LayerColor.black.nsColor.setFill()
            frame.fill()
        case .blur(let radius):
            drawBlurredRegion(frame, radius: radius, baseImage: baseImage)
        }
    }

    private func drawBlurredRegion(_ frame: CGRect, radius: CGFloat, baseImage: CGImage) {
        let imageBounds = CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height)
        let targetFrame = frame.intersection(imageBounds)
        guard !targetFrame.isNull, targetFrame.width > 0, targetFrame.height > 0 else {
            return
        }

        let coreImageFrame = targetFrame
        let inputImage = CIImage(cgImage: baseImage)
            .clampedToExtent()
            .cropped(to: coreImageFrame)
        let blurredImage = inputImage
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(0, radius)])
            .cropped(to: coreImageFrame)
        let context = CIContext(options: nil)

        guard let blurredCGImage = context.createCGImage(blurredImage, from: coreImageFrame) else {
            return
        }

        NSGraphicsContext.current?.cgContext.draw(blurredCGImage, in: targetFrame)
    }

    private func appKitPoint(_ point: CGPoint, canvasHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: canvasHeight - point.y)
    }

    private func appKitPoints(_ points: [CGPoint], canvasHeight: CGFloat) -> [CGPoint] {
        points.map { appKitPoint($0, canvasHeight: canvasHeight) }
    }

    private func appKitRect(_ frame: CGRect, canvasHeight: CGFloat) -> CGRect {
        CGRect(
            x: frame.minX,
            y: canvasHeight - frame.maxY,
            width: frame.width,
            height: frame.height
        ).standardized
    }
}

private extension LayerColor {
    var nsColor: NSColor {
        NSColor(
            calibratedRed: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
}
