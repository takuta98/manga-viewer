import SwiftUI

struct WiFiTransferView: View {
    @ObservedObject var library: LibraryStore
    @StateObject private var server = WiFiTransferServer()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(AppCopy.wifiInstruction)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(server.addressText)
                    .font(.title3.monospaced()).textSelection(.enabled)
                Spacer()
            }
            .padding()
            .navigationTitle(AppCopy.wifiTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.close) { dismiss() }
                }
            }
            .onAppear { server.start() }
            .onDisappear { server.stop() }
        }
    }
}
