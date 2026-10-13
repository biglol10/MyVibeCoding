import AppKit
import SwiftUI

struct ServerConnectionView: View {
    @EnvironmentObject private var store: ExplorerStore
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect to SMB Server").font(.title2)
            TextField("smb://server/share", text: $address).textFieldStyle(.roundedBorder)
            Text("macOS manages login and mounts the share. Mounted shares appear under Locations. Passwords are never stored by MyMacFinder.")
                .foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Refresh Drives") { Task { await store.refreshMountedVolumes() } }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Connect") {
                    do {
                        let url = try SMBServerAddress.parse(address)
                        guard NSWorkspace.shared.open(url) else { throw ExplorerError.operationFailed("macOS could not open the server address.") }
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).frame(width: 470)
    }
}
