import Foundation

@MainActor
public final class CaptureHistoryStore: ObservableObject {
    @Published public private(set) var items: [CaptureHistoryItem]

    private let defaults: UserDefaults
    private let storageKey = "CaptureStudio.CaptureHistory.v1"
    private let maxItems: Int

    public init(defaults: UserDefaults = .standard, maxItems: Int = 100) {
        self.defaults = defaults
        self.maxItems = max(1, maxItems)
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([CaptureHistoryItem].self, from: data) {
            items = decoded.sorted { $0.createdAt > $1.createdAt }
        } else {
            items = []
        }
    }

    public func add(_ item: CaptureHistoryItem) {
        items.removeAll { existing in
            existing.id == item.id || existing.fileURL.standardizedFileURL == item.fileURL.standardizedFileURL
        }
        items.insert(item, at: 0)
        items.sort { $0.createdAt > $1.createdAt }
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        persist()
    }

    public func remove(id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    public func remove(fileURL: URL) {
        items.removeAll { $0.fileURL.standardizedFileURL == fileURL.standardizedFileURL }
        persist()
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
        defaults.set(data, forKey: storageKey)
    }
}
