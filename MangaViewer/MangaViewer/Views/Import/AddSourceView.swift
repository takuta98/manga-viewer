import SwiftUI
import UIKit

struct AddSourceView: View {
    let kind: RemoteSourceKind
    var onSave: (RemoteSource) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var source: RemoteSource
    @State private var testing = false
    @State private var testMessage: String?

    init(kind: RemoteSourceKind, onSave: @escaping (RemoteSource) -> Void) {
        self.kind = kind
        self.onSave = onSave
        _source = State(initialValue: .blank(kind))
    }

    private var canConnect: Bool {
        if kind == .http {
            return !source.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !source.shareOrPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !source.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(AppCopy.displayName, text: $source.name)
                    if kind == .http {
                        TextField(AppCopy.urlField, text: $source.host)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    } else {
                        TextField(AppCopy.hostOrIP, text: $source.host)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                        Stepper(AppCopy.portLabel(source.port), value: $source.port, in: 1...65535)
                    }
                } footer: {
                    Text(AppCopy.addSourceFooter)
                }

                if kind == .smb {
                    Section {
                        TextField(AppCopy.shareFolderOptional, text: $source.shareOrPath)
                    } footer: {
                        Text(AppCopy.smbShareFooter)
                    }
                } else if kind != .http {
                    Section {
                        TextField(AppCopy.pathOrBucket, text: $source.shareOrPath)
                    }
                }

                if kind == .s3 {
                    Section {
                        TextField(AppCopy.region, text: $source.region)
                        TextField(AppCopy.bucket, text: $source.bucket)
                    }
                }

                Section {
                    TextField(AppCopy.username, text: $source.username)
                        .textInputAutocapitalization(.never)
                    SecureField(AppCopy.password, text: $source.password)
                    if kind != .smb && kind != .ftp {
                        Toggle(AppCopy.useTLS, isOn: $source.useTLS)
                    }
                }

                if let testMessage {
                    Section {
                        Text(testMessage)
                            .font(.footnote)
                            .foregroundStyle(testMessage == AppCopy.connectSuccessHint ? .green : .red)
                    }
                }
            }
            .navigationTitle(kind.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppCopy.connect) {
                        if source.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            let host = source.host.trimmingCharacters(in: .whitespacesAndNewlines)
                            source.name = host.isEmpty ? kind.label : host
                        }
                        onSave(source)
                        dismiss()
                    }
                    .disabled(!canConnect)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await runTest() }
                } label: {
                    if testing {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text(AppCopy.testConnection).frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!canConnect || testing)
                .padding()
            }
        }
    }

    private func runTest() async {
        testing = true
        defer { testing = false }
        do {
            _ = try await RemoteGateway.list(source: source, path: "")
            testMessage = AppCopy.connectSuccessHint
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            testMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
