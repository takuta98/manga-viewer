import SwiftUI

struct AddSourceView: View {
    let kind: RemoteSourceKind
    var onSave: (RemoteSource) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var source: RemoteSource
    @State private var testing = false
    @State private var testMessage: String?
    @State private var testSucceeded = false
    private let isEditing: Bool

    init(kind: RemoteSourceKind, onSave: @escaping (RemoteSource) -> Void) {
        self.kind = kind
        self.onSave = onSave
        self.isEditing = false
        _source = State(initialValue: .blank(kind))
    }

    init(source: RemoteSource, onSave: @escaping (RemoteSource) -> Void) {
        self.kind = source.kind
        self.onSave = onSave
        self.isEditing = true
        _source = State(initialValue: source)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("表示名", text: $source.name)
                TextField(hostPlaceholder, text: $source.host)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                if kind != .httpURL && kind != .smb {
                    Stepper(value: Binding(
                        get: { source.port ?? RemoteSource.defaultPort(kind) ?? 0 },
                        set: { source.port = $0 }
                    ), in: 1...65535) {
                        Text("ポート: \(source.port ?? 0)")
                    }
                }
                if kind == .webdav || kind == .opds || kind == .ftp || kind == .sftp {
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
            .navigationTitle(isEditing ? "接続を編集" : kind.label)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if kind == .smb {
                            source.port = source.port ?? 445
                        }
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
            var probe = source
            probe.shareOrPath = ""
            probe.port = probe.port ?? 445
            try await SMBClientService.testConnection(source: probe)
            testSucceeded = true
            testMessage = "接続できました。保存したあと、フォルダを選べます。"
        } catch {
            testSucceeded = false
            testMessage = error.localizedDescription
        }
    }

    private var hostPlaceholder: String {
        switch kind {
        case .smb: return "IPアドレス（例: 192.168.1.10）"
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
            return "IP・ユーザー名・パスワードを入れて保存してください。フォルダは接続したあと一覧から選びます。初回は「ローカルネットワーク」の許可が必要です。"
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
