import Foundation
import ImageIO

@MainActor
public final class CaptureHistoryStore: ObservableObject {
    @Published public private(set) var items: [CaptureHistoryItem]

    private let defaults: UserDefaults
    private static let storageKey = "CaptureStudio.CaptureHistory.v1"
    private let maxItems: Int
    private let thumbnailDirectory: URL
    private let fileManager: FileManager

    public init(
        defaults: UserDefaults = .standard,
        maxItems: Int = 100,
        thumbnailDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.maxItems = max(1, maxItems)
        self.fileManager = fileManager
        self.thumbnailDirectory = thumbnailDirectory ?? Self.defaultThumbnailDirectory(fileManager: fileManager)
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([CaptureHistoryItem].self, from: data) {
            items = decoded.sorted { $0.createdAt > $1.createdAt }
        } else {
            items = []
        }
    }

    public func add(_ item: CaptureHistoryItem) {
        add(item, thumbnailIsPrepared: false)
    }

    public func addPrepared(_ item: CaptureHistoryItem) {
        add(item, thumbnailIsPrepared: true)
    }

    private func add(_ item: CaptureHistoryItem, thumbnailIsPrepared: Bool) {
        let removedItems = items.filter { existing in
            existing.id == item.id || existing.fileURL.standardizedFileURL == item.fileURL.standardizedFileURL
        }
        removedItems.forEach { _ = deleteThumbnailIfNeeded($0) }
        items.removeAll { removedItems.contains($0) }
        items.insert(storedItem(from: item, thumbnailIsPrepared: thumbnailIsPrepared), at: 0)
        items.sort { $0.createdAt > $1.createdAt }
        if items.count > maxItems {
            let droppedItems = Array(items.dropFirst(maxItems))
            droppedItems.forEach { _ = deleteThumbnailIfNeeded($0) }
            items = Array(items.prefix(maxItems))
        }
        persist()
    }

    @discardableResult
    public func remove(id: UUID) -> Bool {
        let removedItems = items.filter { $0.id == id }
        let cleanupSucceeded = removedItems.reduce(true) { result, item in
            deleteThumbnailIfNeeded(item) && result
        }
        items.removeAll { $0.id == id }
        persist()
        return cleanupSucceeded
    }

    @discardableResult
    public func remove(fileURL: URL) -> Bool {
        let removedItems = items.filter { $0.fileURL.standardizedFileURL == fileURL.standardizedFileURL }
        let cleanupSucceeded = removedItems.reduce(true) { result, item in
            deleteThumbnailIfNeeded(item) && result
        }
        items.removeAll { $0.fileURL.standardizedFileURL == fileURL.standardizedFileURL }
        persist()
        return cleanupSucceeded
    }

    @discardableResult
    public func clear() -> Bool {
        let cleanupSucceeded = items.reduce(true) { result, item in
            deleteThumbnailIfNeeded(item) && result
        }
        items.removeAll()
        persist()
        return cleanupSucceeded
    }

    public func items(matching query: String) -> [CaptureHistoryItem] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return items
        }
        return items.filter { $0.searchableText.contains(normalized) }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func storedItem(from item: CaptureHistoryItem, thumbnailIsPrepared: Bool) -> CaptureHistoryItem {
        var storedItem = item
        storedItem.thumbnailURL = nil
        if item.kind == .screenshot,
           let sourceData = item.thumbnailData,
           let thumbnailData = thumbnailIsPrepared
            ? sourceData
            : CaptureHistoryThumbnailService.encodeThumbnail(from: sourceData),
           CGImageSourceCreateWithData(thumbnailData as CFData, nil) != nil {
            let thumbnailURL = thumbnailDirectory
                .appendingPathComponent(item.id.uuidString)
                .appendingPathExtension("png")
            do {
                try fileManager.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
                try thumbnailData.write(to: thumbnailURL, options: .atomic)
                storedItem.thumbnailURL = thumbnailURL
            } catch {
                storedItem.thumbnailURL = nil
            }
        }
        storedItem.thumbnailData = nil
        return storedItem
    }

    private func deleteThumbnailIfNeeded(_ item: CaptureHistoryItem) -> Bool {
        guard let thumbnailURL = item.thumbnailURL else {
            return true
        }
        let ownedThumbnailURL = thumbnailDirectory
            .appendingPathComponent(item.id.uuidString)
            .appendingPathExtension("png")
            .standardizedFileURL
        guard thumbnailURL.standardizedFileURL == ownedThumbnailURL else {
            return false
        }
        guard fileManager.fileExists(atPath: thumbnailURL.path) else {
            return true
        }
        do {
            try fileManager.removeItem(at: thumbnailURL)
            return true
        } catch {
            return false
        }
    }

    private static func defaultThumbnailDirectory(fileManager: FileManager) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseURL
            .appendingPathComponent("CaptureStudio", isDirectory: true)
            .appendingPathComponent("HistoryThumbnails", isDirectory: true)
    }
}
