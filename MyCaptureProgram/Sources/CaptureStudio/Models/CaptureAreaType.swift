import Foundation

public enum CaptureAreaType: String, CaseIterable, Codable, Identifiable, Sendable {
    case rectangle
    case window
    case fullScreen

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .rectangle:
            return "Rectangle"
        case .window:
            return "Window"
        case .fullScreen:
            return "Full Screen"
        }
    }
}
