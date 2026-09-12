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
    public var focusMode: Bool = false
    public var typewriterMode: Bool = false
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case theme, fontSize, lineHeight, contentWidth, fontFamily, autosave, focusMode, typewriterMode
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        theme = try values.decodeIfPresent(ThemeChoice.self, forKey: .theme) ?? .dark
        fontSize = try values.decodeIfPresent(Double.self, forKey: .fontSize) ?? 17
        lineHeight = try values.decodeIfPresent(Double.self, forKey: .lineHeight) ?? 1.7
        contentWidth = try values.decodeIfPresent(Double.self, forKey: .contentWidth) ?? 800
        fontFamily = try values.decodeIfPresent(String.self, forKey: .fontFamily) ?? "system"
        autosave = try values.decodeIfPresent(Bool.self, forKey: .autosave) ?? true
        focusMode = try values.decodeIfPresent(Bool.self, forKey: .focusMode) ?? false
        typewriterMode = try values.decodeIfPresent(Bool.self, forKey: .typewriterMode) ?? false
    }
}

public struct FileEntry: Identifiable, Sendable, Equatable {
    public let url: URL
    public let isDirectory: Bool
    public var id: String { url.path }
    public var name: String { url.lastPathComponent }
    public init(url: URL, isDirectory: Bool) { self.url = url; self.isDirectory = isDirectory }
}

public enum MarkdownFileSupport {
    public static let extensions: Set<String> = ["md", "markdown"]

    public static func isMarkdownFile(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }
}

public enum FolderScanner {
    public static func children(of folder: URL) throws -> [FileEntry] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey], options: [.skipsHiddenFiles])
            .compactMap { url -> FileEntry? in
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
                guard values.isSymbolicLink != true, values.isPackage != true else { return nil }
                let isDirectory = values.isDirectory == true
                guard isDirectory || MarkdownFileSupport.isMarkdownFile(url) else { return nil }
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
            if values.isDirectory != true, MarkdownFileSupport.isMarkdownFile(url) { files.append(url) }
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
