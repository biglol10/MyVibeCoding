import SwiftUI

struct CaptureStudioGuideView: View {
    @Environment(\.openSettings) private var openSettings
    @Binding var dontShowAgain: Bool
    let onClose: () -> Void
    let onStartCapture: () -> Void
    let onStartRecord: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 230), spacing: 12, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "camera.macro")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 4) {
                    Text("CaptureStudio Guide")
                        .font(.title2.weight(.semibold))
                    Text("A quick map of the controls you will use most.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close")
            }

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(CaptureStudioGuidePresentation.sections) { section in
                        guideSection(section)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 320)

            Divider()

            HStack(spacing: 10) {
                Toggle("Don't show this on launch", isOn: $dontShowAgain)
                    .toggleStyle(.checkbox)

                Spacer()

                Button {
                    SettingsTab.selectDefaultOpenTab()
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }

                Button {
                    onStartCapture()
                } label: {
                    Label("Start Capture", systemImage: "viewfinder")
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                Button {
                    onStartRecord()
                } label: {
                    Label("Start Record", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(22)
        .frame(width: 720, height: 560)
    }

    private func guideSection(_ section: CaptureStudioGuidePresentation.Section) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(section.title, systemImage: section.systemImage)
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(section.items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Circle()
                            .fill(.secondary)
                            .frame(width: 4, height: 4)
                        Text(item)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
    }
}
