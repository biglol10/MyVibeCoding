import MyMacSearchAppSupport
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Indexing Locations") {
                List {
                    ForEach($model.settings.scopes) { $scope in
                        HStack {
                            Toggle("", isOn: $scope.isEnabled)
                                .labelsHidden()
                            Text(scope.rootPath)
                                .lineLimit(1)
                                .truncationMode(.middle)
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
                .frame(height: 170)

                Button("Add Folders…") { model.addScopes() }
            }

            Section("Policy") {
                Toggle("Include hidden files", isOn: $model.settings.includeHidden)
                Toggle(
                    "Allow explicitly added external volumes",
                    isOn: $model.settings.externalVolumesEnabled
                )
                Toggle(
                    "Allow explicitly added network volumes",
                    isOn: $model.settings.networkVolumesEnabled
                )
            }

            Section("Permissions") {
                Text("Full Disk Access is only needed for folders macOS otherwise prevents this app from reading. MyMacSearch continues safely past inaccessible descendants.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Full Disk Access Settings…") {
                    model.openFullDiskAccessSettings()
                }
            }

            if let settingsError = model.settingsError {
                Text(settingsError)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Apply and Reindex") { model.applySettings() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }
}
