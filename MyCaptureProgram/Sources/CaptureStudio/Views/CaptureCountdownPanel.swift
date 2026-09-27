import AppKit
import SwiftUI

struct CaptureCountdownPanel: NSViewRepresentable {
    let secondsRemaining: Int?
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSView { NSView() }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(seconds: secondsRemaining, onCancel: onCancel)
    }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.dismiss() }

    @MainActor final class Coordinator: NSObject {
        private var panel: NSPanel?
        private let countdownLabel = NSTextField(labelWithString: "")
        private var onCancel: () -> Void = {}

        func update(seconds: Int?, onCancel: @escaping () -> Void) {
            guard let seconds else { dismiss(); return }
            self.onCancel = onCancel
            if panel == nil {
                let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 290, height: 86),
                                    styleMask: [.nonactivatingPanel, .titled], backing: .buffered, defer: false)
                panel.title = "Capture countdown"
                panel.level = .floating
                panel.isReleasedWhenClosed = false
                panel.hidesOnDeactivate = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                countdownLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
                let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
                cancelButton.bezelStyle = .rounded
                cancelButton.keyEquivalent = "\u{1b}"
                cancelButton.keyEquivalentModifierMask = []
                let stack = NSStackView(views: [countdownLabel, cancelButton])
                stack.orientation = .horizontal
                stack.alignment = .centerY
                stack.spacing = 16
                stack.translatesAutoresizingMaskIntoConstraints = false
                if let content = panel.contentView {
                    content.addSubview(stack)
                    NSLayoutConstraint.activate([
                        stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                        stack.centerYAnchor.constraint(equalTo: content.centerYAnchor)
                    ])
                }
                panel.center()
                self.panel = panel
            }
            countdownLabel.stringValue = "Starting in \(seconds)s…"
            panel?.orderFrontRegardless()
        }
        @objc private func cancel(_ sender: Any?) { onCancel() }
        func dismiss() { panel?.close(); panel = nil }
    }
}
