import SwiftUI

/// NAS (SMB) のフォルダーを辿ってファイル・フォルダーを取り込む画面。
struct NASBrowserView: View {
    @ObservedObject var library: LibraryStore

    @Environment(\.dismiss) private var dismiss

    @State private var settings = SMBServerStore.load()
    @State private var path: [String] = []
    @State private var entries: [SMBEntry] = []
    @State private var client: SMBClient?
    @State private var loading = false
    @State private var working = false
    @State private var statusText: String?
    @State private var errorText: String?
    @State private var editingServer = false

    private var settingsReady: Bool { !settings.host.isEmpty }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !settingsReady {
                    serverForm
                } else {
                    browserList(path: "")
                }
            }
            .navigationTitle("NAS から入手")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                if settingsReady {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { editingServer = true } label: {
                            Image(systemName: "server.rack")
                        }
                        .accessibilityLabel("サーバー設定")
                    }
                }
            }
            .navigationDestination(for: String.self) { dir in
                browserList(path: dir)
                    .navigationTitle(dir.split(separator: "/").last.map(String.init) ?? dir)
            }
        }
        .sheet(isPresented: $editingServer) {
            NavigationStack { serverForm }
        }
        .onAppear {
            if settingsReady { Task { await open(path: "") } }
        }
    }

    // MARK: - ブラウザ

    @ViewBuilder
    private func browserList(path dir: String) -> some View {
        List {
            if let statusText {
                HStack(spacing: 8) {
                    if working { ProgressView() }
                    Text(statusText).font(.footnote)
                }
                .foregroundStyle(.secondary)
            }
            ForEach(entries.filter { $0.isDirectory || isImportable($0) }) { entry in
                if entry.isDirectory {
                    NavigationLink(value: entry.path) {
                        Label(entry.name, systemImage: "folder")
                    }
                } else {
                    HStack {
                        Label(entry.name, systemImage: icon(for: entry))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Button("ダウンロード") { downloadFile(entry) }
                            .buttonStyle(.bordered)
                            .disabled(working)
                    }
                }
            }
            if !loading && entries.isEmpty && errorText == nil {
                Text("ファイルがありません").foregroundStyle(.secondary)
            }
        }
        .overlay {
            if loading { ProgressView("読み込み中…") }
        }
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    downloadFolder(dir)
                } label: {
                    Label("このフォルダーをダウンロード", systemImage: "arrow.down.doc")
                }
                .disabled(working || loading)
            }
        }
        .alert("エラー", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("閉じる", role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
        .onAppear { Task { await open(path: dir) } }
    }

    private var currentDir: String { path.last ?? "" }

    // MARK: - サーバー設定

    private var serverForm: some View {
        @State var form = settings
        @State var formPassword = ""
        return Form {
            Section("サーバー") {
                TextField("ホスト（例: 192.168.1.10）", text: $form.host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("共有名（例: manga）", text: $form.share)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section("アカウント") {
                TextField("ユーザー", text: $form.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("パスワード", text: $formPassword)
            }
            Section {
                Button("保存して接続") {
                    saveServer(form, password: formPassword)
                }
                .disabled(form.host.isEmpty || form.share.isEmpty)
            }
        }
        .navigationTitle("NAS サーバー")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if settingsReady {
                    Button("閉じる") { editingServer = false }
                }
            }
        }
        .onAppear { formPassword = SMBServerStore.loadPassword() }
    }

    // MARK: - 動作

    private func saveServer(_ form: SMBServerSettings, password: String) {
        settings = form
        SMBServerStore.save(form, password: password)
        client = nil
        editingServer = false
        Task { await open(path: currentDir) }
    }

    private func makeClient() throws -> SMBClient {
        if let client { return client }
        let c = try SMBClient(settings: settings, password: SMBServerStore.loadPassword())
        client = c
        return c
    }

    private func open(path dir: String) async {
        loading = true
        errorText = nil
        do {
            entries = try await makeClient().list(path: dir)
        } catch {
            entries = []
            errorText = error.localizedDescription
        }
        loading = false
    }

    private func downloadFile(_ entry: SMBEntry) {
        working = true
        statusText = "\(entry.name) をダウンロード中…"
        Task {
            do {
                _ = try await NASImporter.downloadFile(client: makeClient(), entry: entry, library: library)
                statusText = "\(entry.name) を取り込みました"
            } catch {
                statusText = nil
                errorText = error.localizedDescription
            }
            working = false
        }
    }

    private func downloadFolder(_ dir: String) {
        let folder = SMBEntry(name: dir.split(separator: "/").last.map(String.init) ?? settings.share,
                              path: dir,
                              isDirectory: true,
                              size: nil)
        working = true
        Task {
            do {
                let count = try await NASImporter.downloadFolder(
                    client: makeClient(),
                    entry: folder,
                    library: library
                ) { text in
                    Task { @MainActor in statusText = text }
                }
                statusText = "\(count) 巻を取り込みました"
            } catch {
                statusText = nil
                errorText = error.localizedDescription
            }
            working = false
        }
    }

    private func isImportable(_ entry: SMBEntry) -> Bool {
        let ext = (entry.name as NSString).pathExtension.lowercased()
        return ZipExtractor.imageExtensions.contains(ext) || NASImporter.archiveExtensions.contains(ext)
    }

    private func icon(for entry: SMBEntry) -> String {
        let ext = (entry.name as NSString).pathExtension.lowercased()
        if NASImporter.archiveExtensions.contains(ext) { return "books.vertical" }
        return "photo"
    }
}
