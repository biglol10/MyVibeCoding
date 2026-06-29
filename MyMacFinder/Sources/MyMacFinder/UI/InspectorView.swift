import SwiftUI

struct InspectorView: View {
    let selection: [FileEntry]
    let calculatedFolderSizes: [URL: Int64]
    let onCommand: (ExplorerCommand) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if selection.isEmpty {
                    noSelectionView
                } else if selection.count == 1, let entry = selection.first {
                    singleSelectionView(entry)
                } else {
                    multiSelectionView
                }

                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .background(.bar)
    }

    private var noSelectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No Selection")
                .font(.headline)
            Text("Select a file or folder to view details.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func singleSelectionView(_ entry: FileEntry) -> some View {
        let details = InspectorItemDetails(
            entry: entry,
            calculatedFolderSize: calculatedFolderSizes[entry.url.standardizedFileURL]
        )

        return VStack(alignment: .leading, spacing: 14) {
            FilePreviewView(entry: entry)

            Text(details.name)
                .font(.headline)
                .lineLimit(3)
                .textSelection(.enabled)

            actionRow(for: entry)

            detailsGrid(details)
        }
    }

    private func actionRow(for entry: FileEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                inspectorButton("Open", systemImage: "arrow.up.forward.square", command: .open)
                inspectorButton("Quick Look", systemImage: "eye", command: .quickLook)
            }
            HStack(spacing: 8) {
                inspectorButton("Reveal", systemImage: "finder", command: .revealInFinder)
                inspectorButton("Copy Path", systemImage: "doc.on.doc", command: .copyPath)
            }
            if !entry.isArchiveBacked {
                inspectorButton("Edit Tags", systemImage: "tag", command: .editTags)
            }
            if entry.isDirectoryLike {
                inspectorButton("Calculate Size", systemImage: "sum", command: .calculateFolderSize)
            }
        }
    }

    private func inspectorButton(_ title: String, systemImage: String, command: ExplorerCommand) -> some View {
        Button {
            onCommand(command)
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func detailsGrid(_ details: InspectorItemDetails) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            detailRow("Kind", details.kind)
            detailRow("Extension", details.fileExtension)
            detailRow("Size", details.sizeText)
            detailRow("Created", details.dateCreatedText)
            detailRow("Modified", details.dateModifiedText)
            detailRow("Accessed", details.dateAccessedText)
            detailRow("Hidden", details.isHiddenText)
            detailRow("Readable", details.isReadableText)
            detailRow("Tags", details.finderTagsText)
            detailRow("Path", details.path, lineLimit: 4)
        }
        .font(.caption)
    }

    private func detailRow(_ label: String, _ value: String, lineLimit: Int = 2) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(lineLimit)
                .textSelection(.enabled)
        }
    }

    private var multiSelectionView: some View {
        let summary = InspectorSelectionSummary(entries: selection)

        return VStack(alignment: .leading, spacing: 12) {
            Text("\(summary.itemCount) Items Selected")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                detailRow("Files", "\(summary.fileCount)")
                detailRow("Folders", "\(summary.folderCount)")
                detailRow("Known Size", summary.knownTotalSizeText)
                if let commonParentPath = summary.commonParentPath {
                    detailRow("Parent", commonParentPath, lineLimit: 3)
                }
            }
            .font(.caption)

            Divider()

            ForEach(summary.previewNames, id: \.self) { name in
                Text(name)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
    }
}
