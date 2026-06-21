import Foundation

public enum EditorTool: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case select
    case pen
    case highlighter
    case arrow
    case rectangle
    case ellipse
    case text
    case redaction
    case ocr

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .select:
            return "Select"
        case .pen:
            return "Pen"
        case .highlighter:
            return "Highlighter"
        case .arrow:
            return "Arrow"
        case .rectangle:
            return "Rectangle"
        case .ellipse:
            return "Ellipse"
        case .text:
            return "Text"
        case .redaction:
            return "Redact"
        case .ocr:
            return "OCR"
        }
    }

    public var systemImage: String {
        switch self {
        case .select:
            return "cursorarrow"
        case .pen:
            return "pencil.tip"
        case .highlighter:
            return "highlighter"
        case .arrow:
            return "arrow.up.right"
        case .rectangle:
            return "rectangle"
        case .ellipse:
            return "circle"
        case .text:
            return "textformat"
        case .redaction:
            return "eye.slash"
        case .ocr:
            return "text.viewfinder"
        }
    }
}
