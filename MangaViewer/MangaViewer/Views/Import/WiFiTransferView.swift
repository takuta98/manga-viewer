import SwiftUI

struct WiFiTransferView: View {
    @ObservedObject var library: LibraryStore
    @StateObject private var server = WiFiTransferServer.shared
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("サーバを起動", isOn: Binding(
                        get: { server.isRunning },
                        set: { on in
                            if on { server.start() } else { server.stop() }
                        }
                    ))
                    if server.isRunning {
                        Text(server.addressText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Text("同じ Wi-Fi の PC/スマホブラウザで上記 URL を開き、ファイルを Upload してください。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let message {
                    Text(message).foregroundStyle(.secondary)
                }
                if let err = server.lastError {
                    Text(err).foregroundStyle(.red)
                }
            }
            .navigationTitle("Wi-Fi 転送")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        server.stop()
                        dismiss()
                    }
                }
            }
            .onAppear {
                server.onFileReceived = { url in
                    do {
                        try library.importURL(url)
                        message = "取り込みました: \(url.lastPathComponent)"
                    } catch {
                        message = error.localizedDescription
                    }
                }
            }
            .onDisappear { server.stop() }
        }
    }
}
