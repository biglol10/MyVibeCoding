import Foundation
import Darwin

public enum FileOutputError: LocalizedError, Equatable {
    case outputDirectoryUnavailable(String)
    case outputDirectoryNotWritable(String)
    case unableToAllocateFilename
    case sourceFileChanged

    public var errorDescription: String? {
        switch self {
        case .outputDirectoryUnavailable(let path):
            return "The configured output folder is unavailable: \(path)"
        case .outputDirectoryNotWritable(let path):
            return "The configured output folder is not writable: \(path)"
        case .unableToAllocateFilename:
            return "A unique output filename could not be allocated."
        case .sourceFileChanged:
            return "The source file changed on disk."
        }
    }
}

public struct FileOutputService: @unchecked Sendable {
    private let fileManager: FileManager
    private let dateFormatter: DateFormatter
    private let smartDateFormatter: DateFormatter
    private let operationObserver: (@Sendable () -> Void)?

    public init(fileManager: FileManager = .default) {
        self.init(fileManager: fileManager, operationObserver: nil)
    }

    init(
        fileManager: FileManager,
        operationObserver: (@Sendable () -> Void)?
    ) {
        self.fileManager = fileManager
        self.operationObserver = operationObserver

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

    public func resolvedOutputDirectory(preferredPath: String) throws -> URL {
        let preferredURL = URL(fileURLWithPath: preferredPath, isDirectory: true)
        guard !preferredPath.isEmpty, directoryExists(at: preferredURL) else {
            throw FileOutputError.outputDirectoryUnavailable(preferredPath)
        }
        guard fileManager.isWritableFile(atPath: preferredURL.path) else {
            throw FileOutputError.outputDirectoryNotWritable(preferredPath)
        }

        return preferredURL
    }

    public func screenshotURL(settings: AppSettings, date: Date = Date(), context: FileNamingContext? = nil) throws -> URL {
        try resolvedOutputDirectory(preferredPath: settings.screenshotFolderPath)
            .appendingPathComponent(screenshotFilename(for: date, settings: settings, context: context))
    }

    public func recordingURL(settings: AppSettings, date: Date = Date(), context: FileNamingContext? = nil) throws -> URL {
        try resolvedOutputDirectory(preferredPath: settings.recordingFolderPath)
            .appendingPathComponent(recordingFilename(for: date, settings: settings, context: context))
    }

    public func availableRecordingURL(settings: AppSettings, date: Date = Date(), context: FileNamingContext? = nil) throws -> URL {
        let preferredURL = try recordingURL(settings: settings, date: date, context: context)
        return candidateURL(for: preferredURL, suffix: " \(UUID().uuidString.prefix(8))")
    }

    public func trimmedRecordingURL(settings: AppSettings, date: Date = Date(), context: FileNamingContext? = nil) throws -> URL {
        uniqueFileURL(
            for: try resolvedOutputDirectory(preferredPath: settings.recordingFolderPath)
                .appendingPathComponent(trimmedRecordingFilename(for: date, settings: settings, context: context))
        )
    }

    public func gifRecordingURL(settings: AppSettings, date: Date = Date(), context: FileNamingContext? = nil) throws -> URL {
        uniqueFileURL(
            for: try resolvedOutputDirectory(preferredPath: settings.recordingFolderPath)
                .appendingPathComponent(gifRecordingFilename(for: date, settings: settings, context: context))
        )
    }

    public func temporaryRecordingURL() -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
    }

    public func temporaryGIFURL() -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("gif")
    }

    public func writeScreenshotData(
        _ data: Data,
        settings: AppSettings,
        date: Date = Date(),
        context: FileNamingContext? = nil
    ) throws -> URL {
        let outputURL = try screenshotURL(settings: settings, date: date, context: context)
        return try writeWithoutOverwriting(data, preferredURL: outputURL)
    }

    public func writeRecordingData(
        _ data: Data,
        settings: AppSettings,
        date: Date = Date(),
        context: FileNamingContext? = nil
    ) throws -> URL {
        let outputURL = try recordingURL(settings: settings, date: date, context: context)
        return try writeWithoutOverwriting(data, preferredURL: outputURL)
    }

    public func moveRecordingFile(
        from sourceURL: URL,
        expectedSourceIdentity: CaptureFileIdentity? = nil,
        settings: AppSettings,
        date: Date = Date(),
        context: FileNamingContext? = nil
    ) throws -> URL {
        operationObserver?()
        let sourceIdentity = try validatedSourceIdentity(
            at: sourceURL,
            expected: expectedSourceIdentity
        )
        let preferredOutputURL = try recordingURL(settings: settings, date: date, context: context)
        if sourceURL.standardizedFileURL == preferredOutputURL.standardizedFileURL {
            return preferredOutputURL
        }

        return try moveWithoutOverwriting(
            from: sourceURL,
            preferredURL: preferredOutputURL,
            expectedSourceIdentity: sourceIdentity
        )
    }

    public func moveTrimmedRecordingFile(
        from sourceURL: URL,
        expectedSourceIdentity: CaptureFileIdentity? = nil,
        settings: AppSettings,
        date: Date = Date(),
        context: FileNamingContext? = nil
    ) throws -> URL {
        operationObserver?()
        let sourceIdentity = try validatedSourceIdentity(
            at: sourceURL,
            expected: expectedSourceIdentity
        )
        let preferredURL = try resolvedOutputDirectory(preferredPath: settings.recordingFolderPath)
            .appendingPathComponent(trimmedRecordingFilename(for: date, settings: settings, context: context))
        return try moveWithoutOverwriting(
            from: sourceURL,
            preferredURL: preferredURL,
            expectedSourceIdentity: sourceIdentity
        )
    }

    public func moveGIFFile(
        from sourceURL: URL,
        expectedSourceIdentity: CaptureFileIdentity? = nil,
        settings: AppSettings,
        date: Date = Date(),
        context: FileNamingContext? = nil
    ) throws -> URL {
        operationObserver?()
        let sourceIdentity = try validatedSourceIdentity(
            at: sourceURL,
            expected: expectedSourceIdentity
        )
        let preferredURL = try resolvedOutputDirectory(preferredPath: settings.recordingFolderPath)
            .appendingPathComponent(gifRecordingFilename(for: date, settings: settings, context: context))
        return try moveWithoutOverwriting(
            from: sourceURL,
            preferredURL: preferredURL,
            expectedSourceIdentity: sourceIdentity
        )
    }

    public func moveRecordingFileAsync(
        from sourceURL: URL,
        expectedSourceIdentity: CaptureFileIdentity? = nil,
        settings: AppSettings,
        date: Date = Date(),
        context: FileNamingContext? = nil
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try moveRecordingFile(
                from: sourceURL,
                expectedSourceIdentity: expectedSourceIdentity,
                settings: settings,
                date: date,
                context: context
            )
        }.value
    }

    public func moveTrimmedRecordingFileAsync(
        from sourceURL: URL,
        expectedSourceIdentity: CaptureFileIdentity? = nil,
        settings: AppSettings,
        date: Date = Date(),
        context: FileNamingContext? = nil
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try moveTrimmedRecordingFile(
                from: sourceURL,
                expectedSourceIdentity: expectedSourceIdentity,
                settings: settings,
                date: date,
                context: context
            )
        }.value
    }

    public func moveGIFFileAsync(
        from sourceURL: URL,
        expectedSourceIdentity: CaptureFileIdentity? = nil,
        settings: AppSettings,
        date: Date = Date(),
        context: FileNamingContext? = nil
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try moveGIFFile(
                from: sourceURL,
                expectedSourceIdentity: expectedSourceIdentity,
                settings: settings,
                date: date,
                context: context
            )
        }.value
    }

    private func directoryExists(at url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    private func uniqueFileURL(for preferredURL: URL) -> URL {
        for index in 1...10_000 {
            let suffix = index == 1 ? "" : " \(index)"
            let candidateURL = candidateURL(for: preferredURL, suffix: suffix)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }
        return candidateURL(for: preferredURL, suffix: " \(UUID().uuidString)")
    }

    private func writeWithoutOverwriting(_ data: Data, preferredURL: URL) throws -> URL {
        let temporaryURL = try makeSiblingTemporaryURL(for: preferredURL)
        var temporaryFileExists = false
        defer {
            if temporaryFileExists {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        try writeToNewFile(data, at: temporaryURL)
        temporaryFileExists = true

        for index in 1...10_000 {
            let suffix = index == 1 ? "" : " \(index)"
            let candidateURL = candidateURL(for: preferredURL, suffix: suffix)
            do {
                try publishExclusively(from: temporaryURL, to: candidateURL)
                temporaryFileExists = false
                synchronizeDirectory(containing: candidateURL)
                return candidateURL
            } catch where isFileExistsError(error) {
                continue
            }
        }
        throw FileOutputError.unableToAllocateFilename
    }

    private func writeToNewFile(_ data: Data, at url: URL) throws {
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                return -1
            }
            return Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        }
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var shouldRemovePartialFile = true
        defer {
            Darwin.close(descriptor)
            if shouldRemovePartialFile {
                try? fileManager.removeItem(at: url)
            }
        }

        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }
            var writtenByteCount = 0
            while writtenByteCount < rawBuffer.count {
                let result = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: writtenByteCount),
                    rawBuffer.count - writtenByteCount
                )
                if result < 0 {
                    if errno == EINTR {
                        continue
                    }
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                writtenByteCount += result
            }
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        shouldRemovePartialFile = false
    }

    private func moveWithoutOverwriting(
        from sourceURL: URL,
        preferredURL: URL,
        expectedSourceIdentity: CaptureFileIdentity
    ) throws -> URL {
        for index in 1...10_000 {
            let suffix = index == 1 ? "" : " \(index)"
            let candidateURL = candidateURL(for: preferredURL, suffix: suffix)
            do {
                try publishExclusively(
                    from: sourceURL,
                    to: candidateURL,
                    expectedSourceIdentity: expectedSourceIdentity
                )
                synchronizeDirectory(containing: candidateURL)
                return candidateURL
            } catch where isFileExistsError(error) {
                continue
            }
        }
        throw FileOutputError.unableToAllocateFilename
    }

    private func validatedSourceIdentity(
        at sourceURL: URL,
        expected expectedIdentity: CaptureFileIdentity?
    ) throws -> CaptureFileIdentity {
        let identity = try expectedIdentity ?? CaptureFileIdentity.existingFile(at: sourceURL)
        guard identity.matchesExistingFile(at: sourceURL) else {
            throw FileOutputError.sourceFileChanged
        }
        return identity
    }

    private func makeSiblingTemporaryURL(for preferredURL: URL) throws -> URL {
        let directory = preferredURL.deletingLastPathComponent()
        for _ in 0..<100 {
            let candidate = directory.appendingPathComponent(".CaptureStudio-\(UUID().uuidString).tmp")
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        throw FileOutputError.unableToAllocateFilename
    }

    private func publishExclusively(
        from sourceURL: URL,
        to destinationURL: URL,
        expectedSourceIdentity: CaptureFileIdentity? = nil
    ) throws {
        try ExclusiveFilePublisher.publish(
            from: sourceURL,
            to: destinationURL,
            expectedSourceIdentity: expectedSourceIdentity
        )
    }

    private func synchronizeDirectory(containing url: URL) {
        let directoryURL = url.deletingLastPathComponent()
        let descriptor = directoryURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                return -1
            }
            return Darwin.open(path, O_RDONLY)
        }
        guard descriptor >= 0 else {
            return
        }
        _ = Darwin.fsync(descriptor)
        Darwin.close(descriptor)
    }

    private func candidateURL(for preferredURL: URL, suffix: String) -> URL {
        let directory = preferredURL.deletingLastPathComponent()
        let fileExtension = preferredURL.pathExtension
        let extensionByteCount = fileExtension.isEmpty ? 0 : fileExtension.utf8.count + 1
        let suffixByteCount = suffix.utf8.count
        let maximumBaseBytes = max(1, 255 - extensionByteCount - suffixByteCount)
        let baseName = truncateToUTF8ByteCount(
            preferredURL.deletingPathExtension().lastPathComponent,
            maximumBytes: maximumBaseBytes
        )
        let candidateName = fileExtension.isEmpty
            ? "\(baseName)\(suffix)"
            : "\(baseName)\(suffix).\(fileExtension)"
        return directory.appendingPathComponent(candidateName)
    }

    private func isFileExistsError(_ error: Error) -> Bool {
        let error = error as NSError
        return (error.domain == NSCocoaErrorDomain
                && error.code == CocoaError.fileWriteFileExists.rawValue)
            || (error.domain == NSPOSIXErrorDomain && error.code == EEXIST)
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
        let maximumBaseBytes = max(1, 255 - fileExtension.utf8.count - 1)
        return "\(truncateToUTF8ByteCount(baseName, maximumBytes: maximumBaseBytes)).\(fileExtension)"
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

    private func truncateToUTF8ByteCount(_ value: String, maximumBytes: Int) -> String {
        var result = ""
        var byteCount = 0
        for character in value {
            let characterString = String(character)
            let characterBytes = characterString.utf8.count
            guard byteCount + characterBytes <= maximumBytes else {
                break
            }
            result.append(character)
            byteCount += characterBytes
        }
        return result
    }
}
