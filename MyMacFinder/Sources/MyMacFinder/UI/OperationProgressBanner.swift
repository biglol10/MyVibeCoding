import SwiftUI

struct OperationProgressBanner: View {
    let snapshot: FileOperationProgressSnapshot
    let onCancel: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            progressIndicator

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(snapshot.phase == .failed ? Color.red : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            Text(snapshot.statusText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            if snapshot.isCancellable {
                Button(action: onCancel) {
                    Label("Cancel", systemImage: "xmark.circle")
                        .labelStyle(.titleAndIcon)
                }
                .controlSize(.small)
                .help("Cancel Operation")
            } else if snapshot.isTerminal {
                Button(action: onDismiss) {
                    Label("Dismiss", systemImage: "xmark")
                        .labelStyle(.titleAndIcon)
                }
                .controlSize(.small)
                .help("Dismiss Operation")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private var progressIndicator: some View {
        if let fraction = snapshot.fractionCompleted {
            ProgressView(value: fraction)
                .frame(width: 120)
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(width: 120)
        }
    }

    private var detailText: String {
        snapshot.errorMessage ?? snapshot.currentItemName ?? snapshot.statusText
    }
}
