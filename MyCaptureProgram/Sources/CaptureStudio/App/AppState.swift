import Foundation
import SwiftUI

@MainActor
public final class AppState: ObservableObject {
    @Published public var captureMode: CaptureMode
    @Published public var areaType: CaptureAreaType
    @Published public var currentDocument: EditorDocument?
    @Published public var statusMessage: String?

    public init(
        captureMode: CaptureMode = .screenshot,
        areaType: CaptureAreaType = .rectangle,
        currentDocument: EditorDocument? = nil,
        statusMessage: String? = nil
    ) {
        self.captureMode = captureMode
        self.areaType = areaType
        self.currentDocument = currentDocument
        self.statusMessage = statusMessage
    }
}
