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
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) ?? content.displays.first else {
            throw ScreenshotError.noDisplayAvailable
        }

        let currentProcessID = pid_t(ProcessInfo.processInfo.processIdentifier)
        let excludedWindows = content.windows.filter { window in
            window.owningApplication?.processID == currentProcessID
        }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = selection.sourceRectInPixels
        configuration.width = selection.pixelWidth
        configuration.height = selection.pixelHeight
        configuration.showsCursor = true

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ScreenshotError.pngEncodingFailed
        }

        return ScreenshotResult(pngData: pngData)
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
