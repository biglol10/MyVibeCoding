import SwiftUI

struct BreadcrumbView: View {
    @EnvironmentObject private var store: ExplorerStore
    var body: some View {
        if let current = store.activePane.location.fileSystemURL {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(Self.ancestors(current), id: \.self) { url in
                        Button(url.path == "/" ? "Mac" : url.lastPathComponent) {
                            store.requestToolbarFocusClear()
                            Task { await store.navigate(to: url) }
                        }.buttonStyle(.link).help(url.path)
                        if url.standardizedFileURL.path != current.standardizedFileURL.path {
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }.font(.caption).accessibilityLabel("Folder path")
        }
    }
    static func ancestors(_ url: URL) -> [URL] {
        var result = [url.standardizedFileURL]
        while result.last!.path != "/" {
            let parent = result.last!.deletingLastPathComponent()
            guard parent.path != result.last!.path else { break }
            result.append(parent)
        }
        return result.reversed()
    }
}
