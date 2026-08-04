import AppKit
import Foundation
@preconcurrency import ScreenCaptureKit

public struct ScreenshotResult: Equatable, Sendable {
    public let pngData: Data
    public let createdAt: Date

    public init(pngData: Data, createdAt: Date = Date()) {
        self.pngData = pngData
        self.createdAt = createdAt
    }
}

@MainActor
public protocol ScreenshotServicing {
    func captureImage(selection: CaptureSelection) async throws -> ScreenshotResult
}

public struct ScreenCaptureKitScreenshotService: ScreenshotServicing {
    public init() {}

    public func captureImage(selection: CaptureSelection) async throws -> ScreenshotResult {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) ?? content.displays.first else {
            throw ScreenshotError.noDisplayAvailable
        }

        let currentProcessID = pid_t(ProcessInfo.processInfo.processIdentifier)
        let currentBundleIdentifier = Bundle.main.bundleIdentifier
        let excludedApplications = content.applications.filter { application in
            ScreenCaptureApplicationMatcher.matches(
                applicationProcessID: application.processID,
                applicationBundleIdentifier: application.bundleIdentifier,
                currentProcessID: currentProcessID,
                currentBundleIdentifier: currentBundleIdentifier
            )
        }
        guard !excludedApplications.isEmpty else {
            throw ScreenCaptureContentFilterError.currentApplicationUnavailable
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )
        let geometry = ScreenCaptureOutputGeometry(selection: selection, pointPixelScale: CGFloat(filter.pointPixelScale))
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = geometry.sourceRectInPoints
        configuration.width = geometry.pixelWidth
        configuration.height = geometry.pixelHeight
        configuration.showsCursor = true

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let croppedImage = ScreenshotImageCropper.crop(image, to: geometry) ?? image
        let bitmap = NSBitmapImageRep(cgImage: croppedImage)
        guard let pngData = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
            throw ScreenshotError.pngEncodingFailed
        }

        return ScreenshotResult(pngData: pngData)
    }
}

enum ScreenshotImageCropper {
    static func crop(_ image: CGImage, to geometry: ScreenCaptureOutputGeometry) -> CGImage? {
        let expectedWidth = geometry.pixelWidth
        let expectedHeight = geometry.pixelHeight

        guard image.width != expectedWidth || image.height != expectedHeight else {
            return image
        }

        guard image.width >= expectedWidth, image.height >= expectedHeight else {
            return image
        }

        return image.cropping(to: CGRect(x: 0, y: 0, width: expectedWidth, height: expectedHeight))
    }
}

public enum ScreenshotError: LocalizedError, Equatable {
    case noDisplayAvailable
    case pngEncodingFailed

    public var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            return "No display is available for capture."
        case .pngEncodingFailed:
            return "The captured image could not be encoded as PNG."
        }
    }
}
