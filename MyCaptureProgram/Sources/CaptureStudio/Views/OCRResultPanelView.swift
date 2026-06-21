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
