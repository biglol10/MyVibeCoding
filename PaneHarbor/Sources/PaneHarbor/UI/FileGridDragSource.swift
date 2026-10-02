import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One native file URL writer per selected item, as in the list view.
/// SwiftUI's single-provider onDrag cannot express a multi-file drag on macOS 15.
struct FileGridDragSource: NSViewRepresentable {
    let enabled: Bool
    let paneID: PaneID
    let onClick: (NSEvent.ModifierFlags, Int) -> Void
    let dragURLs: () -> [URL]

    func makeNSView(context: Context) -> FileGridDragView { FileGridDragView() }
    func updateNSView(_ view: FileGridDragView, context: Context) {
        view.enabled = enabled
        view.paneID = paneID
        view.onClick = onClick
        view.dragURLs = dragURLs
    }
}

@MainActor
final class FileGridDragView: NSView, NSDraggingSource {
    var enabled = true
    var paneID = PaneID()
    var onClick: ((NSEvent.ModifierFlags, Int) -> Void)?
    var dragURLs: (() -> [URL])?
    private var downEvent: NSEvent?
    private var didDrag = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Let the SwiftUI context menu and the inline name field receive events.
        guard enabled, NSApp.currentEvent?.type != .rightMouseDown,
              NSApp.currentEvent?.type != .rightMouseUp else { return nil }
        return super.hitTest(point)
    }
    override func mouseDown(with event: NSEvent) { downEvent = event; didDrag = false }
    override func mouseUp(with event: NSEvent) {
        defer { downEvent = nil }
        if !didDrag, let downEvent { onClick?(downEvent.modifierFlags, downEvent.clickCount) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard enabled, !didDrag, let downEvent,
              hypot(event.locationInWindow.x - downEvent.locationInWindow.x,
                    event.locationInWindow.y - downEvent.locationInWindow.y) >= 4 else { return }
        let items = makeDraggingItems()
        guard !items.isEmpty else { return }
        didDrag = true
        FileGridDragSession.paneID = paneID
        let session = beginDraggingSession(with: items, event: downEvent, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }
    func makeDraggingItems() -> [NSDraggingItem] {
        guard enabled else { return [] }
        var seen: Set<URL> = []
        return (dragURLs?() ?? []).filter { $0.isFileURL && seen.insert($0.standardizedFileURL).inserted }.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let image = NSWorkspace.shared.icon(forFile: url.path)
            item.setDraggingFrame(NSRect(x: 12 + CGFloat(index % 4) * 3, y: 38, width: 64, height: 64), contents: image)
            return item
        }
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? [.copy, .move] : .copy
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        FileGridDragSession.paneID = nil
        downEvent = nil
    }
}

@MainActor
private enum FileGridDragSession { static var paneID: PaneID? }

struct FileGridDropDelegate: DropDelegate {
    let store: ExplorerStore
    let paneID: PaneID
    let destination: URL
    let disabled: Bool

    @MainActor var isAvailable: Bool {
        !disabled && !store.isFileMutationInProgress &&
            store.pane(withID: paneID).map { !$0.location.isArchive } == true
    }

    @MainActor private var operation: DropOperation? {
        guard isAvailable else { return nil }
        return FileDropOperationResolver.operation(
            source: FileGridDragSession.paneID == paneID ? .local : .external,
            optionKeyPressed: NSEvent.modifierFlags.contains(.option), proposedOperation: nil)
    }
    func validateDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated { isAvailable }
            && info.hasItemsConforming(to: [UTType.fileURL])
    }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        MainActor.assumeIsolated {
            guard let operation else { return nil }
            return DropProposal(operation: operation == .copy ? .copy : .move)
        }
    }
    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info) else { return false }
        let providers = info.itemProviders(for: [UTType.fileURL])
        guard !providers.isEmpty else { return false }
        guard let operation = MainActor.assumeIsolated({ self.operation }) else { return false }
        Task { @MainActor in
            guard let urls = await Self.loadFileURLs(from: providers) else { return }
            // Loading item providers may finish after this pane was closed or
            // replaced by a different tab. Do not send the drop to that tab.
            guard isAvailable, store.activatePane(withID: paneID) else { return }
            await store.performDrop(urls: urls, destinationFolder: destination, operation: operation)
        }
        return true
    }

    static func loadFileURLs(from providers: [NSItemProvider]) async -> [URL]? {
        // Keep the native URL object supplied by the drag, including its
        // security scope. Converting it to text loses that information.
        var urls: [URL] = []
        for provider in providers {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                    continuation.resume(returning: object as? URL)
                }
            }
            guard let url, url.isFileURL else { return nil }
            urls.append(url)
        }
        return urls.isEmpty ? nil : urls
    }
}
