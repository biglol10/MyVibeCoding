import AppKit
import Foundation

public enum FileDropPasteboardReader {
    private static let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    public static let acceptedTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        filenamesType
    ]

    public static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        var urls: [URL] = []

        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [NSURL] ?? []
        urls.append(contentsOf: objects.map { ($0 as URL).standardizedFileURL })

        if let paths = pasteboard.propertyList(forType: filenamesType) as? [String] {
            urls.append(contentsOf: paths.map { URL(fileURLWithPath: $0).standardizedFileURL })
        }

        if let fileURLString = pasteboard.string(forType: .fileURL),
           let url = URL(string: fileURLString),
           url.isFileURL {
            urls.append(url.standardizedFileURL)
        }

        return deduplicated(urls)
    }

    private static func deduplicated(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        var result: [URL] = []
        for url in urls where !seen.contains(url) {
            seen.insert(url)
            result.append(url)
        }
        return result
    }
}
