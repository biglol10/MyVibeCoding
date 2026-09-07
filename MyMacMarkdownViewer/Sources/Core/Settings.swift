import Foundation

public enum ThemeChoice: String, Codable, Sendable, CaseIterable {
    case dark, night, light, system
    public var label: String { switch self { case .dark: "다크"; case .night: "Night · 청회색"; case .light: "라이트"; case .system: "시스템 설정 따르기" } }
}

public struct ReadingSettings: Codable, Equatable, Sendable {
    public var theme: ThemeChoice = .dark
    public var fontSize: Double = 17
    public var lineHeight: Double = 1.7
    public var contentWidth: Double = 800
    public var fontFamily: String = "system"
    public var autosave: Bool = true
    public init() {}
}

public struct FileEntry: Identifiable, Sendable, Equatable {
    public let url: URL
    public let isDirectory: Bool
    public var id: String { url.path }
    public var name: String { url.lastPathComponent }
    public init(url: URL, isDirectory: Bool) { self.url = url; self.isDirectory = isDirectory }
}

public enum FolderScanner {
    public static func children(of folder: URL) throws -> [FileEntry] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey], options: [.skipsHiddenFiles])
            .compactMap { url -> FileEntry? in
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
                guard values.isSymbolicLink != true, values.isPackage != true else { return nil }
                let isDirectory = values.isDirectory == true
                guard isDirectory || url.pathExtension.lowercased() == "md" else { return nil }
                return FileEntry(url: url, isDirectory: isDirectory)
            }
            .sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }

    public static func index(_ folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            if Task.isCancelled { break }
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { continue }
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values.isDirectory != true, url.pathExtension.lowercased() == "md" { files.append(url) }
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
