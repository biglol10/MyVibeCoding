import Foundation

public enum MainWindowPresentation {
    public static let mainWindowMinimumWidth: Double = 710

    public struct QuickOptionsControl: Equatable, Sendable {
        public let title: String
        public let minimumWidth: Double
    }

    public struct RecentResult: Equatable {
        public let title: String
        public let detail: String
        public let systemImage: String
        public let canCopy: Bool
        public let canReveal: Bool
        public let canSave: Bool
        public let canDelete: Bool
        public let requiresSave: Bool
    }

    public struct RecordingPreview: Equatable {
        public let fileURL: URL?
        public let title: String
        public let detail: String

        public var canPlay: Bool {
            fileURL != nil
        }
    }

    public static let quickOptionsControl = QuickOptionsControl(
        title: "Options",
        minimumWidth: 128
    )

    public static func outputSummary(settings: AppSettings) -> String {
        var parts = [
            folderName(from: settings.screenshotFolderPath),
            "PNG",
            "\(settings.defaultDelaySeconds)s"
        ]
        if settings.copyCapturedImageToClipboard {
            parts.append("Clipboard")
        }
        return parts.joined(separator: " · ")
    }

    public static func recordingSummary(settings: AppSettings) -> String {
        var parts = [
            "MP4",
            "\(settings.recordingDurationSeconds)s",
            "Delay \(settings.countdownSeconds)s"
        ]
        if settings.recordingQuality == .high {
            parts.append("High")
        }
        return parts.joined(separator: " · ")
    }

    public static func recentResult(for document: EditorDocument, statusMessage: String?) -> RecentResult {
        switch document.kind {
        case .screenshot:
            return RecentResult(
                title: document.isDirty ? "Unsaved screenshot" : "Screenshot saved",
                detail: statusMessage ?? (document.isDirty ? "Press Save to write the file." : fileLocationText(for: document)),
                systemImage: "photo",
                canCopy: true,
                canReveal: document.fileURL != nil,
                canSave: true,
                canDelete: true,
                requiresSave: document.isDirty
            )
        case .recording:
            let canSave = document.isDirty && document.fileURL != nil
            return RecentResult(
                title: document.isDirty ? "Unsaved recording" : "Recording saved",
                detail: statusMessage ?? (document.isDirty ? "Press Save to write the file." : fileLocationText(for: document)),
                systemImage: "record.circle",
                canCopy: false,
                canReveal: document.fileURL != nil,
                canSave: canSave,
                canDelete: true,
                requiresSave: canSave
            )
        }
    }

    public static func recordingPreview(for document: EditorDocument, statusMessage: String?) -> RecordingPreview {
        RecordingPreview(
            fileURL: document.fileURL,
            title: document.fileURL == nil ? "Recording captured" : (document.isDirty ? "Unsaved recording" : "Recording saved"),
            detail: statusMessage ?? "Recording is ready."
        )
    }

    private static func folderName(from path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        return name.isEmpty ? path : name
    }

    private static func fileLocationText(for document: EditorDocument) -> String {
        guard let fileURL = document.fileURL else {
            return "No file yet."
        }
        return "Saved to \(folderName(from: fileURL.deletingLastPathComponent().path))"
    }
}
