import AppKit
import Foundation

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
        let removedItems = items.filter { existing in
            existing.id == item.id || existing.fileURL.standardizedFileURL == item.fileURL.standardizedFileURL
        }
        removedItems.forEach { _ = deleteThumbnailIfNeeded($0) }
        items.removeAll { removedItems.contains($0) }
        items.insert(storedItem(from: item), at: 0)
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

    private func storedItem(from item: CaptureHistoryItem) -> CaptureHistoryItem {
        var storedItem = item
        storedItem.thumbnailURL = nil
        if item.kind == .screenshot,
           let sourceData = item.thumbnailData,
           let thumbnailData = Self.thumbnailData(from: sourceData) {
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

    static func thumbnailData(from sourceData: Data) -> Data? {
        guard let image = NSImage(data: sourceData), image.size.width > 0, image.size.height > 0 else {
            return nil
        }

        let maxSize = NSSize(width: 240, height: 160)
        let scale = min(maxSize.width / image.size.width, maxSize.height / image.size.height, 1)
        let targetSize = NSSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale)
        )
        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )
        thumbnail.unlockFocus()

        guard let tiffData = thumbnail.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        return representation.representation(using: .png, properties: [:])
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
