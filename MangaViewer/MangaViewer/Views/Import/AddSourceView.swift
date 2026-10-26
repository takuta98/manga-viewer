import SwiftUI

struct AddSourceView: View {
    let kind: RemoteSourceKind
    var onSave: (RemoteSource) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var source: RemoteSource

    init(kind: RemoteSourceKind, onSave: @escaping (RemoteSource) -> Void) {
        self.kind = kind
        self.onSave = onSave
        _source = State(initialValue: .blank(kind))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("表示名", text: $source.name)
                TextField("ホスト / IP", text: $source.host)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                Stepper("ポート: \(source.port)", value: $source.port, in: 1...65535)
                if kind == .smb {
                    TextField("共有フォルダ名（任意・後から選べます）", text: $source.shareOrPath)
                    Text("まず IP とアカウントで接続できます。共有名が分かる場合だけ入力してください。")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if kind != .http {
                    TextField("パス / バケット", text: $source.shareOrPath)
                }
                if kind == .s3 {
                    TextField("リージョン", text: $source.region)
                    TextField("バケット", text: $source.bucket)
                }
                TextField("ユーザー名", text: $source.username)
                    .textInputAutocapitalization(.never)
                SecureField("パスワード", text: $source.password)
                if kind != .smb && kind != .ftp {
                    Toggle("TLS を使う", isOn: $source.useTLS)
                }
            }
            .navigationTitle(kind.label)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(source)
                        dismiss()
                    }
                    .disabled(source.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && kind != .http)
                }
            }
        }
    }
}
