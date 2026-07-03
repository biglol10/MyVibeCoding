import Foundation

public struct FileOutputService {
    private let fileManager: FileManager
    private let dateFormatter: DateFormatter
    private let smartDateFormatter: DateFormatter

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        self.dateFormatter = formatter

        let smartFormatter = DateFormatter()
        smartFormatter.locale = Locale(identifier: "en_US_POSIX")
        smartFormatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        self.smartDateFormatter = smartFormatter
    }

    public func screenshotFilename(for date: Date = Date()) -> String {
        "Screenshot \(dateFormatter.string(from: date)).png"
    }

    public func screenshotFilename(
        for date: Date = Date(),
        settings: AppSettings,
        context: FileNamingContext?
    ) -> String {
        smartFilename(
            fallback: screenshotFilename(for: date),
            date: date,
            settings: settings,
            context: context,
            suffix: nil,
            fileExtension: "png"
        )
    }

    public func recordingFilename(for date: Date = Date()) -> String {
        "Recording \(dateFormatter.string(from: date)).mp4"
    }

    public func recordingFilename(
        for date: Date = Date(),
        settings: AppSettings,
        context: FileNamingContext?
    ) -> String {
        smartFilename(
            fallback: recordingFilename(for: date),
            date: date,
            settings: settings,
            context: context,
            suffix: nil,
            fileExtension: "mp4"
        )
    }

    public func trimmedRecordingFilename(
        for date: Date = Date(),
        settings: AppSettings,
        context: FileNamingContext?
    ) -> String {
        smartFilename(
            fallback: "Trimmed \(dateFormatter.string(from: date)).mp4",
            date: date,
            settings: settings,
            context: context,
            suffix: "Trimmed",
            fileExtension: "mp4"
        )
    }

    public func gifRecordingFilename(
        for date: Date = Date(),
        settings: AppSettings,
        context: FileNamingContext?
    ) -> String {
        smartFilename(
            fallback: "GIF \(dateFormatter.string(from: date)).gif",
            date: date,
            settings: settings,
            context: context,
            suffix: "GIF",
            fileExtension: "gif"
        )
    }

    public func resolvedOutputDirectory(preferredPath: String) -> URL {
        let preferredURL = URL(fileURLWithPath: preferredPath, isDirectory: true)
        if directoryExists(at: preferredURL) {
            return preferredURL
        }

        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
    }

    public func screenshotURL(settings: AppSettings, date: Date = Date(), context: FileNamingContext? = nil) -> URL {
        resolvedOutputDirectory(preferredPath: settings.screenshotFolderPath)
            .appendingPathComponent(screenshotFilename(for: date, settings: settings, context: context))
    }

    public func recordingURL(settings: AppSettings, date: Date = Date(), context: FileNamingContext? = nil) -> URL {
        resolvedOutputDirectory(preferredPath: settings.recordingFolderPath)
            .appendingPathComponent(recordingFilename(for: date, settings: settings, context: context))
    }

    public func availableRecordingURL(settings: AppSettings, date: Date = Date(), context: FileNamingContext? = nil) -> URL {
        uniqueFileURL(for: recordingURL(settings: settings, date: date, context: context))
    }

    public func trimmedRecordingURL(settings: AppSettings, date: Date = Date(), context: FileNamingContext? = nil) -> URL {
        uniqueFileURL(
            for: resolvedOutputDirectory(preferredPath: settings.recordingFolderPath)
                .appendingPathComponent(trimmedRecordingFilename(for: date, settings: settings, context: context))
        )
    }

    public func gifRecordingURL(settings: AppSettings, date: Date = Date(), context: FileNamingContext? = nil) -> URL {
        uniqueFileURL(
            for: resolvedOutputDirectory(preferredPath: settings.recordingFolderPath)
                .appendingPathComponent(gifRecordingFilename(for: date, settings: settings, context: context))
        )
    }

    public func temporaryRecordingURL() -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
    }

    public func writeScreenshotData(
        _ data: Data,
        settings: AppSettings,
        date: Date = Date(),
        context: FileNamingContext? = nil
    ) throws -> URL {
        let outputURL = uniqueFileURL(for: screenshotURL(settings: settings, date: date, context: context))
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    public func writeRecordingData(
        _ data: Data,
        settings: AppSettings,
        date: Date = Date(),
        context: FileNamingContext? = nil
    ) throws -> URL {
        let outputURL = uniqueFileURL(for: recordingURL(settings: settings, date: date, context: context))
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    public func moveRecordingFile(
        from sourceURL: URL,
        settings: AppSettings,
        date: Date = Date(),
        context: FileNamingContext? = nil
    ) throws -> URL {
        let preferredOutputURL = recordingURL(settings: settings, date: date, context: context)
        if sourceURL.standardizedFileURL == preferredOutputURL.standardizedFileURL {
            return preferredOutputURL
        }

        let outputURL = uniqueFileURL(for: preferredOutputURL)
        try fileManager.moveItem(at: sourceURL, to: outputURL)
        return outputURL
    }

    private func directoryExists(at url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    private func uniqueFileURL(for preferredURL: URL) -> URL {
        guard fileManager.fileExists(atPath: preferredURL.path) else {
            return preferredURL
        }

        let directory = preferredURL.deletingLastPathComponent()
        let baseName = preferredURL.deletingPathExtension().lastPathComponent
        let fileExtension = preferredURL.pathExtension
        var suffix = 2

        while true {
            let candidateName = fileExtension.isEmpty
                ? "\(baseName) \(suffix)"
                : "\(baseName) \(suffix).\(fileExtension)"
            let candidateURL = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            suffix += 1
        }
    }

    private func smartFilename(
        fallback: String,
        date: Date,
        settings: AppSettings,
        context: FileNamingContext?,
        suffix: String?,
        fileExtension: String
    ) -> String {
        guard settings.smartFilenamesEnabled,
              let context,
              !context.displayTitle.isEmpty
        else {
            return fallback
        }

        var parts = [
            smartDateFormatter.string(from: date),
            sanitizeFilenameComponent(context.applicationName)
        ]

        if let windowTitle = context.windowTitle {
            let sanitizedTitle = sanitizeFilenameComponent(windowTitle)
            if !sanitizedTitle.isEmpty {
                parts.append(sanitizedTitle)
            }
        }

        if let suffix {
            parts.append(suffix)
        }

        let baseName = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
        return "\(String(baseName.prefix(180))).\(fileExtension)"
    }

    private func sanitizeFilenameComponent(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        let replaced = value
            .components(separatedBy: invalidCharacters)
            .joined(separator: " ")
        return replaced
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
