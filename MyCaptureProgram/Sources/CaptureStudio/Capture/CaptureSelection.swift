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

    public var sourceRectInPoints: CGRect {
        CGRect(
            x: rect.minX - screenFrame.minX,
            y: screenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        ).integral
    }

    public var pixelWidth: Int {
        max(1, Int((rect.width * scale).rounded(.up)))
    }

    public var pixelHeight: Int {
        max(1, Int((rect.height * scale).rounded(.up)))
    }
}

struct ScreenCaptureOutputGeometry: Equatable, Sendable {
    let sourceRectInPoints: CGRect
    let pixelWidth: Int
    let pixelHeight: Int

    init(selection: CaptureSelection, pointPixelScale: CGFloat) {
        let effectiveScale = max(pointPixelScale, 1)
        self.sourceRectInPoints = selection.sourceRectInPoints
        self.pixelWidth = max(1, Int((selection.sourceRectInPoints.width * effectiveScale).rounded(.up)))
        self.pixelHeight = max(1, Int((selection.sourceRectInPoints.height * effectiveScale).rounded(.up)))
    }
}
