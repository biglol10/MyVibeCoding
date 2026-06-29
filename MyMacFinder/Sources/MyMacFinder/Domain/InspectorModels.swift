import Foundation

public struct InspectorItemDetails: Equatable, Sendable {
    public var name: String
    public var kind: String
    public var fileExtension: String
    public var sizeText: String
    public var dateCreatedText: String
    public var dateModifiedText: String
    public var dateAccessedText: String
    public var path: String
    public var isHiddenText: String
    public var isReadableText: String
    public var finderTagsText: String
    public var isDirectoryLike: Bool

    public init(entry: FileEntry, calculatedFolderSize: Int64? = nil) {
        self.name = entry.name
        self.kind = entry.typeDescription
        self.fileExtension = entry.fileExtension.isEmpty ? "--" : entry.fileExtension
        self.sizeText = Self.sizeText(calculatedFolderSize ?? entry.size)
        self.dateCreatedText = Self.dateText(entry.dateCreated)
        self.dateModifiedText = Self.dateText(entry.dateModified)
        self.dateAccessedText = Self.dateText(entry.dateAccessed)
        self.path = entry.url.path
        self.isHiddenText = entry.isHidden ? "Yes" : "No"
        self.isReadableText = entry.isReadable ? "Yes" : "No"
        self.finderTagsText = entry.finderTags.isEmpty ? "--" : entry.finderTags.map(\.name).joined(separator: ", ")
        self.isDirectoryLike = entry.isDirectoryLike
    }

    public static func sizeText(_ size: Int64?) -> String {
        guard let size else {
            return "--"
        }
        guard size >= 1_000 else {
            return size == 1 ? "1 byte" : "\(size) bytes"
        }

        let units = ["KB", "MB", "GB", "TB", "PB"]
        var value = Double(size)
        var unitIndex = -1
        repeat {
            value /= 1_000
            unitIndex += 1
        } while value >= 1_000 && unitIndex < units.count - 1

        let formatted = value >= 10
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
        return "\(formatted) \(units[unitIndex])"
    }

    public static func dateText(_ date: Date?) -> String {
        guard let date else {
            return "--"
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

public struct InspectorSelectionSummary: Equatable, Sendable {
    public var itemCount: Int
    public var fileCount: Int
    public var folderCount: Int
    public var knownTotalSizeText: String
    public var commonParentPath: String?
    public var previewNames: [String]

    public init(entries: [FileEntry]) {
        self.itemCount = entries.count
        self.fileCount = entries.filter { !$0.isDirectoryLike }.count
        self.folderCount = entries.filter(\.isDirectoryLike).count

        let knownSize = entries
            .filter { !$0.isDirectoryLike }
            .compactMap(\.size)
            .reduce(Int64(0), +)
        self.knownTotalSizeText = InspectorItemDetails.sizeText(knownSize)

        let parents = Set(entries.map { $0.url.deletingLastPathComponent().standardizedFileURL.path })
        self.commonParentPath = parents.count == 1 ? parents.first : nil

        self.previewNames = Array(entries.map(\.name).prefix(8))
    }
}
