import AppKit
import QuickLookThumbnailing

struct FilePreviewThumbnailRequest: Hashable, Sendable {
    let id: UUID
    let url: URL
    let size: CGSize
    let scale: CGFloat
}

protocol FilePreviewThumbnailGenerating: Sendable {
    func generate(
        _ request: FilePreviewThumbnailRequest,
        completion: @escaping @Sendable (NSImage?) -> Void
    )
    func cancel(_ request: FilePreviewThumbnailRequest)
}

enum FilePreviewThumbnailLoader {
    static func loadPreviewImage(
        for url: URL,
        scale: CGFloat,
        generator: any FilePreviewThumbnailGenerating = QuickLookThumbnailGenerator.shared
    ) async -> FilePreviewThumbnail {
        let request = FilePreviewThumbnailRequest(
            id: UUID(),
            url: url,
            size: CGSize(width: 360, height: 240),
            scale: scale
        )
        let state = FilePreviewThumbnailContinuationState()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard state.install(continuation) else {
                    return
                }

                generator.generate(request) { image in
                    state.complete(with: image)
                }
                if state.requestDidStart() {
                    generator.cancel(request)
                }
            }
        } onCancel: {
            if state.cancel() {
                generator.cancel(request)
            }
        }
    }
}

struct FilePreviewThumbnail: @unchecked Sendable {
    var image: NSImage?

    init(image: NSImage?) {
        self.image = image
    }
}

private final class QuickLookThumbnailGenerator: FilePreviewThumbnailGenerating, @unchecked Sendable {
    static let shared = QuickLookThumbnailGenerator(generator: .shared)

    private let generator: QLThumbnailGenerator
    private let lock = NSLock()
    private var requests: [UUID: QLThumbnailGenerator.Request] = [:]

    init(generator: QLThumbnailGenerator) {
        self.generator = generator
    }

    func generate(
        _ request: FilePreviewThumbnailRequest,
        completion: @escaping @Sendable (NSImage?) -> Void
    ) {
        let quickLookRequest = QLThumbnailGenerator.Request(
            fileAt: request.url,
            size: request.size,
            scale: request.scale,
            representationTypes: [.thumbnail, .icon]
        )
        lock.withLock {
            requests[request.id] = quickLookRequest
        }

        generator.generateBestRepresentation(for: quickLookRequest) { [weak self] thumbnail, _ in
            let shouldComplete = self?.lock.withLock {
                self?.requests.removeValue(forKey: request.id) != nil
            } ?? false
            guard shouldComplete else {
                return
            }
            completion(thumbnail?.nsImage)
        }
    }

    func cancel(_ request: FilePreviewThumbnailRequest) {
        let quickLookRequest = lock.withLock {
            requests.removeValue(forKey: request.id)
        }
        if let quickLookRequest {
            generator.cancel(quickLookRequest)
        }
    }
}

private final class FilePreviewThumbnailContinuationState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<FilePreviewThumbnail, Never>?
    private var isCancelled = false
    private var isFinished = false
    private var didStartRequest = false
    private var didCancelRequest = false

    func install(_ continuation: CheckedContinuation<FilePreviewThumbnail, Never>) -> Bool {
        let shouldStart = lock.withLock {
            guard !isCancelled else {
                return false
            }
            self.continuation = continuation
            return true
        }
        if !shouldStart {
            continuation.resume(returning: FilePreviewThumbnail(image: nil))
        }
        return shouldStart
    }

    func requestDidStart() -> Bool {
        lock.withLock {
            guard !isFinished else {
                return false
            }
            didStartRequest = true
            guard isCancelled, !didCancelRequest else {
                return false
            }
            didCancelRequest = true
            return true
        }
    }

    func cancel() -> Bool {
        let result = lock.withLock { () -> (CheckedContinuation<FilePreviewThumbnail, Never>?, Bool) in
            guard !isFinished, !isCancelled else {
                return (nil, false)
            }
            isCancelled = true
            let continuation = self.continuation
            self.continuation = nil
            let shouldCancelRequest = didStartRequest && !didCancelRequest
            didCancelRequest = shouldCancelRequest
            return (continuation, shouldCancelRequest)
        }
        result.0?.resume(returning: FilePreviewThumbnail(image: nil))
        return result.1
    }

    func complete(with image: NSImage?) {
        let continuation = lock.withLock { () -> CheckedContinuation<FilePreviewThumbnail, Never>? in
            guard !isFinished, !isCancelled else {
                return nil
            }
            isFinished = true
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(returning: FilePreviewThumbnail(image: image))
    }
}
