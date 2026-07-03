import SwiftUI

struct PrivacyAccessSettingsView: View {
    let sandboxPolicy: SandboxPolicySummary
    let grantedFolderSummaries: [FolderAccessGrantSummary]
    let onChooseFolder: () -> Void
    let onOpenPrivacySettings: () -> Void
    let onRemoveGrant: (FolderAccessGrantSummary.ID) -> Void
    let onResetGrants: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statusPanel
                actionsPanel
                foldersPanel
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(maxWidth: 620, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.white, Color.accentColor)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.18))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Privacy & Access")
                    .font(.title3.weight(.semibold))
                Text("Manage folder access and macOS privacy recovery options.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusPanel: some View {
        SettingsPanel {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: sandboxPolicy.isSandboxed ? "shippingbox" : "checkmark.shield")
                    .font(.title3)
                    .foregroundStyle(sandboxPolicy.isSandboxed ? .orange : .green)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Sandbox")
                            .font(.headline)
                        StatusBadge(
                            title: sandboxPolicy.statusTitle,
                            color: sandboxPolicy.isSandboxed ? .orange : .green
                        )
                    }

                    Text(sandboxPolicy.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var actionsPanel: some View {
        SettingsPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Access Recovery")
                    .font(.headline)

                HStack(spacing: 10) {
                    Button(action: onChooseFolder) {
                        Label("Choose Folder...", systemImage: "folder.badge.plus")
                            .frame(minWidth: 150)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: onOpenPrivacySettings) {
                        Label("Privacy Settings", systemImage: "lock.shield")
                            .frame(minWidth: 150)
                    }
                    .buttonStyle(.bordered)

                    Spacer(minLength: 0)
                }

                Text("Use folder grants for sandboxed builds. Use macOS Privacy Settings when protected locations need Full Disk Access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var foldersPanel: some View {
        SettingsPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Selected Folders")
                            .font(.headline)
                        Text("\(grantedFolderSummaries.count) folder\(grantedFolderSummaries.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !grantedFolderSummaries.isEmpty {
                        Button("Reset", role: .destructive, action: onResetGrants)
                            .controlSize(.small)
                    }
                }

                if grantedFolderSummaries.isEmpty {
                    emptyFolderState
                } else {
                    VStack(spacing: 0) {
                        ForEach(grantedFolderSummaries) { grant in
                            FolderGrantRow(
                                grant: grant,
                                onRemove: { onRemoveGrant(grant.id) }
                            )
                            if grant.id != grantedFolderSummaries.last?.id {
                                Divider()
                                    .padding(.leading, 34)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                    )
                }
            }
        }
    }

    private var emptyFolderState: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("No folders selected")
                    .font(.callout.weight(.medium))
                Text("Choose a folder when macOS blocks access to a location you trust.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}

private struct SettingsPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
            )
    }
}

private struct StatusBadge: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.15))
            )
    }
}

private struct FolderGrantRow: View {
    let grant: FolderAccessGrantSummary
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: grant.availability.systemImageName)
                .foregroundStyle(grant.availability.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(grant.displayPath)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(grant.statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle")
                    .imageScale(.medium)
            }
            .buttonStyle(.borderless)
            .help("Remove")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.secondary.opacity(0.05))
    }
}

private extension FolderAccessGrantSummary {
    var statusText: String {
        if isStale {
            return "Bookmark refreshed"
        }

        switch availability {
        case .available:
            return "Available"
        case .unavailable:
            return "Needs selection again"
        case .unknown:
            return "Saved folder access"
        }
    }
}

private extension FolderAccessGrantAvailability {
    var systemImageName: String {
        switch self {
        case .available:
            return "checkmark.circle.fill"
        case .unavailable:
            return "exclamationmark.triangle.fill"
        case .unknown:
            return "folder.fill"
        }
    }

    var tint: Color {
        switch self {
        case .available:
            return .green
        case .unavailable:
            return .orange
        case .unknown:
            return .secondary
        }
    }
}
