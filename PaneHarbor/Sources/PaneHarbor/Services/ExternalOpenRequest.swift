import AppKit
import Foundation

/// Only local, absolute paths are accepted. No command, web URL, or remote file host is executed.
public enum ExternalOpenRequest {
    public static func fileURL(from url: URL) throws -> URL {
        if url.isFileURL {
            guard url.host == nil || url.host == "" || url.host == "localhost",
                  url.path.hasPrefix("/"), !url.path.contains("\0") else {
                throw ExplorerError.invalidPath(url.absoluteString)
            }
            return URL(fileURLWithPath: url.path).standardizedFileURL
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "paneharbor", components.host == "open",
              components.path.isEmpty, components.fragment == nil,
              components.user == nil, components.password == nil, components.port == nil,
              let items = components.queryItems, items.count == 1,
              items[0].name == "path", let path = items[0].value,
              path.hasPrefix("/"), !path.contains("\0") else {
            throw ExplorerError.invalidPath(url.absoluteString)
        }
        // URLComponents decodes exactly once: literal %, +, # and Unicode survive the handoff.
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    public static func fileURL(fromPathText text: String) throws -> URL {
        guard !text.contains("\0") else { throw ExplorerError.invalidPath(text) }
        if text.hasPrefix("/") {
            return URL(fileURLWithPath: text).standardizedFileURL
        }
        if text.hasPrefix("~/") {
            return URL(fileURLWithPath: (text as NSString).expandingTildeInPath).standardizedFileURL
        }
        guard let url = URL(string: text) else { throw ExplorerError.invalidPath(text) }
        return try fileURL(from: url)
    }

    @MainActor
    static func fileURLs(from pasteboard: NSPasteboard) throws -> [URL] {
        if let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !files.isEmpty {
            return try files.map { try fileURL(from: $0) }
        }
        let legacyFiles = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        if let paths = pasteboard.propertyList(forType: legacyFiles) as? [String], !paths.isEmpty {
            return try paths.map { try fileURL(fromPathText: $0) }
        }
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            throw ExplorerError.operationFailed("Select a local file, folder, or absolute path first.")
        }
        // A whole path is tried first, so even a filename containing a newline can be passed.
        if let url = try? fileURL(fromPathText: text), FileManager.default.fileExists(atPath: url.path) {
            return [url]
        }
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard !lines.isEmpty else { throw ExplorerError.invalidPath(text) }
        return try lines.map { try fileURL(fromPathText: $0) }
    }
}
