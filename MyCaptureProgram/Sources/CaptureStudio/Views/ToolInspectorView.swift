import AppKit
import SwiftUI

struct ToolInspectorPresentation: Equatable {
    let showsLineWidth: Bool
    let showsTextSize: Bool
    let showsTextContent: Bool

    var isVisible: Bool {
        showsLineWidth || showsTextSize || showsTextContent
    }

    static func controls(for tool: EditorTool, selectedLayer: EditorLayer?) -> ToolInspectorPresentation {
        switch tool {
        case .pen, .highlighter, .arrow, .rectangle, .ellipse:
            return ToolInspectorPresentation(showsLineWidth: true, showsTextSize: false, showsTextContent: false)
        case .text:
            return ToolInspectorPresentation(
                showsLineWidth: false,
                showsTextSize: true,
                showsTextContent: selectedLayer?.textContent != nil
            )
        case .select:
            if selectedLayer?.textContent != nil {
                return ToolInspectorPresentation(showsLineWidth: false, showsTextSize: true, showsTextContent: true)
            }
            if selectedLayer?.lineWidth != nil {
                return ToolInspectorPresentation(showsLineWidth: true, showsTextSize: false, showsTextContent: false)
            }
            return ToolInspectorPresentation(showsLineWidth: false, showsTextSize: false, showsTextContent: false)
        case .redaction, .ocr:
            return ToolInspectorPresentation(showsLineWidth: false, showsTextSize: false, showsTextContent: false)
        }
    }
}

struct ToolInspectorView: View {
    let selectedLayer: EditorLayer?
    @ObservedObject var editorViewModel: EditorViewModel

    var body: some View {
        let presentation = ToolInspectorPresentation.controls(
            for: editorViewModel.activeTool,
            selectedLayer: selectedLayer
        )

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if presentation.showsLineWidth || presentation.showsTextSize {
                    ColorPicker("Color", selection: strokeColorBinding, supportsOpacity: false)
                        .fixedSize()
                }
                if presentation.showsLineWidth {
                    Stepper("Width \(Int(editorViewModel.displayedLineWidth))", value: lineWidthBinding, in: 1...24)
                }

                if presentation.showsTextSize {
                    Stepper("Text \(Int(editorViewModel.displayedTextSize))", value: textSizeBinding, in: 10...72)
                }
            }

            if let layer = selectedLayer, layer.isResizable {
                HStack(spacing: 12) {
                    Text("Annotation size (px)").foregroundStyle(.secondary)
                    TextField("Width", value: Binding<Double>(
                        get: { Double(layer.frame.width) },
                        set: { editorViewModel.resizeSelectedLayer(width: CGFloat($0), height: layer.frame.height) }
                    ), format: .number).frame(width: 72)
                    Text("×")
                    TextField("Height", value: Binding<Double>(
                        get: { Double(layer.frame.height) },
                        set: { editorViewModel.resizeSelectedLayer(width: layer.frame.width, height: CGFloat($0)) }
                    ), format: .number).frame(width: 72)
                }.textFieldStyle(.roundedBorder)
            }

            if presentation.showsTextContent {
                HStack(spacing: 10) {
                    Text("Content")
                        .foregroundStyle(.secondary)
                    TextField("Text", text: textContentBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 220, maxWidth: 320)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var strokeColorBinding: Binding<Color> {
        Binding(get: {
            let color = editorViewModel.displayedStrokeColor
            return Color(red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
        }, set: { value in
            guard let color = NSColor(value).usingColorSpace(.sRGB) else { return }
            editorViewModel.updateDisplayedStrokeColor(LayerColor(
                red: color.redComponent, green: color.greenComponent, blue: color.blueComponent
            ))
        })
    }

    private var lineWidthBinding: Binding<CGFloat> {
        Binding(
            get: { editorViewModel.displayedLineWidth },
            set: { editorViewModel.updateDisplayedLineWidth($0) }
        )
    }

    private var textSizeBinding: Binding<CGFloat> {
        Binding(
            get: { editorViewModel.displayedTextSize },
            set: { editorViewModel.updateDisplayedTextSize($0) }
        )
    }

    private var textContentBinding: Binding<String> {
        Binding(
            get: { editorViewModel.editableText },
            set: { editorViewModel.updateSelectedText($0) }
        )
    }
}
