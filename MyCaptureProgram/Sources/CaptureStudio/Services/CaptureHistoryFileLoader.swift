import Foundation

public struct CaptureHistoryFileLoader: Sendable {
    private let loadFile: @Sendable (URL) async throws -> Data

    public init() {
        loadFile = { fileURL in
            try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: fileURL, options: .mappedIfSafe)
            }.value
        }
    }

    init(loadFile: @escaping @Sendable (URL) async throws -> Data) {
        self.loadFile = loadFile
    }

    public func load(_ fileURL: URL) async throws -> Data {
        try await loadFile(fileURL)
    }
}
