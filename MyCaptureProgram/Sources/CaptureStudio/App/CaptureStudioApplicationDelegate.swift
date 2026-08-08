import AppKit

@MainActor
final class CaptureStudioApplicationDelegate: NSObject, NSApplicationDelegate {
    private weak var captureCoordinator: CaptureCoordinator?
    private var terminationTask: Task<Void, Never>?

    func configure(captureCoordinator: CaptureCoordinator) {
        self.captureCoordinator = captureCoordinator
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let captureCoordinator else {
            return .terminateNow
        }
        guard captureCoordinator.needsTerminationPreparation else {
            return .terminateNow
        }
        guard terminationTask == nil else {
            return .terminateLater
        }

        terminationTask = Task { [weak self, weak sender] in
            guard let self, let sender else {
                return
            }
            let shouldTerminate = await captureCoordinator.prepareForTermination()
            terminationTask = nil
            sender.reply(toApplicationShouldTerminate: shouldTerminate)
        }
        return .terminateLater
    }
}
