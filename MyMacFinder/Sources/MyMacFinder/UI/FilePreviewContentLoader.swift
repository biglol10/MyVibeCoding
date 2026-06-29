import Foundation
import UniformTypeIdentifiers

struct FilePreviewReadResult: Sendable {
    let data: Data
    let fileSize: Int64?
}

enum FilePreviewContentLoader {
    typealias FileReader = @Sendable (_ url: URL, _ readLimit: Int) throws -> FilePreviewReadResult

    static let defaultByteLimit = 16 * 1024

    private static let textExtensions: Set<String> = [
        "bash", "c", "conf", "cpp", "cs", "css", "csv", "env", "fish", "go", "h", "hpp",
        "html", "ini", "java", "js", "json", "jsx", "kt", "log", "m", "markdown", "md",
        "mm", "php", "plist", "py", "rb", "rs", "scss", "sh", "sql", "swift", "toml",
        "ts", "tsx", "tsv", "txt", "xml", "yaml", "yml", "zsh"
    ]

    private static let textFileNames: Set<String> = [
        ".env", ".gitignore", ".zshrc", "dockerfile", "gemfile", "makefile", "podfile", "rakefile"
    ]

    static func loadContent(
        for entry: FileEntry,
        byteLimit: Int = defaultByteLimit,
        fileReader: @escaping FileReader = readPreviewData
    ) async -> FilePreviewContent {
        let readTask = Task.detached(priority: .utility) {
            guard !Task.isCancelled else {
                return FilePreviewContent.visual
            }
            guard shouldAttemptTextPreview(for: entry) else {
                return .visual
            }

            do {
                let readLimit = max(byteLimit, 0)
                let result = try fileReader(entry.url.standardizedFileURL, readLimit)
                guard !Task.isCancelled else {
                    return .visual
                }
                guard !result.data.contains(0) else {
                    return .unsupported(message: "Binary file preview is not available.")
                }

                let previewData = result.data.prefix(readLimit)
                guard let decoded = decode(previewData) else {
                    return .unsupported(message: "Cannot read text preview.")
                }

                let isTruncated = result.data.count > readLimit || (result.fileSize ?? 0) > readLimit
                return .text(
                    FileTextPreview(
                        text: decoded.text,
                        isTruncated: isTruncated,
                        byteLimit: readLimit,
                        encodingName: decoded.encodingName
                    )
                )
            } catch {
                return .unsupported(message: "Cannot read text preview.")
            }
        }

        return await withTaskCancellationHandler {
            await readTask.value
        } onCancel: {
            readTask.cancel()
        }
    }

    private static func readPreviewData(for url: URL, readLimit: Int) throws -> FilePreviewReadResult {
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        let bytesToRead = readLimit == Int.max ? Int.max : readLimit + 1
        let data = try handle.read(upToCount: bytesToRead) ?? Data()
        return FilePreviewReadResult(data: data, fileSize: fileSize)
    }

    private static func shouldAttemptTextPreview(for entry: FileEntry) -> Bool {
        guard !entry.isDirectoryLike, !entry.isArchiveBacked, entry.isReadable else {
            return false
        }

        let fileName = entry.name.lowercased()
        if textFileNames.contains(fileName) {
            return true
        }

        let fileExtension = entry.fileExtension.lowercased()
        if textExtensions.contains(fileExtension) {
            return true
        }

        if let contentType = try? entry.url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType.conforms(to: .text)
                || contentType.conforms(to: .sourceCode)
                || contentType.conforms(to: .json)
                || contentType.conforms(to: .xml)
                || contentType == .commaSeparatedText
        }

        return entry.typeDescription.localizedCaseInsensitiveContains("text")
    }

    private static func decode(_ data: Data.SubSequence) -> (text: String, encodingName: String)? {
        let previewData = Data(data)
        if let text = String(data: previewData, encoding: .utf8) {
            return (text, "UTF-8")
        }
        if let text = String(data: previewData, encoding: .utf16LittleEndian) {
            return (text, "UTF-16")
        }
        if let text = String(data: previewData, encoding: .utf16BigEndian) {
            return (text, "UTF-16")
        }
        return nil
    }
}
