import AppKit
import UniformTypeIdentifiers

enum FileEntryIconResolver {
    typealias ContentTypeIconProvider = @MainActor (UTType) -> NSImage

    @MainActor
    static func icon(for entry: FileEntry, size: NSSize) -> NSImage {
        icon(
            for: entry,
            size: size,
            contentTypeIconProvider: { NSWorkspace.shared.icon(for: $0) }
        )
    }

    @MainActor
    static func icon(
        for entry: FileEntry,
        size: NSSize,
        contentTypeIconProvider: ContentTypeIconProvider
    ) -> NSImage {
        let sourceIcon = contentTypeIconProvider(contentType(for: entry))
        let icon = sourceIcon.copy() as? NSImage ?? sourceIcon
        icon.size = size
        return icon
    }

    private static func contentType(for entry: FileEntry) -> UTType {
        switch entry.kind {
        case .folder, .volume, .zipVirtualFolder:
            return .folder
        case .package:
            return .applicationBundle
        case .symlink:
            return .symbolicLink
        case .file, .zipVirtualFile, .other:
            guard !entry.fileExtension.isEmpty else {
                return .data
            }
            return UTType(filenameExtension: entry.fileExtension) ?? .data
        }
    }
}
