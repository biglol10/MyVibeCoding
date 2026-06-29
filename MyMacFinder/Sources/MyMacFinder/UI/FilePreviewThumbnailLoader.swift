import AppKit
import QuickLookThumbnailing

enum FilePreviewThumbnailLoader {
    static func loadPreviewImage(for url: URL, scale: CGFloat) async -> FilePreviewThumbnail {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 360, height: 240),
            scale: scale,
            representationTypes: [.thumbnail, .icon]
        )

        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
                continuation.resume(returning: FilePreviewThumbnail(image: thumbnail?.nsImage))
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
