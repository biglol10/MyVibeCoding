import MyMacSearchCore
import SwiftUI

struct SearchFilterTokensView: View {
    let tokens: [SearchQueryToken]
    let onRemove: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tokens) { token in
                    HStack(spacing: 4) {
                        Text(token.rawText)
                            .lineLimit(1)
                        Button {
                            onRemove(token.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove filter \(token.rawText)")
                    }
                    .font(.caption)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                }
            }
        }
    }
}
