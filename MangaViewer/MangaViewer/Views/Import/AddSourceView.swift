import SwiftUI

struct AddSourceView: View {
    let kind: RemoteSourceKind
    var onSave: (RemoteSource) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var source: RemoteSource
    @State private var testing = false
    @State private var testMessage: String?
    @State private var testSucceeded = false

    init(kind: RemoteSourceKind, onSave: @escaping (RemoteSource) -> Void) {
        self.kind = kind
        self.onSave = onSave
        _source = State(initialValue: .blank(kind))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("表示名", text: $source.name)
                TextField(hostPlaceholder, text: $source.host)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                if kind != .httpURL {
                    Stepper(value: Binding(
                        get: { source.port ?? RemoteSource.defaultPort(kind) ?? 0 },
                        set: { source.port = $0 }
                    ), in: 1...65535) {
                        Text("ポート: \(source.port ?? 0)")
                    }
                }
                if kind == .smb {
                    TextField("共有名（必須・例: manga）", text: $source.shareOrPath)
                        .textInputAutocapitalization(.never)
                    TextField("ドメイン / ワークグループ（任意）", text: Binding(
                        get: { source.domain ?? "" },
                        set: { source.domain = $0 }
                    ))
                    .textInputAutocapitalization(.never)
                } else if kind == .webdav || kind == .opds || kind == .ftp || kind == .sftp {
                    TextField("パス / フィード", text: $source.shareOrPath)
                        .textInputAutocapitalization(.never)
                } else if kind == .s3 {
                    TextField("Bucket", text: Binding(
                        get: { source.bucket ?? "" },
                        set: { source.bucket = $0 }
                    ))
                    TextField("Region", text: Binding(
                        get: { source.region ?? "us-east-1" },
                        set: { source.region = $0 }
                    ))
                    TextField("プレフィックス", text: $source.shareOrPath)
                }
                TextField("ユーザー名", text: $source.username)
                    .textInputAutocapitalization(.never)
                SecureField("パスワード / シークレット", text: $source.password)
                if kind == .webdav || kind == .opds || kind == .s3 {
                    Toggle("TLS (https)", isOn: $source.useTLS)
                }
                if kind == .smb {
                    Section {
                        Button {
                            Task { await runSMBTest() }
                        } label: {
                            if testing {
                                ProgressView()
                            } else {
                                Text("接続テスト")
                            }
                        }
                        .disabled(testing || source.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if let testMessage {
                            Text(testMessage)
                                .font(.footnote)
                                .foregroundStyle(testSucceeded ? .green : .red)
                        }
                    }
                }
                Section {
                    Text(helpText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(kind.label)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(source)
                        dismiss()
                    }
                    .disabled(source.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func runSMBTest() async {
        testing = true
        testMessage = nil
        testSucceeded = false
        defer { testing = false }
        do {
            try await SMBClientService.testConnection(source: source)
            testSucceeded = true
            testMessage = "接続できました"
        } catch {
            testSucceeded = false
            testMessage = error.localizedDescription
        }
    }

    private var hostPlaceholder: String {
        switch kind {
        case .smb: return "192.168.1.10 または nas.local"
        case .webdav: return "https://nas.example/webdav"
        case .ftp: return "ftp.example.com"
        case .sftp: return "nas.example.com"
        case .opds: return "https://komga.example"
        case .s3: return "https://minio.example:9000"
        default: return "ホスト"
        }
    }

    private var helpText: String {
        switch kind {
        case .smb:
            return "ホストに IP、共有名に NAS の共有フォルダ名を入れます。ホスト欄に smb://192.168.1.10/manga と書いても構いません。初回は「ローカルネットワーク」許可が必要です。参考: Comink / KedaReader / Andrea。"
        case .webdav:
            return "NAS の WebDAV や Nextcloud。Basic 認証対応。"
        case .opds:
            return "Komga / Kavita / Calibre-Web の OPDS フィード URL を指定。"
        case .s3:
            return "AWS S3 互換（MinIO 等）。Access Key = ユーザー名、Secret = パスワード。"
        case .ftp:
            return "PASV FTP。FTPS は未対応。"
        case .sftp:
            return "SSH パスワード認証。鍵認証は今後対応。"
        default:
            return ""
        }
    }
}
