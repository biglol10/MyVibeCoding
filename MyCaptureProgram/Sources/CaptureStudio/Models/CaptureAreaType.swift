import Foundation

public enum CaptureAreaType: String, CaseIterable, Codable, Identifiable {
    case rectangle
    case window
    case fullScreen
    case freeform

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .rectangle:
            return "Rectangle"
        case .window:
            return "Window"
        case .fullScreen:
            return "Full Screen"
        case .freeform:
            return "Freeform"
        }
    }
}
