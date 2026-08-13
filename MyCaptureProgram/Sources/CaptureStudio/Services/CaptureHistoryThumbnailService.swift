import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct CaptureHistoryThumbnailService: Sendable {
    private let encode: @Sendable (Data) -> Data?

    public init() {
        encode = Self.encodeThumbnail
    }

    init(encode: @escaping @Sendable (Data) -> Data?) {
        self.encode = encode
    }

    public func thumbnailData(from sourceData: Data) async -> Data? {
        let encode = self.encode
        return await Task.detached(priority: .utility) {
            encode(sourceData)
        }.value
    }

    static func encodeThumbnail(from sourceData: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0,
              height > 0
        else {
            return nil
        }

        let scale = min(240 / width, 160 / height, 1)
        let maximumPixelSize = max(1, Int((max(width, height) * scale).rounded(.down)))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return outputData as Data
    }
}
