# Image Editor, OCR, and Redact Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add screenshot annotation editing, flattened Save/Copy, OCR text extraction, and quick redaction to Capture Studio.

**Architecture:** Screenshot editing state lives in `EditorDocument` as image-coordinate layers. Rendering is isolated in an `ImageRenderServicing` implementation that flattens base PNG data plus layers into PNG data. OCR and redaction are separate services so the UI and `CaptureCoordinator` can be tested with deterministic fakes.

**Tech Stack:** Swift 6, SwiftUI, AppKit/CoreGraphics, CoreImage, Vision, XCTest, existing SwiftPM executable target.

---

## Scope And Delivery

This plan implements the approved screenshot-only editor scope from `docs/superpowers/specs/2026-06-20-image-editor-ocr-redact-design.md`.

Included:

- Screenshot layer models.
- Undo/redo snapshots.
- Flattened PNG renderer.
- Save/Copy integration for edited screenshots.
- Screenshot editor toolbar and canvas entry point.
- OCR service and OCR result model.
- OCR result panel with copy text action.
- Redaction detection and Quick Redact.
- Unit and integration coverage.

Out of scope:

- Recording trim.
- GIF export.
- Scrolling capture.
- AI calls.
- Multi-document history.

## File Structure

Create:

- `Sources/CaptureStudio/Editing/EditorTool.swift`: active screenshot editing tool enum.
- `Sources/CaptureStudio/Editing/EditorLayer.swift`: annotation layer models and layer mutations.
- `Sources/CaptureStudio/Editing/EditorHistory.swift`: undo/redo snapshot models and reducer.
- `Sources/CaptureStudio/Editing/EditorCanvasGeometry.swift`: image/view coordinate conversion.
- `Sources/CaptureStudio/Editing/EditorViewModel.swift`: screenshot editor state mutations.
- `Sources/CaptureStudio/Editing/ImageRenderService.swift`: AppKit/CoreGraphics flattening service.
- `Sources/CaptureStudio/OCR/OCRModels.swift`: OCR result and observation models.
- `Sources/CaptureStudio/OCR/OCRService.swift`: Vision-backed OCR service.
- `Sources/CaptureStudio/Redaction/RedactionDetector.swift`: sensitive text detection.
- `Sources/CaptureStudio/Views/EditorCanvasView.swift`: screenshot image canvas.
- `Sources/CaptureStudio/Views/OCRResultPanelView.swift`: recognized text panel.
- `Sources/CaptureStudio/Views/ToolInspectorView.swift`: color/width/text/blur settings.
- `Tests/CaptureStudioTests/EditorLayerTests.swift`
- `Tests/CaptureStudioTests/EditorHistoryTests.swift`
- `Tests/CaptureStudioTests/EditorCanvasGeometryTests.swift`
- `Tests/CaptureStudioTests/ImageRenderServiceTests.swift`
- `Tests/CaptureStudioTests/CaptureCoordinatorEditingTests.swift`
- `Tests/CaptureStudioTests/EditorViewModelTests.swift`
- `Tests/CaptureStudioTests/OCRResultTests.swift`
- `Tests/CaptureStudioTests/OCRServiceTests.swift`
- `Tests/CaptureStudioTests/CaptureCoordinatorOCRTests.swift`
- `Tests/CaptureStudioTests/RedactionDetectorTests.swift`
- `Tests/CaptureStudioTests/QuickRedactIntegrationTests.swift`

Modify:

- `Sources/CaptureStudio/Models/EditorDocument.swift`: add screenshot editing state.
- `Sources/CaptureStudio/Capture/CaptureCoordinator.swift`: inject renderer/OCR/redaction services and route Save/Copy/OCR/Quick Redact.
- `Sources/CaptureStudio/Capture/PostCaptureServices.swift`: add text clipboard support.
- `Sources/CaptureStudio/Views/MainWindowView.swift`: show editor canvas and OCR panel for screenshots.
- `Sources/CaptureStudio/Views/EditorToolbarView.swift`: add screenshot editing tools while preserving recording-safe actions.
- `Tests/CaptureStudioTests/CaptureCoordinatorTests.swift`: adjust existing screenshot expectations to include editing state.
- `Tests/CaptureStudioTests/TestDoubles.swift`: update coordinator test doubles for new dependencies.

## Task 1: Editor Layer Models

**Files:**

- Create: `Sources/CaptureStudio/Editing/EditorTool.swift`
- Create: `Sources/CaptureStudio/Editing/EditorLayer.swift`
- Test: `Tests/CaptureStudioTests/EditorLayerTests.swift`

- [ ] **Step 1: Write failing layer tests**

Create `Tests/CaptureStudioTests/EditorLayerTests.swift`:

```swift
import CoreGraphics
import XCTest
@testable import CaptureStudio

final class EditorLayerTests: XCTestCase {
    func testShapeLayerMovesByDelta() {
        var layer = EditorLayer.rectangle(
            ShapeLayer(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                frame: CGRect(x: 10, y: 20, width: 100, height: 80),
                style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 4)
            )
        )

        layer.moveBy(dx: 5, dy: -8)

        XCTAssertEqual(layer.frame, CGRect(x: 15, y: 12, width: 100, height: 80))
    }

    func testFreehandLayerFrameBoundsAllPoints() {
        let layer = EditorLayer.freehand(
            FreehandLayer(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                points: [
                    CGPoint(x: 20, y: 40),
                    CGPoint(x: 60, y: 10),
                    CGPoint(x: 90, y: 70)
                ],
                style: LayerStyle(strokeColor: .blue, fillColor: .clear, lineWidth: 3)
            )
        )

        XCTAssertEqual(layer.frame, CGRect(x: 20, y: 10, width: 70, height: 60))
    }

    func testTextLayerStoresContentAndStyle() {
        let layer = EditorLayer.text(
            TextLayer(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                frame: CGRect(x: 30, y: 40, width: 220, height: 64),
                text: "Release blocker",
                fontSize: 24,
                style: LayerStyle(strokeColor: .clear, fillColor: .yellow, lineWidth: 1)
            )
        )

        XCTAssertEqual(layer.id, UUID(uuidString: "33333333-3333-3333-3333-333333333333")!)
        XCTAssertEqual(layer.frame, CGRect(x: 30, y: 40, width: 220, height: 64))
        XCTAssertEqual(layer.textContent, "Release blocker")
    }
}
```

- [ ] **Step 2: Run the layer tests to verify RED**

Run:

```bash
swift test --filter EditorLayerTests
```

Expected: FAIL because `EditorLayer`, `ShapeLayer`, `FreehandLayer`, `TextLayer`, and `LayerStyle` do not exist.

- [ ] **Step 3: Add editor tool enum**

Create `Sources/CaptureStudio/Editing/EditorTool.swift`:

```swift
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
```

- [ ] **Step 4: Add layer models**

Create `Sources/CaptureStudio/Editing/EditorLayer.swift`:

```swift
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
```

- [ ] **Step 5: Run the layer tests to verify GREEN**

Run:

```bash
swift test --filter EditorLayerTests
```

Expected: PASS.

- [ ] **Step 6: Commit Task 1**

```bash
git add Sources/CaptureStudio/Editing/EditorTool.swift Sources/CaptureStudio/Editing/EditorLayer.swift Tests/CaptureStudioTests/EditorLayerTests.swift
git commit -m "feat: add screenshot editor layer models"
```

## Task 2: Editor Document State And History

**Files:**

- Create: `Sources/CaptureStudio/Editing/EditorHistory.swift`
- Modify: `Sources/CaptureStudio/Models/EditorDocument.swift`
- Test: `Tests/CaptureStudioTests/EditorHistoryTests.swift`
- Test: `Tests/CaptureStudioTests/AppStateTests.swift`

- [ ] **Step 1: Write failing history tests**

Create `Tests/CaptureStudioTests/EditorHistoryTests.swift`:

```swift
import CoreGraphics
import XCTest
@testable import CaptureStudio

final class EditorHistoryTests: XCTestCase {
    func testUndoRestoresPreviousLayerState() {
        let initial = EditorSnapshot(layers: [], selectedLayerID: nil)
        let layer = EditorLayer.rectangle(
            ShapeLayer(
                id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                frame: CGRect(x: 20, y: 20, width: 120, height: 80),
                style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 2)
            )
        )
        let edited = EditorSnapshot(layers: [layer], selectedLayerID: layer.id)
        var history = EditorHistory(current: edited, undoStack: [initial], redoStack: [])

        history.undo()

        XCTAssertEqual(history.current, initial)
        XCTAssertEqual(history.redoStack, [edited])
    }

    func testRedoRestoresUndoneLayerState() {
        let initial = EditorSnapshot(layers: [], selectedLayerID: nil)
        let layer = EditorLayer.rectangle(
            ShapeLayer(
                id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
                frame: CGRect(x: 20, y: 20, width: 120, height: 80),
                style: LayerStyle(strokeColor: .blue, fillColor: .clear, lineWidth: 2)
            )
        )
        let edited = EditorSnapshot(layers: [layer], selectedLayerID: layer.id)
        var history = EditorHistory(current: initial, undoStack: [], redoStack: [edited])

        history.redo()

        XCTAssertEqual(history.current, edited)
        XCTAssertEqual(history.undoStack, [initial])
    }
}
```

- [ ] **Step 2: Write failing document editing state test**

Append to `Tests/CaptureStudioTests/AppStateTests.swift`:

```swift
@MainActor
func testScreenshotDocumentStoresEditingState() {
    let layer = EditorLayer.rectangle(
        ShapeLayer(
            frame: CGRect(x: 10, y: 10, width: 100, height: 50),
            style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 2)
        )
    )

    let document = EditorDocument(
        kind: .screenshot,
        createdAt: Date(timeIntervalSince1970: 10),
        data: Data([0x89, 0x50, 0x4E, 0x47]),
        layers: [layer],
        selectedLayerID: layer.id,
        isDirty: true
    )

    XCTAssertEqual(document.baseImageData, Data([0x89, 0x50, 0x4E, 0x47]))
    XCTAssertEqual(document.layers, [layer])
    XCTAssertEqual(document.selectedLayerID, layer.id)
    XCTAssertTrue(document.hasEdits)
}
```

- [ ] **Step 3: Run tests to verify RED**

Run:

```bash
swift test --filter EditorHistoryTests
swift test --filter AppStateTests/testScreenshotDocumentStoresEditingState
```

Expected: FAIL because `EditorSnapshot`, `EditorHistory`, and new `EditorDocument` properties do not exist.

- [ ] **Step 4: Add history model**

Create `Sources/CaptureStudio/Editing/EditorHistory.swift`:

```swift
import Foundation

public struct EditorSnapshot: Codable, Equatable, Sendable {
    public var layers: [EditorLayer]
    public var selectedLayerID: UUID?

    public init(layers: [EditorLayer], selectedLayerID: UUID?) {
        self.layers = layers
        self.selectedLayerID = selectedLayerID
    }
}

public struct EditorHistory: Equatable, Sendable {
    public var current: EditorSnapshot
    public var undoStack: [EditorSnapshot]
    public var redoStack: [EditorSnapshot]

    public init(current: EditorSnapshot, undoStack: [EditorSnapshot] = [], redoStack: [EditorSnapshot] = []) {
        self.current = current
        self.undoStack = undoStack
        self.redoStack = redoStack
    }

    public mutating func apply(_ next: EditorSnapshot) {
        undoStack.append(current)
        current = next
        redoStack.removeAll()
    }

    public mutating func undo() {
        guard let previous = undoStack.popLast() else {
            return
        }

        redoStack.append(current)
        current = previous
    }

    public mutating func redo() {
        guard let next = redoStack.popLast() else {
            return
        }

        undoStack.append(current)
        current = next
    }
}
```

- [ ] **Step 5: Extend `EditorDocument`**

Modify `Sources/CaptureStudio/Models/EditorDocument.swift` so the struct has these additional properties and initializer parameters:

```swift
public var baseImageData: Data?
public var renderedImageData: Data?
public var layers: [EditorLayer]
public var selectedLayerID: UUID?
public var ocrResult: OCRResult?
public var undoStack: [EditorSnapshot]
public var redoStack: [EditorSnapshot]
```

Update the initializer so screenshot captures keep backward compatibility:

```swift
public init(
    id: UUID = UUID(),
    kind: Kind,
    createdAt: Date = Date(),
    fileURL: URL? = nil,
    data: Data? = nil,
    baseImageData: Data? = nil,
    renderedImageData: Data? = nil,
    layers: [EditorLayer] = [],
    selectedLayerID: UUID? = nil,
    ocrResult: OCRResult? = nil,
    undoStack: [EditorSnapshot] = [],
    redoStack: [EditorSnapshot] = [],
    isDirty: Bool = true
) {
    self.id = id
    self.kind = kind
    self.createdAt = createdAt
    self.fileURL = fileURL
    self.data = data
    self.baseImageData = baseImageData ?? data
    self.renderedImageData = renderedImageData
    self.layers = layers
    self.selectedLayerID = selectedLayerID
    self.ocrResult = ocrResult
    self.undoStack = undoStack
    self.redoStack = redoStack
    self.isDirty = isDirty
}
```

Add computed helpers:

```swift
public var hasEdits: Bool {
    !layers.isEmpty
}

public var currentImageData: Data? {
    renderedImageData ?? data ?? baseImageData
}
```

- [ ] **Step 6: Add temporary OCR model stub to unblock document compilation**

Create `Sources/CaptureStudio/OCR/OCRModels.swift`:

```swift
import CoreGraphics
import Foundation

public struct OCRObservation: Codable, Equatable, Sendable {
    public var text: String
    public var confidence: Float
    public var boundingBox: CGRect

    public init(text: String, confidence: Float, boundingBox: CGRect) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

public struct OCRResult: Codable, Equatable, Sendable {
    public var fullText: String
    public var observations: [OCRObservation]

    public init(fullText: String, observations: [OCRObservation]) {
        self.fullText = fullText
        self.observations = observations
    }
}
```

- [ ] **Step 7: Run tests to verify GREEN**

Run:

```bash
swift test --filter EditorHistoryTests
swift test --filter AppStateTests
```

Expected: PASS.

- [ ] **Step 8: Commit Task 2**

```bash
git add Sources/CaptureStudio/Editing/EditorHistory.swift Sources/CaptureStudio/Models/EditorDocument.swift Sources/CaptureStudio/OCR/OCRModels.swift Tests/CaptureStudioTests/EditorHistoryTests.swift Tests/CaptureStudioTests/AppStateTests.swift
git commit -m "feat: add screenshot editor document state"
```

## Task 3: Canvas Geometry

**Files:**

- Create: `Sources/CaptureStudio/Editing/EditorCanvasGeometry.swift`
- Test: `Tests/CaptureStudioTests/EditorCanvasGeometryTests.swift`

- [ ] **Step 1: Write failing geometry tests**

Create `Tests/CaptureStudioTests/EditorCanvasGeometryTests.swift`:

```swift
import CoreGraphics
import XCTest
@testable import CaptureStudio

final class EditorCanvasGeometryTests: XCTestCase {
    func testImageRectAspectFitsInsideView() {
        let geometry = EditorCanvasGeometry(
            imageSize: CGSize(width: 1600, height: 900),
            viewSize: CGSize(width: 800, height: 800)
        )

        XCTAssertEqual(geometry.imageRectInView, CGRect(x: 0, y: 175, width: 800, height: 450))
    }

    func testViewPointConvertsToImagePixelPoint() {
        let geometry = EditorCanvasGeometry(
            imageSize: CGSize(width: 1600, height: 900),
            viewSize: CGSize(width: 800, height: 800)
        )

        let point = geometry.imagePoint(forViewPoint: CGPoint(x: 400, y: 400))

        XCTAssertEqual(point.x, 800, accuracy: 0.001)
        XCTAssertEqual(point.y, 450, accuracy: 0.001)
    }

    func testImageRectConvertsToViewRect() {
        let geometry = EditorCanvasGeometry(
            imageSize: CGSize(width: 1600, height: 900),
            viewSize: CGSize(width: 800, height: 800)
        )

        let rect = geometry.viewRect(forImageRect: CGRect(x: 400, y: 225, width: 400, height: 225))

        XCTAssertEqual(rect, CGRect(x: 200, y: 287.5, width: 200, height: 112.5))
    }
}
```

- [ ] **Step 2: Run geometry tests to verify RED**

Run:

```bash
swift test --filter EditorCanvasGeometryTests
```

Expected: FAIL because `EditorCanvasGeometry` does not exist.

- [ ] **Step 3: Add geometry helper**

Create `Sources/CaptureStudio/Editing/EditorCanvasGeometry.swift`:

```swift
import CoreGraphics
import Foundation

public struct EditorCanvasGeometry: Equatable, Sendable {
    public var imageSize: CGSize
    public var viewSize: CGSize

    public init(imageSize: CGSize, viewSize: CGSize) {
        self.imageSize = imageSize
        self.viewSize = viewSize
    }

    public var imageRectInView: CGRect {
        guard imageSize.width > 0, imageSize.height > 0, viewSize.width > 0, viewSize.height > 0 else {
            return .zero
        }

        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        let x = (viewSize.width - width) / 2
        let y = (viewSize.height - height) / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    public func imagePoint(forViewPoint point: CGPoint) -> CGPoint {
        let rect = imageRectInView
        guard rect.width > 0, rect.height > 0 else {
            return .zero
        }

        let normalizedX = (point.x - rect.minX) / rect.width
        let normalizedY = (point.y - rect.minY) / rect.height
        return CGPoint(
            x: min(max(normalizedX, 0), 1) * imageSize.width,
            y: min(max(normalizedY, 0), 1) * imageSize.height
        )
    }

    public func viewRect(forImageRect imageRect: CGRect) -> CGRect {
        let rect = imageRectInView
        guard imageSize.width > 0, imageSize.height > 0 else {
            return .zero
        }

        return CGRect(
            x: rect.minX + (imageRect.minX / imageSize.width) * rect.width,
            y: rect.minY + (imageRect.minY / imageSize.height) * rect.height,
            width: (imageRect.width / imageSize.width) * rect.width,
            height: (imageRect.height / imageSize.height) * rect.height
        )
    }
}
```

- [ ] **Step 4: Run geometry tests to verify GREEN**

Run:

```bash
swift test --filter EditorCanvasGeometryTests
```

Expected: PASS.

- [ ] **Step 5: Commit Task 3**

```bash
git add Sources/CaptureStudio/Editing/EditorCanvasGeometry.swift Tests/CaptureStudioTests/EditorCanvasGeometryTests.swift
git commit -m "feat: add editor canvas geometry conversion"
```

## Task 4: Image Render Service

**Files:**

- Create: `Sources/CaptureStudio/Editing/ImageRenderService.swift`
- Test: `Tests/CaptureStudioTests/ImageRenderServiceTests.swift`

- [ ] **Step 1: Write failing render tests**

Create `Tests/CaptureStudioTests/ImageRenderServiceTests.swift`:

```swift
import AppKit
import XCTest
@testable import CaptureStudio

final class ImageRenderServiceTests: XCTestCase {
    func testRenderWithoutLayersReturnsValidPNG() throws {
        let basePNG = try TestImageFactory.pngData(width: 80, height: 60, color: .white)
        let renderer = AppKitImageRenderService()

        let result = try renderer.renderPNG(basePNGData: basePNG, layers: [])

        XCTAssertTrue(result.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        XCTAssertGreaterThan(result.count, 0)
    }

    func testVisibleRectangleLayerChangesRenderedPNG() throws {
        let basePNG = try TestImageFactory.pngData(width: 80, height: 60, color: .white)
        let layer = EditorLayer.rectangle(
            ShapeLayer(
                frame: CGRect(x: 10, y: 10, width: 30, height: 20),
                style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 4)
            )
        )
        let renderer = AppKitImageRenderService()

        let result = try renderer.renderPNG(basePNGData: basePNG, layers: [layer])

        XCTAssertNotEqual(result, basePNG)
        XCTAssertTrue(result.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }
}

private enum TestImageFactory {
    static func pngData(width: Int, height: Int, color: NSColor) throws -> Data {
        let image = NSImage(size: CGSize(width: width, height: height))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:])
        else {
            throw NSError(domain: "TestImageFactory", code: 1)
        }

        return data
    }
}
```

- [ ] **Step 2: Run render tests to verify RED**

Run:

```bash
swift test --filter ImageRenderServiceTests
```

Expected: FAIL because `AppKitImageRenderService` does not exist.

- [ ] **Step 3: Add renderer service**

Create `Sources/CaptureStudio/Editing/ImageRenderService.swift`:

```swift
import AppKit
import CoreImage
import Foundation

public protocol ImageRenderServicing {
    func renderPNG(basePNGData: Data, layers: [EditorLayer]) throws -> Data
}

public enum ImageRenderError: LocalizedError, Equatable {
    case imageDecodeFailed
    case bitmapCreationFailed
    case pngEncodingFailed

    public var errorDescription: String? {
        switch self {
        case .imageDecodeFailed:
            return "captured image could not be decoded."
        case .bitmapCreationFailed:
            return "edited image bitmap could not be created."
        case .pngEncodingFailed:
            return "edited image could not be encoded."
        }
    }
}

public struct AppKitImageRenderService: ImageRenderServicing {
    public init() {}

    public func renderPNG(basePNGData: Data, layers: [EditorLayer]) throws -> Data {
        guard let image = NSImage(data: basePNGData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            throw ImageRenderError.imageDecodeFailed
        }

        let width = cgImage.width
        let height = cgImage.height
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )

        guard let bitmap else {
            throw ImageRenderError.bitmapCreationFailed
        }

        let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.current?.cgContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        for layer in layers {
            draw(layer)
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw ImageRenderError.pngEncodingFailed
        }

        return data
    }

    private func draw(_ layer: EditorLayer) {
        switch layer {
        case .rectangle(let shape):
            drawShape(shape.frame, style: shape.style, oval: false)
        case .ellipse(let shape):
            drawShape(shape.frame, style: shape.style, oval: true)
        case .freehand(let freehand):
            drawPolyline(freehand.points, style: freehand.style, alpha: 1)
        case .highlighter(let highlighter):
            drawPolyline(highlighter.points, style: highlighter.style, alpha: 0.35)
        case .arrow(let arrow):
            drawArrow(arrow)
        case .text(let text):
            drawText(text)
        case .redaction(let redaction):
            drawRedaction(redaction)
        }
    }

    private func drawShape(_ frame: CGRect, style: LayerStyle, oval: Bool) {
        style.fillColor.nsColor.setFill()
        style.strokeColor.nsColor.setStroke()
        let path = oval ? NSBezierPath(ovalIn: frame) : NSBezierPath(rect: frame)
        path.lineWidth = style.lineWidth
        path.fill()
        path.stroke()
    }

    private func drawPolyline(_ points: [CGPoint], style: LayerStyle, alpha: CGFloat) {
        guard points.count > 1 else {
            return
        }

        let path = NSBezierPath()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.line(to: point)
        }
        path.lineWidth = style.lineWidth
        style.strokeColor.nsColor.withAlphaComponent(alpha).setStroke()
        path.stroke()
    }

    private func drawArrow(_ arrow: ArrowLayer) {
        arrow.style.strokeColor.nsColor.setStroke()
        let path = NSBezierPath()
        path.move(to: arrow.start)
        path.line(to: arrow.end)
        path.lineWidth = arrow.style.lineWidth
        path.stroke()
    }

    private func drawText(_ text: TextLayer) {
        text.style.fillColor.nsColor.setFill()
        text.frame.fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: text.fontSize),
            .foregroundColor: text.style.strokeColor.nsColor
        ]
        text.text.draw(in: text.frame.insetBy(dx: 6, dy: 4), withAttributes: attributes)
    }

    private func drawRedaction(_ redaction: RedactionLayer) {
        LayerColor.black.nsColor.setFill()
        redaction.frame.fill()
    }
}

private extension LayerColor {
    var nsColor: NSColor {
        NSColor(
            calibratedRed: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
}
```

- [ ] **Step 4: Run render tests to verify GREEN**

Run:

```bash
swift test --filter ImageRenderServiceTests
```

Expected: PASS.

- [ ] **Step 5: Commit Task 4**

```bash
git add Sources/CaptureStudio/Editing/ImageRenderService.swift Tests/CaptureStudioTests/ImageRenderServiceTests.swift
git commit -m "feat: render edited screenshots"
```

## Task 5: Save And Copy Use Flattened Screenshot Data

**Files:**

- Modify: `Sources/CaptureStudio/Capture/CaptureCoordinator.swift`
- Test: `Tests/CaptureStudioTests/CaptureCoordinatorEditingTests.swift`

- [ ] **Step 1: Write failing coordinator editing tests**

Create `Tests/CaptureStudioTests/CaptureCoordinatorEditingTests.swift`:

```swift
import XCTest
@testable import CaptureStudio

@MainActor
final class CaptureCoordinatorEditingTests: XCTestCase {
    func testSaveCurrentScreenshotUsesRenderedDataWhenLayersExist() throws {
        let appState = AppState()
        let settingsStore = SettingsStore(defaults: isolatedDefaults("saveRendered"))
        let outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        settingsStore.update { settings in
            settings.screenshotFolderPath = outputDirectory.path
        }
        let original = Data([0x89, 0x50, 0x4E, 0x47, 0x00])
        let rendered = Data([0x89, 0x50, 0x4E, 0x47, 0x99])
        let layer = EditorLayer.redaction(
            RedactionLayer(
                frame: CGRect(x: 0, y: 0, width: 10, height: 10),
                style: LayerStyle(strokeColor: .black, fillColor: .black, lineWidth: 1)
            )
        )
        appState.currentDocument = EditorDocument(kind: .screenshot, createdAt: Date(timeIntervalSince1970: 50), data: original, layers: [layer])
        let renderer = MockImageRenderService(renderedData: rendered)
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockScreenshotService(),
            fileOutputService: FileOutputService(),
            imageRenderService: renderer
        )

        coordinator.saveCurrentDocument()

        let fileURL = try XCTUnwrap(appState.currentDocument?.fileURL)
        XCTAssertEqual(try Data(contentsOf: fileURL), rendered)
        XCTAssertEqual(renderer.renderCallCount, 1)
    }

    func testCopyCurrentScreenshotUsesRenderedDataWhenLayersExist() {
        let appState = AppState()
        let settingsStore = SettingsStore(defaults: isolatedDefaults("copyRendered"))
        let original = Data([0x89, 0x50, 0x4E, 0x47, 0x00])
        let rendered = Data([0x89, 0x50, 0x4E, 0x47, 0x88])
        let layer = EditorLayer.redaction(
            RedactionLayer(
                frame: CGRect(x: 0, y: 0, width: 10, height: 10),
                style: LayerStyle(strokeColor: .black, fillColor: .black, lineWidth: 1)
            )
        )
        appState.currentDocument = EditorDocument(kind: .screenshot, data: original, layers: [layer])
        let renderer = MockImageRenderService(renderedData: rendered)
        let clipboard = MockClipboardService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: MockScreenshotService(),
            imageRenderService: renderer,
            clipboardService: clipboard
        )

        coordinator.copyCurrentDocument()

        XCTAssertEqual(clipboard.copiedPNGData, rendered)
        XCTAssertEqual(renderer.renderCallCount, 1)
    }

    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let suiteName = "CaptureCoordinatorEditingTests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
```

Add local mocks to the bottom of the test file:

```swift
@MainActor
private final class MockImageRenderService: ImageRenderServicing {
    let renderedData: Data
    var renderCallCount = 0

    init(renderedData: Data) {
        self.renderedData = renderedData
    }

    func renderPNG(basePNGData: Data, layers: [EditorLayer]) throws -> Data {
        renderCallCount += 1
        return renderedData
    }
}
```

Reuse `MockScreenshotService` and `MockClipboardService` by moving those mocks from `CaptureCoordinatorTests.swift` into a shared test support file if needed:

- Create `Tests/CaptureStudioTests/TestDoubles.swift`.
- Move duplicate mocks there.
- Keep method signatures unchanged.

- [ ] **Step 2: Run coordinator editing tests to verify RED**

Run:

```bash
swift test --filter CaptureCoordinatorEditingTests
```

Expected: FAIL because `CaptureCoordinator` does not accept `imageRenderService` and Save/Copy still use raw screenshot data.

- [ ] **Step 3: Inject render service into coordinator**

Modify `Sources/CaptureStudio/Capture/CaptureCoordinator.swift`:

```swift
private let imageRenderService: ImageRenderServicing
```

Add initializer parameter:

```swift
imageRenderService: ImageRenderServicing = AppKitImageRenderService()
```

Assign it:

```swift
self.imageRenderService = imageRenderService
```

Add helper:

```swift
private func screenshotDataForOutput(_ document: EditorDocument) throws -> Data {
    guard let baseData = document.baseImageData ?? document.data else {
        throw ImageRenderError.imageDecodeFailed
    }

    guard document.hasEdits else {
        return document.renderedImageData ?? document.data ?? baseData
    }

    return try imageRenderService.renderPNG(basePNGData: baseData, layers: document.layers)
}
```

Update screenshot branch in `saveCurrentDocument()`:

```swift
let outputData = try screenshotDataForOutput(document)
let fileURL = try fileOutputService.writeScreenshotData(
    outputData,
    settings: settingsStore.settings,
    date: document.createdAt
)
document.data = outputData
document.renderedImageData = outputData
```

Update screenshot branch in `copyCurrentDocument()`:

```swift
let outputData = try screenshotDataForOutput(document)
clipboardService.copyPNGData(outputData)
```

If render fails, set:

```swift
appState.statusMessage = "Image render failed: \(error.localizedDescription)"
```

- [ ] **Step 4: Run coordinator editing tests to verify GREEN**

Run:

```bash
swift test --filter CaptureCoordinatorEditingTests
swift test --filter CaptureCoordinatorTests
```

Expected: PASS.

- [ ] **Step 5: Commit Task 5**

```bash
git add Sources/CaptureStudio/Capture/CaptureCoordinator.swift Tests/CaptureStudioTests/CaptureCoordinatorEditingTests.swift Tests/CaptureStudioTests/TestDoubles.swift Tests/CaptureStudioTests/CaptureCoordinatorTests.swift
git commit -m "feat: save and copy flattened screenshots"
```

## Task 6: Editor View Model

**Files:**

- Create: `Sources/CaptureStudio/Editing/EditorViewModel.swift`
- Test: `Tests/CaptureStudioTests/EditorViewModelTests.swift`

- [ ] **Step 1: Write failing view model tests**

Create `Tests/CaptureStudioTests/EditorViewModelTests.swift`:

```swift
import XCTest
@testable import CaptureStudio

@MainActor
final class EditorViewModelTests: XCTestCase {
    func testAddLayerMarksDocumentDirtyAndSelectsLayer() {
        let appState = AppState()
        appState.currentDocument = EditorDocument(kind: .screenshot, data: Data([0x89, 0x50, 0x4E, 0x47]), isDirty: false)
        let viewModel = EditorViewModel(appState: appState)
        let layer = EditorLayer.rectangle(
            ShapeLayer(
                frame: CGRect(x: 10, y: 20, width: 80, height: 40),
                style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 2)
            )
        )

        viewModel.addLayer(layer)

        XCTAssertEqual(appState.currentDocument?.layers, [layer])
        XCTAssertEqual(appState.currentDocument?.selectedLayerID, layer.id)
        XCTAssertTrue(appState.currentDocument?.isDirty ?? false)
    }

    func testUndoRestoresPreviousLayerState() {
        let appState = AppState()
        appState.currentDocument = EditorDocument(kind: .screenshot, data: Data([0x89, 0x50, 0x4E, 0x47]))
        let viewModel = EditorViewModel(appState: appState)
        let layer = EditorLayer.rectangle(
            ShapeLayer(
                frame: CGRect(x: 10, y: 20, width: 80, height: 40),
                style: LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 2)
            )
        )

        viewModel.addLayer(layer)
        viewModel.undo()

        XCTAssertEqual(appState.currentDocument?.layers, [])
        XCTAssertNil(appState.currentDocument?.selectedLayerID)
    }
}
```

- [ ] **Step 2: Run view model tests to verify RED**

Run:

```bash
swift test --filter EditorViewModelTests
```

Expected: FAIL because `EditorViewModel` does not exist.

- [ ] **Step 3: Add view model**

Create `Sources/CaptureStudio/Editing/EditorViewModel.swift`:

```swift
import Foundation
import SwiftUI

@MainActor
public final class EditorViewModel: ObservableObject {
    private let appState: AppState

    @Published public var activeTool: EditorTool = .select
    @Published public var style = LayerStyle(strokeColor: .red, fillColor: .clear, lineWidth: 3)
    @Published public var textSize: CGFloat = 20
    @Published public var blurRadius: CGFloat = 8

    public init(appState: AppState) {
        self.appState = appState
    }

    public func addLayer(_ layer: EditorLayer) {
        mutateDocument { document in
            let snapshot = EditorSnapshot(layers: document.layers, selectedLayerID: document.selectedLayerID)
            document.undoStack.append(snapshot)
            document.redoStack.removeAll()
            document.layers.append(layer)
            document.selectedLayerID = layer.id
            document.renderedImageData = nil
            document.isDirty = true
        }
    }

    public func selectLayer(id: UUID?) {
        mutateDocument { document in
            document.selectedLayerID = id
        }
    }

    public func deleteSelectedLayer() {
        mutateDocument { document in
            guard let selectedLayerID = document.selectedLayerID else {
                return
            }

            let snapshot = EditorSnapshot(layers: document.layers, selectedLayerID: document.selectedLayerID)
            document.undoStack.append(snapshot)
            document.redoStack.removeAll()
            document.layers.removeAll { $0.id == selectedLayerID }
            document.selectedLayerID = nil
            document.renderedImageData = nil
            document.isDirty = true
        }
    }

    public func undo() {
        mutateDocument { document in
            guard let previous = document.undoStack.popLast() else {
                return
            }

            let current = EditorSnapshot(layers: document.layers, selectedLayerID: document.selectedLayerID)
            document.redoStack.append(current)
            document.layers = previous.layers
            document.selectedLayerID = previous.selectedLayerID
            document.renderedImageData = nil
            document.isDirty = true
        }
    }

    public func redo() {
        mutateDocument { document in
            guard let next = document.redoStack.popLast() else {
                return
            }

            let current = EditorSnapshot(layers: document.layers, selectedLayerID: document.selectedLayerID)
            document.undoStack.append(current)
            document.layers = next.layers
            document.selectedLayerID = next.selectedLayerID
            document.renderedImageData = nil
            document.isDirty = true
        }
    }

    private func mutateDocument(_ mutate: (inout EditorDocument) -> Void) {
        guard var document = appState.currentDocument, document.kind == .screenshot else {
            return
        }

        mutate(&document)
        appState.currentDocument = document
    }
}
```

- [ ] **Step 4: Run view model tests to verify GREEN**

Run:

```bash
swift test --filter EditorViewModelTests
```

Expected: PASS.

- [ ] **Step 5: Commit Task 6**

```bash
git add Sources/CaptureStudio/Editing/EditorViewModel.swift Tests/CaptureStudioTests/EditorViewModelTests.swift
git commit -m "feat: add screenshot editor view model"
```

## Task 7: Editor UI Shell

**Files:**

- Create: `Sources/CaptureStudio/Views/EditorCanvasView.swift`
- Create: `Sources/CaptureStudio/Views/ToolInspectorView.swift`
- Modify: `Sources/CaptureStudio/Views/EditorToolbarView.swift`
- Modify: `Sources/CaptureStudio/Views/MainWindowView.swift`

- [ ] **Step 1: Update toolbar API**

Modify `Sources/CaptureStudio/Views/EditorToolbarView.swift` to accept screenshot tools:

```swift
struct EditorToolbarView: View {
    let documentKind: EditorDocument.Kind?
    let activeTool: EditorTool
    let onToolSelected: (EditorTool) -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onOCR: () -> Void
    let onQuickRedact: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if documentKind == .screenshot {
                ForEach(EditorTool.allCases.filter { $0 != .ocr }) { tool in
                    toolbarButton(tool.systemImage, tool.title) {
                        onToolSelected(tool)
                    }
                    .background(activeTool == tool ? Color.accentColor.opacity(0.16) : Color.clear)
                }

                Divider().frame(height: 22)
                toolbarButton("arrow.uturn.backward", "Undo", action: onUndo)
                toolbarButton("arrow.uturn.forward", "Redo", action: onRedo)
                toolbarButton("text.viewfinder", "OCR", action: onOCR)
                toolbarButton("eye.slash", "Quick Redact", action: onQuickRedact)
            }

            Divider().frame(height: 22)
            toolbarButton("doc.on.doc", "Copy", action: onCopy)
            toolbarButton("square.and.arrow.down", "Save", action: onSave)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(documentKind == nil ? 0.45 : 1)
    }

    private func toolbarButton(_ systemName: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 24, height: 24)
        }
        .disabled(documentKind == nil)
        .help(help)
    }
}
```

- [ ] **Step 2: Add canvas shell**

Create `Sources/CaptureStudio/Views/EditorCanvasView.swift`:

```swift
import AppKit
import SwiftUI

struct EditorCanvasView: View {
    let document: EditorDocument
    @ObservedObject var editorViewModel: EditorViewModel

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle()
                    .fill(.quaternary.opacity(0.28))

                if let image = nsImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .overlay(layerOverlay(imageSize: image.size, viewSize: proxy.size))
                } else {
                    ContentUnavailableView("No Preview", systemImage: "photo")
                }
            }
        }
    }

    private var nsImage: NSImage? {
        guard let data = document.currentImageData else {
            return nil
        }

        return NSImage(data: data)
    }

    private func layerOverlay(imageSize: CGSize, viewSize: CGSize) -> some View {
        let geometry = EditorCanvasGeometry(imageSize: imageSize, viewSize: viewSize)
        return ZStack {
            ForEach(document.layers) { layer in
                layerView(layer, geometry: geometry)
            }
        }
    }

    private func layerView(_ layer: EditorLayer, geometry: EditorCanvasGeometry) -> some View {
        let rect = geometry.viewRect(forImageRect: layer.frame)
        return Rectangle()
            .stroke(layer.id == document.selectedLayerID ? Color.accentColor : Color.clear, lineWidth: 1)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
}
```

- [ ] **Step 3: Add tool inspector shell**

Create `Sources/CaptureStudio/Views/ToolInspectorView.swift`:

```swift
import SwiftUI

struct ToolInspectorView: View {
    @ObservedObject var editorViewModel: EditorViewModel

    var body: some View {
        HStack(spacing: 12) {
            Stepper("Width \(Int(editorViewModel.style.lineWidth))", value: lineWidthBinding, in: 1...24)
            Stepper("Text \(Int(editorViewModel.textSize))", value: textSizeBinding, in: 10...72)
            Stepper("Blur \(Int(editorViewModel.blurRadius))", value: blurRadiusBinding, in: 2...32)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var lineWidthBinding: Binding<CGFloat> {
        Binding(
            get: { editorViewModel.style.lineWidth },
            set: { editorViewModel.style.lineWidth = $0 }
        )
    }

    private var textSizeBinding: Binding<CGFloat> {
        Binding(
            get: { editorViewModel.textSize },
            set: { editorViewModel.textSize = $0 }
        )
    }

    private var blurRadiusBinding: Binding<CGFloat> {
        Binding(
            get: { editorViewModel.blurRadius },
            set: { editorViewModel.blurRadius = $0 }
        )
    }
}
```

- [ ] **Step 4: Wire `MainWindowView`**

Modify `MainWindowView` to own an editor view model:

```swift
@StateObject private var editorViewModel: EditorViewModel

init(captureCoordinator: CaptureCoordinator, appState: AppState) {
    self.captureCoordinator = captureCoordinator
    _editorViewModel = StateObject(wrappedValue: EditorViewModel(appState: appState))
}
```

If initialization with `@EnvironmentObject` is awkward, introduce `MainWindowContainer` as the owner and pass `appState` explicitly to `MainWindowView`.

Replace `previewArea` document branch:

```swift
if let document = appState.currentDocument, document.kind == .screenshot {
    EditorCanvasView(document: document, editorViewModel: editorViewModel)
} else {
    emptyOrRecordingPreview
}
```

Pass toolbar callbacks:

```swift
EditorToolbarView(
    documentKind: appState.currentDocument?.kind,
    activeTool: editorViewModel.activeTool,
    onToolSelected: { editorViewModel.activeTool = $0 },
    onUndo: editorViewModel.undo,
    onRedo: editorViewModel.redo,
    onCopy: captureCoordinator.copyCurrentDocument,
    onSave: captureCoordinator.saveCurrentDocument,
    onOCR: { Task { await captureCoordinator.runOCR() } },
    onQuickRedact: { Task { await captureCoordinator.quickRedact() } }
)
```

- [ ] **Step 5: Run build**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 6: Commit Task 7**

```bash
git add Sources/CaptureStudio/Views/EditorCanvasView.swift Sources/CaptureStudio/Views/ToolInspectorView.swift Sources/CaptureStudio/Views/EditorToolbarView.swift Sources/CaptureStudio/Views/MainWindowView.swift Sources/CaptureStudio/CaptureStudioApp.swift
git commit -m "feat: add screenshot editor UI shell"
```

## Task 8: OCR Service

**Files:**

- Modify: `Sources/CaptureStudio/OCR/OCRModels.swift`
- Create: `Sources/CaptureStudio/OCR/OCRService.swift`
- Test: `Tests/CaptureStudioTests/OCRResultTests.swift`
- Test: `Tests/CaptureStudioTests/OCRServiceTests.swift`

- [ ] **Step 1: Write OCR model tests**

Create `Tests/CaptureStudioTests/OCRResultTests.swift`:

```swift
import CoreGraphics
import XCTest
@testable import CaptureStudio

final class OCRResultTests: XCTestCase {
    func testVisionNormalizedBoxConvertsToImagePixels() {
        let observation = OCRObservation.fromVision(
            text: "hello@example.com",
            confidence: 0.95,
            normalizedBoundingBox: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.25),
            imageSize: CGSize(width: 1000, height: 800)
        )

        XCTAssertEqual(observation.boundingBox, CGRect(x: 250, y: 400, width: 500, height: 200))
    }

    func testFullTextJoinsObservationsByNewline() {
        let result = OCRResult(observations: [
            OCRObservation(text: "first", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0, width: 10, height: 10)),
            OCRObservation(text: "second", confidence: 0.8, boundingBox: CGRect(x: 0, y: 20, width: 10, height: 10))
        ])

        XCTAssertEqual(result.fullText, "first\nsecond")
    }
}
```

- [ ] **Step 2: Write OCR service fake contract test**

Create `Tests/CaptureStudioTests/OCRServiceTests.swift`:

```swift
import XCTest
@testable import CaptureStudio

final class OCRServiceTests: XCTestCase {
    func testFakeOCRServiceReturnsDeterministicResult() async throws {
        let service = FakeOCRService(result: OCRResult(observations: [
            OCRObservation(text: "token-1234567890", confidence: 1, boundingBox: CGRect(x: 1, y: 2, width: 3, height: 4))
        ]))

        let result = try await service.recognizeText(in: Data([0x89, 0x50, 0x4E, 0x47]))

        XCTAssertEqual(result.fullText, "token-1234567890")
    }
}

private struct FakeOCRService: OCRServicing {
    let result: OCRResult

    func recognizeText(in imageData: Data) async throws -> OCRResult {
        result
    }
}
```

- [ ] **Step 3: Run OCR tests to verify RED**

Run:

```bash
swift test --filter OCRResultTests
swift test --filter OCRServiceTests
```

Expected: FAIL because `fromVision`, `OCRResult(observations:)`, and `OCRServicing` do not exist.

- [ ] **Step 4: Extend OCR models**

Modify `Sources/CaptureStudio/OCR/OCRModels.swift`:

```swift
public struct OCRResult: Codable, Equatable, Sendable {
    public var fullText: String
    public var observations: [OCRObservation]

    public init(fullText: String, observations: [OCRObservation]) {
        self.fullText = fullText
        self.observations = observations
    }

    public init(observations: [OCRObservation]) {
        self.observations = observations
        self.fullText = observations.map(\.text).joined(separator: "\n")
    }
}

public extension OCRObservation {
    static func fromVision(
        text: String,
        confidence: Float,
        normalizedBoundingBox: CGRect,
        imageSize: CGSize
    ) -> OCRObservation {
        let x = normalizedBoundingBox.minX * imageSize.width
        let y = (1 - normalizedBoundingBox.maxY) * imageSize.height
        let width = normalizedBoundingBox.width * imageSize.width
        let height = normalizedBoundingBox.height * imageSize.height
        return OCRObservation(
            text: text,
            confidence: confidence,
            boundingBox: CGRect(x: x, y: y, width: width, height: height).integral
        )
    }
}
```

- [ ] **Step 5: Add Vision-backed OCR service**

Create `Sources/CaptureStudio/OCR/OCRService.swift`:

```swift
import AppKit
import Foundation
import Vision

public protocol OCRServicing {
    func recognizeText(in imageData: Data) async throws -> OCRResult
}

public enum OCRError: LocalizedError, Equatable {
    case imageDecodeFailed
    case cgImageUnavailable
    case noTextFound

    public var errorDescription: String? {
        switch self {
        case .imageDecodeFailed:
            return "image could not be decoded."
        case .cgImageUnavailable:
            return "image could not be prepared for OCR."
        case .noTextFound:
            return "No text found."
        }
    }
}

public struct VisionOCRService: OCRServicing {
    public init() {}

    public func recognizeText(in imageData: Data) async throws -> OCRResult {
        guard let image = NSImage(data: imageData) else {
            throw OCRError.imageDecodeFailed
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.cgImageUnavailable
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])

        let observations = request.results?.compactMap { observation -> OCRObservation? in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }

            return OCRObservation.fromVision(
                text: candidate.string,
                confidence: candidate.confidence,
                normalizedBoundingBox: observation.boundingBox,
                imageSize: CGSize(width: cgImage.width, height: cgImage.height)
            )
        } ?? []

        guard !observations.isEmpty else {
            throw OCRError.noTextFound
        }

        return OCRResult(observations: observations)
    }
}
```

- [ ] **Step 6: Run OCR tests to verify GREEN**

Run:

```bash
swift test --filter OCRResultTests
swift test --filter OCRServiceTests
swift build
```

Expected: PASS.

- [ ] **Step 7: Commit Task 8**

```bash
git add Sources/CaptureStudio/OCR/OCRModels.swift Sources/CaptureStudio/OCR/OCRService.swift Tests/CaptureStudioTests/OCRResultTests.swift Tests/CaptureStudioTests/OCRServiceTests.swift
git commit -m "feat: add vision ocr service"
```

## Task 9: OCR Coordinator And Panel

**Files:**

- Modify: `Sources/CaptureStudio/Capture/CaptureCoordinator.swift`
- Create: `Sources/CaptureStudio/Views/OCRResultPanelView.swift`
- Modify: `Sources/CaptureStudio/Views/MainWindowView.swift`
- Test: `Tests/CaptureStudioTests/CaptureCoordinatorOCRTests.swift`

- [ ] **Step 1: Write failing coordinator OCR test**

Create `Tests/CaptureStudioTests/CaptureCoordinatorOCRTests.swift`:

```swift
import XCTest
@testable import CaptureStudio

@MainActor
final class CaptureCoordinatorOCRTests: XCTestCase {
    func testRunOCRStoresResultOnScreenshotDocument() async {
        let appState = AppState()
        appState.currentDocument = EditorDocument(kind: .screenshot, data: Data([0x89, 0x50, 0x4E, 0x47]))
        let result = OCRResult(observations: [
            OCRObservation(text: "hello@example.com", confidence: 1, boundingBox: CGRect(x: 1, y: 2, width: 3, height: 4))
        ])
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: SettingsStore(defaults: isolatedDefaults("ocr")),
            screenshotService: MockScreenshotService(),
            ocrService: MockOCRService(result: result)
        )

        await coordinator.runOCR()

        XCTAssertEqual(appState.currentDocument?.ocrResult, result)
        XCTAssertEqual(appState.statusMessage, "OCR complete.")
    }

    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let suiteName = "CaptureCoordinatorOCRTests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private struct MockOCRService: OCRServicing {
    let result: OCRResult

    func recognizeText(in imageData: Data) async throws -> OCRResult {
        result
    }
}
```

- [ ] **Step 2: Run OCR coordinator test to verify RED**

Run:

```bash
swift test --filter CaptureCoordinatorOCRTests
```

Expected: FAIL because `CaptureCoordinator` has no `ocrService` dependency and no `runOCR()`.

- [ ] **Step 3: Add OCR dependency and method**

Modify `CaptureCoordinator`:

```swift
private let ocrService: OCRServicing
```

Initializer parameter:

```swift
ocrService: OCRServicing = VisionOCRService()
```

Method:

```swift
public func runOCR() async {
    guard var document = appState.currentDocument, document.kind == .screenshot else {
        appState.statusMessage = "No screenshot to scan."
        return
    }

    do {
        let data = try screenshotDataForOutput(document)
        let result = try await ocrService.recognizeText(in: data)
        document.ocrResult = result
        appState.currentDocument = document
        appState.statusMessage = "OCR complete."
    } catch {
        appState.statusMessage = "OCR failed: \(error.localizedDescription)"
    }
}
```

- [ ] **Step 4: Add OCR result panel**

Create `Sources/CaptureStudio/Views/OCRResultPanelView.swift`:

```swift
import SwiftUI

struct OCRResultPanelView: View {
    let result: OCRResult
    let onCopyText: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Text", systemImage: "text.viewfinder")
                    .font(.headline)
                Spacer()
                Button("Copy") {
                    onCopyText()
                }
            }

            ScrollView {
                Text(result.fullText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}
```

Modify `MainWindowView` to show it when `appState.currentDocument?.ocrResult != nil`.

- [ ] **Step 5: Add copy OCR text**

Add to `CaptureCoordinator`:

```swift
public func copyOCRText() {
    guard let text = appState.currentDocument?.ocrResult?.fullText, !text.isEmpty else {
        appState.statusMessage = "No OCR text to copy."
        return
    }

    clipboardService.copyText(text)
    appState.statusMessage = "OCR text copied."
}
```

Extend `ClipboardServicing` in `PostCaptureServices.swift`:

```swift
func copyText(_ text: String)
```

Implement with `NSPasteboard.PasteboardType.string`.

- [ ] **Step 6: Run OCR coordinator tests**

Run:

```bash
swift test --filter CaptureCoordinatorOCRTests
swift test --filter CaptureCoordinatorTests
swift build
```

Expected: PASS.

- [ ] **Step 7: Commit Task 9**

```bash
git add Sources/CaptureStudio/Capture/CaptureCoordinator.swift Sources/CaptureStudio/Capture/PostCaptureServices.swift Sources/CaptureStudio/Views/OCRResultPanelView.swift Sources/CaptureStudio/Views/MainWindowView.swift Tests/CaptureStudioTests/CaptureCoordinatorOCRTests.swift
git commit -m "feat: add ocr workflow"
```

## Task 10: Redaction Detector

**Files:**

- Create: `Sources/CaptureStudio/Redaction/RedactionDetector.swift`
- Test: `Tests/CaptureStudioTests/RedactionDetectorTests.swift`

- [ ] **Step 1: Write failing detector tests**

Create `Tests/CaptureStudioTests/RedactionDetectorTests.swift`:

```swift
import XCTest
@testable import CaptureStudio

final class RedactionDetectorTests: XCTestCase {
    func testDetectsEmailPhoneURLTokenAndLongNumber() {
        let observations = [
            OCRObservation(text: "Email me at user@example.com", confidence: 1, boundingBox: CGRect(x: 10, y: 10, width: 200, height: 20)),
            OCRObservation(text: "Call 010-1234-5678", confidence: 1, boundingBox: CGRect(x: 10, y: 40, width: 200, height: 20)),
            OCRObservation(text: "Visit https://example.com", confidence: 1, boundingBox: CGRect(x: 10, y: 70, width: 200, height: 20)),
            OCRObservation(text: "key sk-abcdefghijklmnopqrstuvwxyz123456", confidence: 1, boundingBox: CGRect(x: 10, y: 100, width: 260, height: 20)),
            OCRObservation(text: "card 1234567890123456", confidence: 1, boundingBox: CGRect(x: 10, y: 130, width: 220, height: 20))
        ]

        let candidates = RedactionDetector().detect(in: OCRResult(observations: observations))

        XCTAssertEqual(Set(candidates.map(\.kind)), [.email, .phone, .url, .longToken, .longNumber])
    }
}
```

- [ ] **Step 2: Run detector tests to verify RED**

Run:

```bash
swift test --filter RedactionDetectorTests
```

Expected: FAIL because `RedactionDetector` and `RedactionCandidate` do not exist.

- [ ] **Step 3: Add detector**

Create `Sources/CaptureStudio/Redaction/RedactionDetector.swift`:

```swift
import CoreGraphics
import Foundation

public struct RedactionCandidate: Equatable, Identifiable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case email
        case phone
        case url
        case longToken
        case longNumber
    }

    public var id = UUID()
    public var text: String
    public var kind: Kind
    public var boundingBox: CGRect

    public init(id: UUID = UUID(), text: String, kind: Kind, boundingBox: CGRect) {
        self.id = id
        self.text = text
        self.kind = kind
        self.boundingBox = boundingBox
    }
}

public struct RedactionDetector {
    public init() {}

    public func detect(in result: OCRResult) -> [RedactionCandidate] {
        result.observations.flatMap { observation in
            candidates(for: observation)
        }
    }

    private func candidates(for observation: OCRObservation) -> [RedactionCandidate] {
        var candidates: [RedactionCandidate] = []
        appendMatches(pattern: "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", kind: .email, observation: observation, candidates: &candidates)
        appendMatches(pattern: "(\\+?\\d[\\d\\-\\s()]{7,}\\d)", kind: .phone, observation: observation, candidates: &candidates)
        appendMatches(pattern: "https?://[^\\s]+|[A-Z0-9.-]+\\.[A-Z]{2,}", kind: .url, observation: observation, candidates: &candidates)
        appendMatches(pattern: "[A-Z0-9_-]{20,}", kind: .longToken, observation: observation, candidates: &candidates)
        appendMatches(pattern: "\\b\\d{8,}\\b", kind: .longNumber, observation: observation, candidates: &candidates)
        return candidates
    }

    private func appendMatches(
        pattern: String,
        kind: RedactionCandidate.Kind,
        observation: OCRObservation,
        candidates: inout [RedactionCandidate]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return
        }

        let text = observation.text
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: range) {
            guard let swiftRange = Range(match.range, in: text) else {
                continue
            }

            candidates.append(
                RedactionCandidate(
                    text: String(text[swiftRange]),
                    kind: kind,
                    boundingBox: observation.boundingBox
                )
            )
        }
    }
}
```

- [ ] **Step 4: Run detector tests to verify GREEN**

Run:

```bash
swift test --filter RedactionDetectorTests
```

Expected: PASS.

- [ ] **Step 5: Commit Task 10**

```bash
git add Sources/CaptureStudio/Redaction/RedactionDetector.swift Tests/CaptureStudioTests/RedactionDetectorTests.swift
git commit -m "feat: detect sensitive screenshot text"
```

## Task 11: Quick Redact Integration

**Files:**

- Modify: `Sources/CaptureStudio/Capture/CaptureCoordinator.swift`
- Test: `Tests/CaptureStudioTests/QuickRedactIntegrationTests.swift`

- [ ] **Step 1: Write failing quick redact test**

Create `Tests/CaptureStudioTests/QuickRedactIntegrationTests.swift`:

```swift
import XCTest
@testable import CaptureStudio

@MainActor
final class QuickRedactIntegrationTests: XCTestCase {
    func testQuickRedactCreatesRedactionLayersFromOCRCandidates() async {
        let appState = AppState()
        appState.currentDocument = EditorDocument(kind: .screenshot, data: Data([0x89, 0x50, 0x4E, 0x47]))
        let ocr = OCRResult(observations: [
            OCRObservation(text: "Email user@example.com", confidence: 1, boundingBox: CGRect(x: 10, y: 20, width: 200, height: 24))
        ])
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: SettingsStore(defaults: isolatedDefaults("quickRedact")),
            screenshotService: MockScreenshotService(),
            ocrService: MockOCRService(result: ocr),
            redactionDetector: RedactionDetector()
        )

        await coordinator.quickRedact()

        XCTAssertEqual(appState.currentDocument?.layers.count, 1)
        XCTAssertEqual(appState.currentDocument?.layers.first?.frame, CGRect(x: 10, y: 20, width: 200, height: 24))
        XCTAssertEqual(appState.statusMessage, "Redaction added.")
    }

    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let suiteName = "QuickRedactIntegrationTests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
```

- [ ] **Step 2: Run quick redact test to verify RED**

Run:

```bash
swift test --filter QuickRedactIntegrationTests
```

Expected: FAIL because `CaptureCoordinator` has no `redactionDetector` dependency and no `quickRedact()`.

- [ ] **Step 3: Add redaction dependency and method**

Modify `CaptureCoordinator` initializer:

```swift
private let redactionDetector: RedactionDetector
```

Initializer parameter:

```swift
redactionDetector: RedactionDetector = RedactionDetector()
```

Method:

```swift
public func quickRedact() async {
    guard var document = appState.currentDocument, document.kind == .screenshot else {
        appState.statusMessage = "No screenshot to redact."
        return
    }

    do {
        let result: OCRResult
        if let existing = document.ocrResult {
            result = existing
        } else {
            let data = try screenshotDataForOutput(document)
            result = try await ocrService.recognizeText(in: data)
            document.ocrResult = result
        }

        let candidates = redactionDetector.detect(in: result)
        guard !candidates.isEmpty else {
            appState.currentDocument = document
            appState.statusMessage = "No sensitive text found."
            return
        }

        let snapshot = EditorSnapshot(layers: document.layers, selectedLayerID: document.selectedLayerID)
        document.undoStack.append(snapshot)
        document.redoStack.removeAll()
        let newLayers = candidates.map { candidate in
            EditorLayer.redaction(
                RedactionLayer(
                    frame: candidate.boundingBox,
                    style: LayerStyle(strokeColor: .black, fillColor: .black, lineWidth: 1)
                )
            )
        }
        document.layers.append(contentsOf: newLayers)
        document.selectedLayerID = newLayers.last?.id
        document.renderedImageData = nil
        document.isDirty = true
        appState.currentDocument = document
        appState.statusMessage = newLayers.count == 1 ? "Redaction added." : "\(newLayers.count) redactions added."
    } catch {
        appState.statusMessage = "Redaction failed: \(error.localizedDescription)"
    }
}
```

- [ ] **Step 4: Run quick redact tests to verify GREEN**

Run:

```bash
swift test --filter QuickRedactIntegrationTests
swift test --filter CaptureCoordinatorOCRTests
```

Expected: PASS.

- [ ] **Step 5: Commit Task 11**

```bash
git add Sources/CaptureStudio/Capture/CaptureCoordinator.swift Tests/CaptureStudioTests/QuickRedactIntegrationTests.swift
git commit -m "feat: add quick redact workflow"
```

## Task 12: Final Integration And Manual Verification

**Files:**

- Modify: `Tests/CaptureStudioTests/CaptureWorkflowIntegrationTests.swift`
- Modify: `README.md`

- [ ] **Step 1: Add edited screenshot integration test**

Append to `CaptureWorkflowIntegrationTests`:

```swift
func testActualScreenshotWithRedactionLayerSavesFlattenedPNG() async throws {
    try Self.skipUnlessIntegrationIsEnabled()
    let temporaryDirectory = try Self.makeTemporaryDirectory()
    let appState = AppState()
    let settingsStore = SettingsStore(defaults: Self.isolatedDefaults("actualEditedScreenshot"))
    settingsStore.update { settings in
        settings.screenshotFolderPath = temporaryDirectory.path
        settings.automaticallySaveScreenshots = false
        settings.copyCapturedImageToClipboard = false
        settings.defaultDelaySeconds = 0
    }
    let coordinator = try await Self.makeCoordinator(appState: appState, settingsStore: settingsStore)

    await coordinator.startNewCapture()

    var document = try XCTUnwrap(appState.currentDocument)
    document.layers = [
        EditorLayer.redaction(
            RedactionLayer(
                frame: CGRect(x: 5, y: 5, width: 40, height: 30),
                style: LayerStyle(strokeColor: .black, fillColor: .black, lineWidth: 1)
            )
        )
    ]
    appState.currentDocument = document
    coordinator.saveCurrentDocument()

    let fileURL = try XCTUnwrap(appState.currentDocument?.fileURL)
    XCTAssertEqual(fileURL.deletingLastPathComponent().standardizedFileURL, temporaryDirectory.standardizedFileURL)
    XCTAssertGreaterThan(try Self.fileSize(at: fileURL), 0)
}
```

- [ ] **Step 2: Update README run notes**

Replace `README.md` with:

````markdown
# Capture Studio

Native macOS screenshot and screen recording app inspired by Windows Snipping Tool.

## Requirements

- macOS 15 or newer
- Xcode command line tools
- Swift 6

## Run

```bash
swift run CaptureStudio
```

## Test

```bash
swift test
```

Run ScreenCaptureKit and screenshot-editor integration tests:

```bash
CAPTURE_STUDIO_RUN_INTEGRATION=1 swift test
```

## Screenshot Editing

After a screenshot is captured, the editor toolbar can annotate, OCR, and redact the screenshot before saving or copying. Save and Copy flatten annotation layers into a PNG. OCR and Quick Redact run on demand.

## Current Milestone

This milestone includes:

- Minimal main window
- Settings window
- Persistent settings
- Customizable shortcut model with reset defaults
- Output filename and folder fallback model
- Capture coordinator interfaces
- Real screen region selection
- Screenshot capture and screen recording
- Screenshot editing, OCR, and quick redaction

Color picker and recording trim are separate implementation milestones.
````

- [ ] **Step 3: Run full verification**

Run:

```bash
swift test
CAPTURE_STUDIO_RUN_INTEGRATION=1 swift test
swift build
git diff --check
```

Expected:

- `swift test`: PASS with integration tests skipped.
- `CAPTURE_STUDIO_RUN_INTEGRATION=1 swift test`: PASS with actual capture integrations.
- `swift build`: PASS.
- `git diff --check`: no output.

- [ ] **Step 4: Manual verification checklist**

Run the app:

```bash
swift run CaptureStudio
```

Verify manually:

- Capture screenshot.
- Add rectangle, arrow, text, highlighter, and redaction layers.
- Undo and redo layer creation.
- Save edited screenshot and open it from the configured folder.
- Copy edited screenshot and paste into Preview or Notes.
- Run OCR on visible text.
- Copy OCR text.
- Run Quick Redact on visible email or phone text.
- Confirm recording flow still records and saves.

- [ ] **Step 5: Commit final integration**

```bash
git add Tests/CaptureStudioTests/CaptureWorkflowIntegrationTests.swift README.md
git commit -m "test: cover edited screenshot workflow"
```

## Final Verification Before Completion

Run:

```bash
swift test
CAPTURE_STUDIO_RUN_INTEGRATION=1 swift test
swift build
git status --short --branch
```

Completion requires:

- All tests pass.
- Integration tests pass in the local ScreenCaptureKit-permitted environment.
- Build passes.
- Worktree is clean.
- Final answer reports any manual verification gaps honestly.

## Spec Coverage Review

- Editor data model: Tasks 1, 2, 6.
- Image-coordinate conversion: Task 3.
- Flattened Save/Copy: Tasks 4, 5.
- UI toolbar and canvas shell: Task 7.
- OCR model and service: Tasks 8, 9.
- Quick Redact: Tasks 10, 11.
- Integration and manual verification: Task 12.

## Execution Handoff

Plan complete when this file is saved and committed. Use an isolated worktree before implementation. Recommended branch name:

```bash
codex/image-editor-ocr-redact
```
