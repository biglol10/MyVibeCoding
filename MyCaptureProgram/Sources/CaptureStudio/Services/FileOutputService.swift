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

    public func availableRecordingURL(settings: AppSettings, date: Date = Date()) -> URL {
        uniqueFileURL(for: recordingURL(settings: settings, date: date))
    }

    public func temporaryRecordingURL() -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
    }

    public func writeScreenshotData(_ data: Data, settings: AppSettings, date: Date = Date()) throws -> URL {
        let outputURL = uniqueFileURL(for: screenshotURL(settings: settings, date: date))
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    public func writeRecordingData(_ data: Data, settings: AppSettings, date: Date = Date()) throws -> URL {
        let outputURL = uniqueFileURL(for: recordingURL(settings: settings, date: date))
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    public func moveRecordingFile(from sourceURL: URL, settings: AppSettings, date: Date = Date()) throws -> URL {
        let preferredOutputURL = recordingURL(settings: settings, date: date)
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
}
