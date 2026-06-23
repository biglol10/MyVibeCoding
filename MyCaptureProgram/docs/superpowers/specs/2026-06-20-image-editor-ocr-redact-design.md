# Image Editor, OCR, and Redact Design

## Goal

Add a practical post-capture workflow for screenshots: annotation editing, OCR text extraction, and quick redaction. The feature should turn Capture Studio from a capture-and-save utility into a tool that can prepare screenshots for sharing without opening Preview, Keynote, or another editor.

## Scope

This design covers screenshot documents only.

Included:

- Image editor canvas for captured PNG screenshots.
- Annotation tools: arrow, rectangle, ellipse, freehand pen, highlighter, text box, blur/redact rectangle.
- Tool settings: stroke color, fill color, line width, text size, blur strength.
- Selection, move, resize, delete, undo, and redo for editor layers.
- Export flattened PNG data for Save and Copy.
- OCR text extraction from the captured image.
- OCR results panel with copy-all and copy-selected text.
- Quick redact for detected emails, phone numbers, URLs, API-key-like long tokens, and long numeric identifiers.
- Tests for layer model behavior, flatten/export flow, OCR service contracts, and redaction detection.

Excluded from this design:

- MP4 recording trim.
- GIF export.
- Scrolling capture.
- Multi-window editing.
- AI summarization or external model calls.
- Full document management/history.

## Product Behavior

After a screenshot is captured, the preview area becomes an editor. The bottom toolbar shows tools that are meaningful for screenshots:

- Select
- Pen
- Highlighter
- Arrow
- Rectangle
- Ellipse
- Text
- Redact
- OCR
- Copy
- Save

Recording documents keep the simpler Copy/Save behavior and do not show image-only editing tools.

For screenshots, Copy and Save use the current flattened image. If no edits exist, flattening returns the original PNG data. If edits exist, flattening composites all annotation layers over the captured image and writes a new PNG.

OCR is explicit. The app should not run OCR automatically after every screenshot. The user presses OCR, the app analyzes the current base image or flattened image, then displays recognized text. Quick redact can use the OCR output to place redaction layers over detected sensitive ranges.

## Data Model

`EditorDocument` remains the active document wrapper but gains screenshot-editing state:

- `baseImageData: Data?` for original screenshot PNG data.
- `renderedImageData: Data?` for the latest flattened PNG cache.
- `layers: [EditorLayer]` for annotations.
- `selectedLayerID: UUID?`.
- `ocrResult: OCRResult?`.
- `undoStack: [EditorSnapshot]`.
- `redoStack: [EditorSnapshot]`.

`EditorLayer` is an enum-backed model:

- `freehand(FreehandLayer)`
- `highlight(FreehandLayer)`
- `arrow(ArrowLayer)`
- `rectangle(ShapeLayer)`
- `ellipse(ShapeLayer)`
- `text(TextLayer)`
- `redaction(RedactionLayer)`

Every layer stores:

- `id`
- `frame`
- `style`
- `createdAt`

Freehand layers also store points in image coordinates. Text layers store text content, font size, foreground color, and optional background color. Redaction layers store mode: `.solid` or `.blur(radius:)`.

Coordinates are stored in image pixel coordinates, not SwiftUI view coordinates. The editor view converts between displayed image coordinates and pixel coordinates. This avoids corrupting edits when the window resizes.

## Rendering Architecture

Rendering should be isolated behind a service:

`ImageRenderService`

- Input: base PNG data, image size, layers.
- Output: flattened PNG data.
- Implementation: AppKit/CoreGraphics drawing into a bitmap context.
- Responsibility: compositing layers, rendering text, drawing shapes, applying blur/redaction effects.

The editor UI does not write files directly. It mutates the document model and asks `CaptureCoordinator` to save or copy. `CaptureCoordinator` uses `ImageRenderService` to get the flattened data before delegating to `FileOutputService` or `ClipboardServicing`.

## Editor UI

`EditorCanvasView`

- Displays the screenshot.
- Draws layer overlays.
- Handles pointer interactions for creating, selecting, dragging, and resizing layers.
- Exposes image-coordinate edits to `EditorViewModel`.

`EditorViewModel`

- Owns the current tool.
- Applies model mutations to `AppState.currentDocument`.
- Maintains undo/redo snapshots.
- Requests flattening through `ImageRenderService`.

`EditorToolbarView`

- Switches between screenshot editing mode and recording mode.
- Screenshot mode shows editing tools plus OCR/Copy/Save.
- Recording mode shows recording-safe actions only.

`ToolInspectorView`

- Compact side or popover panel for color, width, text size, and blur strength.
- Hidden unless a screenshot document is active.

The main window should remain minimal. Editing controls appear only after a screenshot exists.

## OCR Architecture

`OCRServicing`

- Method: `recognizeText(in imageData: Data) async throws -> OCRResult`.
- Default implementation: Apple Vision text recognition.
- Test implementation: deterministic fake OCR service.

`OCRResult`

- `fullText: String`
- `observations: [OCRObservation]`

`OCRObservation`

- `text: String`
- `confidence: Float`
- `boundingBox: CGRect`

Bounding boxes are normalized by Vision, then converted into image pixel coordinates before storing. Redaction uses image pixel coordinates so it stays aligned with rendered output.

## Redaction Detection

`RedactionDetector`

- Input: OCR observations.
- Output: `[RedactionCandidate]`.

Initial detectors:

- Email: common email regex.
- Phone: permissive phone regex for Korean and international formats.
- URL: `http://`, `https://`, and common domain-like strings.
- Long token: 20+ character alphanumeric strings with separators allowed.
- Long number: 8+ contiguous digits.

The detector should prefer false negatives over aggressive false positives. It should never permanently alter the base image. Quick redact creates editable redaction layers, so the user can delete or resize them before saving.

## Save And Copy Flow

Screenshot save flow:

1. `CaptureCoordinator.saveCurrentDocument()` checks screenshot document.
2. If layers exist or rendered cache is stale, it asks `ImageRenderService` to flatten.
3. It writes flattened PNG data through `FileOutputService`.
4. It updates `currentDocument.fileURL`, `renderedImageData`, and `isDirty`.

Screenshot copy flow:

1. `CaptureCoordinator.copyCurrentDocument()` checks screenshot document.
2. It flattens if needed.
3. It copies flattened PNG data through `ClipboardServicing`.

Recording save/copy behavior remains unchanged.

## Error Handling

Rendering errors:

- If base PNG cannot be decoded, show `Image render failed: captured image could not be decoded.`
- If flattened PNG encoding fails, show `Image render failed: edited image could not be encoded.`

OCR errors:

- If Vision fails, show `OCR failed: <localized error>`.
- If no text is found, show `No text found.`

Redaction errors:

- If OCR has not run, Quick Redact triggers OCR first.
- If no candidates are detected, show `No sensitive text found.`

Save/copy errors:

- Existing save/copy status messages remain, but screenshot save/copy should refer to edited image data when edits exist.

## Testing Strategy

Unit tests:

- `EditorLayerTests`: layer creation, selection, movement, resize, delete.
- `EditorHistoryTests`: undo/redo snapshots.
- `ImageRenderServiceTests`: flattened output differs after adding a visible layer and remains valid PNG.
- `OCRResultTests`: normalized OCR boxes convert to image pixel coordinates.
- `RedactionDetectorTests`: emails, phone numbers, URLs, long tokens, and long numbers create candidates.
- `CaptureCoordinatorEditingTests`: save/copy uses flattened PNG when layers exist and original PNG when no layers exist.

Integration tests:

- Existing ScreenCaptureKit tests stay.
- Add an optional integration test that captures a real screenshot, adds a deterministic redaction layer, saves, and verifies valid PNG output.

Manual verification:

- Capture a screenshot.
- Draw arrow, rectangle, text, highlighter, and redaction.
- Undo/redo each edit.
- Save and reopen the PNG.
- Copy and paste into Preview or Notes.
- Run OCR on a screenshot containing visible text.
- Run Quick Redact on text containing email/phone/token.

## Delivery Order

Phase 1: Editor data model and renderer.

- Add layer models.
- Add image-coordinate conversion helpers.
- Add flattening service.
- Wire Save/Copy to flattened PNG.

Phase 2: Canvas and toolbar.

- Add screenshot editor canvas.
- Add select, shape, freehand, text, and redaction tools.
- Add undo/redo.

Phase 3: OCR.

- Add Vision-backed OCR service.
- Add OCR result panel.
- Add copy-all and copy-selected text.

Phase 4: Quick Redact.

- Add detectors.
- Convert detections into editable redaction layers.
- Add Quick Redact action.

## Open Design Choices

These choices are intentionally fixed for the first implementation:

- Redaction defaults to solid black boxes, with blur available as a tool setting.
- OCR runs only on demand.
- Redaction candidates are editable overlay layers, not destructive base-image edits.
- Layer coordinates use image pixel coordinates.
- The first editor version supports one active screenshot document at a time.

## Acceptance Criteria

- A screenshot can be annotated and saved as a flattened PNG.
- Copy uses the edited image, not only the original capture.
- Undo/redo works for layer creation, movement, deletion, and style changes.
- OCR can extract text from a screenshot and copy it.
- Quick Redact creates editable redaction layers over detected sensitive text.
- Existing capture, recording, settings, and save tests continue to pass.
- Optional integration tests can still be run with `CAPTURE_STUDIO_RUN_INTEGRATION=1`.
