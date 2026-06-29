import AppKit
import SwiftUI

struct FilePreviewView: View {
    private static let previewDebounceNanoseconds: UInt64 = 120_000_000

    let entry: FileEntry
    @State private var previewImage: NSImage?
    @State private var previewContent: FilePreviewContent = .visual

    var body: some View {
        Group {
            switch previewContent {
            case .text(let preview):
                textPreview(preview)
            case .visual:
                visualPreview(message: nil)
            case .unsupported(let message):
                visualPreview(message: message)
            }
        }
        .task(id: entry.url) {
            await loadPreview()
        }
    }

    private func visualPreview(message: String?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)

            VStack(spacing: 8) {
                if let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                        .resizable()
                        .scaledToFit()
                        .padding(.horizontal, 32)
                        .padding(.top, 22)
                        .opacity(entry.isHidden ? 0.55 : 1)
                }

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                }
            }
        }
        .frame(height: entry.isDirectoryLike ? 150 : 190)
    }

    private func textPreview(_ preview: FileTextPreview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label("Text Preview", systemImage: "doc.text")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                Text(preview.encodingName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if preview.isTruncated {
                    Text("Truncated")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tertiary, in: Capsule())
                }
            }

            Divider()

            ScrollView {
                Text(preview.text.isEmpty ? "Empty file" : preview.text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(preview.text.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(height: 240)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func loadPreview() async {
        previewImage = nil
        previewContent = .visual

        do {
            try await Task.sleep(nanoseconds: Self.previewDebounceNanoseconds)
        } catch {
            return
        }
        guard !Task.isCancelled else {
            return
        }

        let content = await FilePreviewContentLoader.loadContent(for: entry)
        guard !Task.isCancelled else {
            return
        }
        previewContent = content

        switch content {
        case .text, .unsupported:
            return
        case .visual:
            let preview = await FilePreviewThumbnailLoader.loadPreviewImage(
                for: entry.url,
                scale: NSScreen.main?.backingScaleFactor ?? 2
            )
            guard !Task.isCancelled else {
                return
            }
            previewImage = preview.image
        }
    }
}
