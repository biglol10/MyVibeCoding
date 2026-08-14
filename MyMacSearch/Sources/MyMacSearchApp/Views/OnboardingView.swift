import MyMacSearchAppSupport
import SwiftUI

struct OnboardingView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose folders to index")
                    .font(.title2.weight(.semibold))
                Text("MyMacSearch indexes names, paths, kinds, sizes, and modification dates only. Review the locations before the first scan.")
                    .foregroundStyle(.secondary)
            }

            List {
                ForEach($model.settings.scopes) { $scope in
                    HStack {
                        Toggle("", isOn: $scope.isEnabled)
                            .labelsHidden()
                        Image(systemName: "folder")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(URL(fileURLWithPath: scope.rootPath).lastPathComponent)
                            Text(scope.rootPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            model.removeScope(id: scope.id)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .frame(minHeight: 180)

            HStack {
                Button("Add Folders…") { model.addScopes() }
                    .disabled(model.isResolvingScopes)
                Spacer()
                Toggle("Include hidden files", isOn: $model.settings.includeHidden)
            }

            GroupBox("Excluded by default") {
                Text("/System, /Library, Library/Caches, package contents, .git, .build, node_modules, and DerivedData. Symbolic links and packages are indexed as single entries and are not traversed.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(4)
            }

            Text("External disks and network volumes are never indexed unless you add them and enable the matching option in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let settingsError = model.settingsError {
                Text(settingsError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Full Disk Access Settings…") {
                    model.openFullDiskAccessSettings()
                }
                .buttonStyle(.link)
                Spacer()
                Button("Start Indexing") {
                    model.confirmOnboarding()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    model.isResolvingScopes
                        || !model.settings.scopes.contains(where: \.isEnabled)
                )
            }
        }
        .padding(24)
        .frame(maxWidth: 760, maxHeight: 620)
    }
}
