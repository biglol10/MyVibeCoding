import CoreGraphics

public struct CaptureSelection: Equatable, Sendable {
    public let displayID: CGDirectDisplayID
    public let screenFrame: CGRect
    public let rect: CGRect
    public let scale: CGFloat

    public init(displayID: CGDirectDisplayID, screenFrame: CGRect, rect: CGRect, scale: CGFloat) {
        self.displayID = displayID
        self.screenFrame = screenFrame
        self.rect = rect.standardized
        self.scale = scale
    }

    public var isUsable: Bool {
        rect.width >= 8 && rect.height >= 8
    }

    public var sourceRectInPixels: CGRect {
        CGRect(
            x: (rect.minX - screenFrame.minX) * scale,
            y: (screenFrame.maxY - rect.maxY) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral
    }

    public var pixelWidth: Int {
        max(1, Int(sourceRectInPixels.width))
    }

    public var pixelHeight: Int {
        max(1, Int(sourceRectInPixels.height))
    }
}
