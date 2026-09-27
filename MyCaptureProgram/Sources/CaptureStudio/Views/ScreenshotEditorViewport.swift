import AppKit
import SwiftUI

struct ScreenshotEditorViewport: View {
    let document: EditorDocument
    @ObservedObject var editorViewModel: EditorViewModel
    let onCopy: () -> Void
    @State private var zoom: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let imageSize = document.currentImageData.flatMap(NSImage.init(data:))?.size ?? proxy.size
            let viewport = CGSize(width: proxy.size.width, height: max(1, proxy.size.height - 40))
            let fit = min(viewport.width / max(1, imageSize.width), viewport.height / max(1, imageSize.height))
            VStack(spacing: 0) {
                ScrollView([.horizontal, .vertical]) {
                    EditorCanvasView(document: document, editorViewModel: editorViewModel, onCopy: onCopy)
                        .frame(width: zoom.map { imageSize.width * $0 } ?? viewport.width,
                               height: zoom.map { imageSize.height * $0 } ?? viewport.height)
                        .frame(minWidth: viewport.width, minHeight: viewport.height)
                }.frame(height: viewport.height)
                HStack(spacing: 12) {
                    Button { zoom = max(0.1, (zoom ?? fit) / 1.5) } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }.accessibilityLabel("Zoom out")
                    Text("\(Int((zoom ?? fit) * 100))%")
                        .monospacedDigit().frame(minWidth: 44)
                    Button { zoom = min(8, (zoom ?? fit) * 1.5) } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }.accessibilityLabel("Zoom in")
                    Button("100%") { zoom = 1 }
                    Button("Fit") { zoom = nil }
                    Spacer()
                    if zoom != nil { Text("Scroll to move around").foregroundStyle(.secondary) }
                }
                .font(.caption).padding(.horizontal, 8).frame(height: 40).background(.bar)
            }
        }
        .onChange(of: document.id) { zoom = nil }
    }
}
