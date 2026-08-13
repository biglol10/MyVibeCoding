import Foundation
import CoreGraphics

public enum WidgetFramePlacement {
    public static func clampedFrame(
        _ frame: CGRect,
        visibleFrames: [CGRect],
        fallback: CGRect
    ) -> CGRect {
        let safeFallback = isValid(fallback) ? fallback : CGRect(x: 0, y: 0, width: 260, height: 260)
        let screens = visibleFrames.filter(isValid)
        guard screens.isEmpty == false else { return safeFallback }

        let candidate = isValid(frame) ? frame : safeFallback
        if let screen = bestIntersectingScreen(for: candidate, screens: screens) {
            return clamp(candidate, to: screen)
        }

        let fallbackScreen = bestIntersectingScreen(for: safeFallback, screens: screens) ?? screens[0]
        return clamp(safeFallback, to: fallbackScreen)
    }

    private static func bestIntersectingScreen(for frame: CGRect, screens: [CGRect]) -> CGRect? {
        screens
            .compactMap { screen -> (screen: CGRect, area: CGFloat)? in
                let intersection = screen.intersection(frame)
                guard intersection.isNull == false,
                      intersection.width > 0,
                      intersection.height > 0 else {
                    return nil
                }
                return (screen, intersection.width * intersection.height)
            }
            .max { $0.area < $1.area }?
            .screen
    }

    private static func clamp(_ frame: CGRect, to screen: CGRect) -> CGRect {
        let maximumX = max(screen.minX, screen.maxX - frame.width)
        let maximumY = max(screen.minY, screen.maxY - frame.height)
        return CGRect(
            x: min(max(frame.minX, screen.minX), maximumX),
            y: min(max(frame.minY, screen.minY), maximumY),
            width: frame.width,
            height: frame.height
        )
    }

    private static func isValid(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite &&
            frame.origin.y.isFinite &&
            frame.width.isFinite &&
            frame.height.isFinite &&
            frame.width > 0 &&
            frame.height > 0
    }
}
