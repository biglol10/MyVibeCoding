import Foundation

public enum CaptureMode: String, CaseIterable, Codable, Identifiable {
    case screenshot
    case record

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .screenshot:
            return "Screenshot"
        case .record:
            return "Record"
        }
    }
}
