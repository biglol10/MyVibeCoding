import CoreGraphics

enum ScreenCoordinateConverter {
    static func appKitRect(fromQuartz rect: CGRect, mainDisplayBounds: CGRect) -> CGRect {
        let rect = rect.standardized
        return CGRect(
            x: rect.minX,
            y: mainDisplayBounds.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        ).standardized
    }
}
