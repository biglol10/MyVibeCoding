import Foundation

public struct AdvancedSearchOptions: Codable, Equatable, Sendable {
    public var content: String = ""
    public var minimumBytes: Int64? = nil
    public var maximumBytes: Int64? = nil
    public var modifiedFrom: Date? = nil
    public var modifiedBefore: Date? = nil
    public init() {}
    public var isActive: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || minimumBytes != nil || maximumBytes != nil || modifiedFrom != nil || modifiedBefore != nil
    }
    public func matchesMetadata(_ entry: FileEntry) -> Bool {
        if let minimumBytes, (entry.size ?? -1) < minimumBytes { return false }
        if let maximumBytes, entry.size == nil || entry.size! > maximumBytes { return false }
        if let modifiedFrom, entry.dateModified == nil || entry.dateModified! < modifiedFrom { return false }
        if let modifiedBefore, entry.dateModified == nil || entry.dateModified! >= modifiedBefore { return false }
        return true
    }
}
