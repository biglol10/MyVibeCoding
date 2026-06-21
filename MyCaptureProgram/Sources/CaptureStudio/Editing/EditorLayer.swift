import CoreGraphics
import Foundation

public struct LayerColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let clear = LayerColor(red: 0, green: 0, blue: 0, alpha: 0)
    public static let black = LayerColor(red: 0, green: 0, blue: 0)
    public static let red = LayerColor(red: 1, green: 0, blue: 0)
    public static let blue = LayerColor(red: 0, green: 0.36, blue: 1)
    public static let yellow = LayerColor(red: 1, green: 0.86, blue: 0)
}

public struct LayerStyle: Codable, Equatable, Sendable {
    public var strokeColor: LayerColor
    public var fillColor: LayerColor
    public var lineWidth: CGFloat

    public init(strokeColor: LayerColor, fillColor: LayerColor, lineWidth: CGFloat) {
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.lineWidth = lineWidth
    }
}

public struct ShapeLayer: Codable, Equatable, Sendable {
    public var id: UUID
    public var frame: CGRect
    public var style: LayerStyle

    public init(id: UUID = UUID(), frame: CGRect, style: LayerStyle) {
        self.id = id
        self.frame = frame.standardized
        self.style = style
    }
}

public struct ArrowLayer: Codable, Equatable, Sendable {
    public var id: UUID
    public var start: CGPoint
    public var end: CGPoint
    public var style: LayerStyle

    public init(id: UUID = UUID(), start: CGPoint, end: CGPoint, style: LayerStyle) {
        self.id = id
        self.start = start
        self.end = end
        self.style = style
    }
}

public struct FreehandLayer: Codable, Equatable, Sendable {
    public var id: UUID
    public var points: [CGPoint]
    public var style: LayerStyle

    public init(id: UUID = UUID(), points: [CGPoint], style: LayerStyle) {
        self.id = id
        self.points = points
        self.style = style
    }
}

public struct TextLayer: Codable, Equatable, Sendable {
    public var id: UUID
    public var frame: CGRect
    public var text: String
    public var fontSize: CGFloat
    public var style: LayerStyle

    public init(id: UUID = UUID(), frame: CGRect, text: String, fontSize: CGFloat, style: LayerStyle) {
        self.id = id
        self.frame = frame.standardized
        self.text = text
        self.fontSize = fontSize
        self.style = style
    }
}

public struct RedactionLayer: Codable, Equatable, Sendable {
    public enum Mode: Codable, Equatable, Sendable {
        case solid
        case blur(radius: CGFloat)
    }

    public var id: UUID
    public var frame: CGRect
    public var mode: Mode
    public var style: LayerStyle

    public init(id: UUID = UUID(), frame: CGRect, mode: Mode = .solid, style: LayerStyle) {
        self.id = id
        self.frame = frame.standardized
        self.mode = mode
        self.style = style
    }
}

public enum EditorLayer: Codable, Equatable, Identifiable, Sendable {
    case freehand(FreehandLayer)
    case highlighter(FreehandLayer)
    case arrow(ArrowLayer)
    case rectangle(ShapeLayer)
    case ellipse(ShapeLayer)
    case text(TextLayer)
    case redaction(RedactionLayer)

    public var id: UUID {
        switch self {
        case .freehand(let layer), .highlighter(let layer):
            return layer.id
        case .arrow(let layer):
            return layer.id
        case .rectangle(let layer), .ellipse(let layer):
            return layer.id
        case .text(let layer):
            return layer.id
        case .redaction(let layer):
            return layer.id
        }
    }

    public var frame: CGRect {
        get {
            switch self {
            case .freehand(let layer), .highlighter(let layer):
                return layer.points.boundingRect
            case .arrow(let layer):
                return CGRect(
                    x: min(layer.start.x, layer.end.x),
                    y: min(layer.start.y, layer.end.y),
                    width: abs(layer.end.x - layer.start.x),
                    height: abs(layer.end.y - layer.start.y)
                ).standardized
            case .rectangle(let layer), .ellipse(let layer):
                return layer.frame
            case .text(let layer):
                return layer.frame
            case .redaction(let layer):
                return layer.frame
            }
        }
        set {
            resize(to: newValue)
        }
    }

    public var textContent: String? {
        if case .text(let layer) = self {
            return layer.text
        }

        return nil
    }

    public mutating func moveBy(dx: CGFloat, dy: CGFloat) {
        switch self {
        case .freehand(var layer):
            layer.points = layer.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            self = .freehand(layer)
        case .highlighter(var layer):
            layer.points = layer.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            self = .highlighter(layer)
        case .arrow(var layer):
            layer.start = CGPoint(x: layer.start.x + dx, y: layer.start.y + dy)
            layer.end = CGPoint(x: layer.end.x + dx, y: layer.end.y + dy)
            self = .arrow(layer)
        case .rectangle(var layer):
            layer.frame = layer.frame.offsetBy(dx: dx, dy: dy)
            self = .rectangle(layer)
        case .ellipse(var layer):
            layer.frame = layer.frame.offsetBy(dx: dx, dy: dy)
            self = .ellipse(layer)
        case .text(var layer):
            layer.frame = layer.frame.offsetBy(dx: dx, dy: dy)
            self = .text(layer)
        case .redaction(var layer):
            layer.frame = layer.frame.offsetBy(dx: dx, dy: dy)
            self = .redaction(layer)
        }
    }

    public mutating func resize(to frame: CGRect) {
        switch self {
        case .rectangle(var layer):
            layer.frame = frame.standardized
            self = .rectangle(layer)
        case .ellipse(var layer):
            layer.frame = frame.standardized
            self = .ellipse(layer)
        case .text(var layer):
            layer.frame = frame.standardized
            self = .text(layer)
        case .redaction(var layer):
            layer.frame = frame.standardized
            self = .redaction(layer)
        case .freehand, .highlighter, .arrow:
            return
        }
    }
}

private extension Array where Element == CGPoint {
    var boundingRect: CGRect {
        guard let first else {
            return .zero
        }

        let minX = map(\.x).min() ?? first.x
        let maxX = map(\.x).max() ?? first.x
        let minY = map(\.y).min() ?? first.y
        let maxY = map(\.y).max() ?? first.y
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).standardized
    }
}
