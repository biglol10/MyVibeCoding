import AppKit
import SwiftUI

struct ServerConnectionView: View {
    @EnvironmentObject private var store: ExplorerStore
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("Connect to SMB Server")).font(.title2)
            TextField(L10n.text("smb://server/share"), text: $address).textFieldStyle(.roundedBorder)
            Text(L10n.text(store.sandboxPolicy.isSandboxed
                ? "macOS manages login and mounts the share. Then choose the mounted folder to give PaneHarbor access. Passwords are never stored by PaneHarbor."
                : "macOS manages login and mounts the share. Mounted shares appear under Locations. Passwords are never stored by this app."))
                .foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button(L10n.text("Refresh Drives")) { Task { await store.refreshMountedVolumes() } }
                Spacer()
                Button(L10n.text("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.text("Connect")) {
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
