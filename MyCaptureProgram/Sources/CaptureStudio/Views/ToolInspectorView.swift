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
