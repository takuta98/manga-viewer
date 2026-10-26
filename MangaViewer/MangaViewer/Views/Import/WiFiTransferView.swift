import SwiftUI

struct WiFiTransferView: View {
    @ObservedObject var library: LibraryStore
    @StateObject private var server = WiFiTransferServer()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("同じ Wi‑Fi の別端末のブラウザで次のアドレスを開いてください。")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(server.addressText)
                    .font(.title3.monospaced()).textSelection(.enabled)
                Text("外部ライブラリは使わず、このアプリ内の簡易HTTPサーバで受信します。")
                    .font(.footnote).foregroundStyle(.tertiary)
                Spacer()
            }
            .padding()
            .navigationTitle("Wi‑Fi 転送")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
            .onAppear { server.start() }
            .onDisappear { server.stop() }
        }
    }
}
