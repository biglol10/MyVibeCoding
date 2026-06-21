import AppKit
import CoreImage
import Foundation

public protocol ImageRenderServicing {
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

        for layer in layers {
            draw(layer)
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw ImageRenderError.pngEncodingFailed
        }

        return data
    }

    private func draw(_ layer: EditorLayer) {
        switch layer {
        case .rectangle(let shape):
            drawShape(shape.frame, style: shape.style, oval: false)
        case .ellipse(let shape):
            drawShape(shape.frame, style: shape.style, oval: true)
        case .freehand(let freehand):
            drawPolyline(freehand.points, style: freehand.style, alpha: 1)
        case .highlighter(let highlighter):
            drawPolyline(highlighter.points, style: highlighter.style, alpha: 0.35)
        case .arrow(let arrow):
            drawArrow(arrow)
        case .text(let text):
            drawText(text)
        case .redaction(let redaction):
            drawRedaction(redaction)
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

    private func drawArrow(_ arrow: ArrowLayer) {
        arrow.style.strokeColor.nsColor.setStroke()
        let path = NSBezierPath()
        path.move(to: arrow.start)
        path.line(to: arrow.end)
        path.lineWidth = arrow.style.lineWidth
        path.stroke()
    }

    private func drawText(_ text: TextLayer) {
        text.style.fillColor.nsColor.setFill()
        text.frame.fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: text.fontSize),
            .foregroundColor: text.style.strokeColor.nsColor
        ]
        text.text.draw(in: text.frame.insetBy(dx: 6, dy: 4), withAttributes: attributes)
    }

    private func drawRedaction(_ redaction: RedactionLayer) {
        LayerColor.black.nsColor.setFill()
        redaction.frame.fill()
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
