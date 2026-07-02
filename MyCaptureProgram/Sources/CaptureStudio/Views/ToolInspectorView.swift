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
                if presentation.showsLineWidth {
                    Stepper("Width \(Int(editorViewModel.displayedLineWidth))", value: lineWidthBinding, in: 1...24)
                }

                if presentation.showsTextSize {
                    Stepper("Text \(Int(editorViewModel.displayedTextSize))", value: textSizeBinding, in: 10...72)
                }
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
