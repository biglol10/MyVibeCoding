import Foundation

public struct FileOutputService {
    private let fileManager: FileManager
    private let dateFormatter: DateFormatter

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        self.dateFormatter = formatter
    }

    public func screenshotFilename(for date: Date = Date()) -> String {
        "Screenshot \(dateFormatter.string(from: date)).png"
    }

    public func recordingFilename(for date: Date = Date()) -> String {
        "Recording \(dateFormatter.string(from: date)).mp4"
    }

    public func resolvedOutputDirectory(preferredPath: String) -> URL {
        let preferredURL = URL(fileURLWithPath: preferredPath, isDirectory: true)
        if directoryExists(at: preferredURL) {
            return preferredURL
        }

        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
    }

    public func screenshotURL(settings: AppSettings, date: Date = Date()) -> URL {
        resolvedOutputDirectory(preferredPath: settings.screenshotFolderPath)
            .appendingPathComponent(screenshotFilename(for: date))
    }

    public func recordingURL(settings: AppSettings, date: Date = Date()) -> URL {
        resolvedOutputDirectory(preferredPath: settings.recordingFolderPath)
            .appendingPathComponent(recordingFilename(for: date))
    }

    public func temporaryRecordingURL() -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
    }

    public func writeScreenshotData(_ data: Data, settings: AppSettings, date: Date = Date()) throws -> URL {
        let outputURL = screenshotURL(settings: settings, date: date)
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    public func writeRecordingData(_ data: Data, settings: AppSettings, date: Date = Date()) throws -> URL {
        let outputURL = recordingURL(settings: settings, date: date)
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    public func moveRecordingFile(from sourceURL: URL, settings: AppSettings, date: Date = Date()) throws -> URL {
        let outputURL = recordingURL(settings: settings, date: date)
        if sourceURL.standardizedFileURL == outputURL.standardizedFileURL {
            return outputURL
        }

        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        try fileManager.moveItem(at: sourceURL, to: outputURL)
        return outputURL
    }

    private func directoryExists(at url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
