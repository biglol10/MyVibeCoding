import Foundation
import SwiftUI

public struct PermissionPrompt: Identifiable, Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case screenRecording
    }

    public let kind: Kind
    public let title: String
    public let message: String
    public let actionTitle: String
    public let systemSettingsURLString: String

    public var id: Kind { kind }

    public static let screenRecording = PermissionPrompt(
        kind: .screenRecording,
        title: "Screen Recording Permission Required",
        message: "CaptureStudio needs Screen Recording permission before Capture or Record can start. Enable CaptureStudio in System Settings, then restart the app if macOS still blocks access.",
        actionTitle: "Open System Settings",
        systemSettingsURLString: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )
}

@MainActor
public final class AppState: ObservableObject {
    @Published public var captureMode: CaptureMode
    @Published public var areaType: CaptureAreaType
    @Published public var currentDocument: EditorDocument?
    @Published public var statusMessage: String?
    @Published public var permissionPrompt: PermissionPrompt?
    @Published public var isGuidePresented: Bool
    @Published public var isCaptureOperationInProgress: Bool
    @Published public var isFileOperationInProgress: Bool
    @Published public var isRecordingInProgress: Bool
    @Published public var isHistoryPresented: Bool
    @Published public var historySearchText: String

    public init(
        captureMode: CaptureMode = .screenshot,
        areaType: CaptureAreaType = .rectangle,
        currentDocument: EditorDocument? = nil,
        statusMessage: String? = nil,
        permissionPrompt: PermissionPrompt? = nil,
        isGuidePresented: Bool = false,
        isCaptureOperationInProgress: Bool = false,
        isFileOperationInProgress: Bool = false,
        isRecordingInProgress: Bool = false,
        isHistoryPresented: Bool = false,
        historySearchText: String = ""
    ) {
        self.captureMode = captureMode
        self.areaType = areaType
        self.currentDocument = currentDocument
        self.statusMessage = statusMessage
        self.permissionPrompt = permissionPrompt
        self.isGuidePresented = isGuidePresented
        self.isCaptureOperationInProgress = isCaptureOperationInProgress
        self.isFileOperationInProgress = isFileOperationInProgress
        self.isRecordingInProgress = isRecordingInProgress
        self.isHistoryPresented = isHistoryPresented
        self.historySearchText = historySearchText
    }

    public var isInteractionBlocked: Bool {
        isCaptureOperationInProgress || isFileOperationInProgress
    }
}
