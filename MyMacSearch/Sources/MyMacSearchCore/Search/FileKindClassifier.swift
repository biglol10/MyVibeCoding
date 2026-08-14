import Foundation

public enum FileKindClassifier {
    private static let images: Set<String> = ["avif", "bmp", "gif", "heic", "jpeg", "jpg", "png", "svg", "tif", "tiff", "webp"]
    private static let videos: Set<String> = ["avi", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "webm"]
    private static let audio: Set<String> = ["aac", "aiff", "flac", "m4a", "mp3", "ogg", "wav"]
    private static let archives: Set<String> = ["7z", "bz2", "dmg", "gz", "rar", "tar", "tgz", "xz", "zip"]
    private static let code: Set<String> = [
        "c", "cc", "cpp", "css", "go", "h", "hpp", "html", "java", "js", "json", "jsx",
        "kt", "kts", "m", "mm", "php", "py", "rb", "rs", "sh", "sql", "swift", "ts", "tsx", "xml", "yaml", "yml"
    ]
    private static let documents: Set<String> = ["csv", "doc", "docx", "key", "md", "numbers", "pages", "ppt", "pptx", "rtf", "txt", "xls", "xlsx"]

    public static func kind(name: String, isDirectory: Bool, isPackage: Bool) -> IndexedFileKind {
        if isPackage || name.lowercased().hasSuffix(".app") {
            return .application
        }
        if isDirectory {
            return .folder
        }

        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        if ext == "pdf" { return .pdf }
        if images.contains(ext) { return .image }
        if videos.contains(ext) { return .video }
        if audio.contains(ext) { return .audio }
        if archives.contains(ext) { return .archive }
        if code.contains(ext) { return .code }
        if documents.contains(ext) { return .document }
        return .other
    }
}
