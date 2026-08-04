import CoreGraphics
import Foundation

public protocol CaptureMetadataServicing: Sendable {
    func namingContext(for selection: CaptureSelection) -> FileNamingContext?
}

public struct CoreGraphicsCaptureMetadataService: CaptureMetadataServicing {
    public init() {}

    public func namingContext(for selection: CaptureSelection) -> FileNamingContext? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let currentProcessID = Int(ProcessInfo.processInfo.processIdentifier)
        let selectionRect = selection.rect
        let mainDisplayBounds = CGDisplayBounds(CGMainDisplayID())
        let rankedWindows = windowList.compactMap { info -> (context: FileNamingContext, score: CGFloat)? in
            guard let ownerName = info[kCGWindowOwnerName as String] as? String,
                  !ownerName.isEmpty,
                  let processID = info[kCGWindowOwnerPID as String] as? Int,
                  processID != currentProcessID,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let alpha = info[kCGWindowAlpha as String] as? Double,
                  alpha > 0,
                  let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any]
            else {
                return nil
            }

            var bounds = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDictionary as CFDictionary, &bounds) else {
                return nil
            }

            let appKitBounds = ScreenCoordinateConverter.appKitRect(
                fromQuartz: bounds,
                mainDisplayBounds: mainDisplayBounds
            )
            let intersection = appKitBounds.intersection(selectionRect)
            guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else {
                return nil
            }

            let title = (info[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let context = FileNamingContext(
                applicationName: ownerName,
                windowTitle: title?.isEmpty == false ? title : nil
            )
            return (context, intersection.width * intersection.height)
        }

        return rankedWindows.max { $0.score < $1.score }?.context
    }
}
