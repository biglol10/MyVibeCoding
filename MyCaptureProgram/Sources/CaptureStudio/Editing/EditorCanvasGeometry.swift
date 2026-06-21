import CoreGraphics
import Foundation

public struct EditorCanvasGeometry: Equatable, Sendable {
    public var imageSize: CGSize
    public var viewSize: CGSize

    public init(imageSize: CGSize, viewSize: CGSize) {
        self.imageSize = imageSize
        self.viewSize = viewSize
    }

    public var imageRectInView: CGRect {
        guard imageSize.width > 0, imageSize.height > 0, viewSize.width > 0, viewSize.height > 0 else {
            return .zero
        }

        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let x = (viewSize.width - width) / 2
        let y = (viewSize.height - height) / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    public func imagePoint(forViewPoint point: CGPoint) -> CGPoint {
        let rect = imageRectInView
        guard rect.width > 0, rect.height > 0 else {
            return .zero
        }

        let normalizedX = (point.x - rect.minX) / rect.width
        let normalizedY = (point.y - rect.minY) / rect.height
        return CGPoint(
            x: min(max(normalizedX, 0), 1) * imageSize.width,
            y: min(max(normalizedY, 0), 1) * imageSize.height
        )
    }

    public func viewRect(forImageRect imageRect: CGRect) -> CGRect {
        let rect = imageRectInView
        guard imageSize.width > 0, imageSize.height > 0 else {
            return .zero
        }

        return CGRect(
            x: rect.minX + (imageRect.minX / imageSize.width) * rect.width,
            y: rect.minY + (imageRect.minY / imageSize.height) * rect.height,
            width: (imageRect.width / imageSize.width) * rect.width,
            height: (imageRect.height / imageSize.height) * rect.height
        )
    }
}
