import SwiftUI
import MyMacCleanCore
import MyMacCleanAppSupport

struct SizeText: View {
    let bytes: Int64

    var body: some View {
        Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
            .monospacedDigit()
    }
}

struct ConfidenceBadge: View {
    let confidence: MatchConfidence

    var body: some View {
        Text(confidence.rawValue.capitalized)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(background)
            .clipShape(Capsule())
    }

    private var background: Color {
        switch confidence {
        case .high: Color.blue.opacity(0.12)
        case .medium: Color.orange.opacity(0.16)
        case .low: Color.gray.opacity(0.14)
        }
    }
}

struct SafetyBadge: View {
    let safety: CandidateSafetyLevel

    var body: some View {
        Text(title)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(background)
            .clipShape(Capsule())
    }

    private var title: String {
        switch safety {
        case .safe: "Safe"
        case .review: "Review"
        case .risky: "Risky"
        }
    }

    private var background: Color {
        switch safety {
        case .safe: Color.green.opacity(0.16)
        case .review: Color.orange.opacity(0.18)
        case .risky: Color.red.opacity(0.18)
        }
    }
}

struct RelatedFileRow: View {
    let candidate: RelatedFileCandidate
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 16) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(candidate.isProtected ? Color.secondary : Color.blue)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 5) {
                    Text(candidate.url.lastPathComponent)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    Text(candidate.url.path)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(evidenceText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                HStack(spacing: 18) {
                    SafetyBadge(safety: candidate.safety)
                        .frame(minWidth: 88, alignment: .trailing)
                    SizeText(bytes: candidate.size)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 56, alignment: .trailing)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 78)
            .background(rowBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(rowStroke, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(candidate.isProtected)
        .opacity(candidate.isProtected ? 0.55 : 1)
    }

    private var rowBackground: Color {
        isSelected ? Color.blue.opacity(0.08) : Color.primary.opacity(0.035)
    }

    private var rowStroke: Color {
        isSelected ? Color.blue.opacity(0.16) : Color.primary.opacity(0.055)
    }

    private var evidenceText: String {
        guard let evidence = candidate.evidence.first else { return candidate.matchReason }
        return "\(evidence.type.rawValue): \(evidence.matchedValue)"
    }
}

struct DeleteActionButton: View {
    let selectedCount: Int
    let selectedBytes: Int64
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "trash.fill")
                    .font(.title3.weight(.semibold))
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Permanently Delete Selected Items")
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(summary)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(isDisabled ? Color.secondary : Color.white.opacity(0.82))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.callout.weight(.bold))
                    .opacity(isDisabled ? 0 : 0.75)
            }
            .foregroundStyle(isDisabled ? Color.secondary : Color.white)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(background)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private var isDisabled: Bool {
        selectedCount == 0
    }

    private var summary: String {
        if isDisabled {
            return "Select related files first"
        }
        let size = ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file)
        return "\(selectedCount) items selected - \(size)"
    }

    private var background: Color {
        isDisabled ? Color.primary.opacity(0.07) : Color.red.opacity(0.88)
    }

    private var borderColor: Color {
        isDisabled ? Color.primary.opacity(0.08) : Color.red.opacity(0.35)
    }
}

struct SidebarDestinationRow: View {
    let destination: SidebarDestination
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: destination.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.blue)
                    .frame(width: 22)

                Text(destination.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(rowBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(rowBorder, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(destination.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rowBackground: Color {
        isSelected ? Color.blue.opacity(0.22) : Color.clear
    }

    private var rowBorder: Color {
        isSelected ? Color.blue.opacity(0.28) : Color.clear
    }
}
