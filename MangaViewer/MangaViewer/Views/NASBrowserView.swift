import SwiftUI

/// NAS (SMB) から作品を持ってくる画面。
/// IP アドレスだけで接続し、共有フォルダーを選んで中を辿る。
struct NASBrowserView: View {
    @ObservedObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    // 入力は画面が持つ。再描画で消えないように View 直下の @State。
    @State private var host = ""
    @State private var username = ""
    @State private var password = ""

    @State private var client: SMBClient?
    @State private var shares: [String] = []
    @State private var currentPath: [String] = []
    @State private var entries: [SMBEntry] = []

    @State private var busy = false
    @State private var status = ""
    @State private var errorMessage: String?
    @State private var doneCount = 0

    var body: some View {
        NavigationStack {
            Group {
                if client == nil {
                    connectForm
                } else if client?.share == nil {
                    shareList
                } else {
                    browser
                }
            }
            .navigationTitle("NAS から入手")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                if client != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            Task { await reset() }
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .accessibilityLabel("接続し直す")
                    }
                }
            }
            .alert("エラー", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .onAppear {
            let saved = SMBServerStore.load()
            host = saved.host
            username = saved.username
        }
        .overlay {
            if busy {
                Color.black.opacity(0.3).ignoresSafeArea()
                VStack(spacing: 10) {
                    ProgressView()
                    Text(status)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    // MARK: - 接続

    private var connectForm: some View {
        Form {
            Section("サーバー") {
                TextField("IP アドレス", text: $host)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("ユーザー名（空ならゲスト）", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("パスワード", text: $password)
            }
            Section {
                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        Spacer()
                        Text("接続")
                        Spacer()
                    }
                }
                .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if doneCount > 0 {
                Section {
                    Text("\(doneCount) 冊を本棚に追加しました")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func connect() async {
        var settings = SMBServerSettings()
        settings.host = host
        settings.username = username
        SMBServerStore.save(settings, password: password)
        busy = true
        status = "接続しています…"
        do {
            let c = try SMBClient(settings: settings, password: password)
            let list = try await c.listShares()
            client = c
            shares = list
            status = ""
        } catch {
            errorMessage = error.localizedDescription
        }
        busy = false
    }

    private func reset() async {
        await client?.disconnect()
        client = nil
        shares = []
        entries = []
        currentPath = []
    }

    // MARK: - 共有の選択

    private var shareList: some View {
        List(shares, id: \.self) { share in
            Button {
                Task { await pick(share) }
            } label: {
                Label(share, systemImage: "folder.badge.gearshape")
            }
        }
        .overlay {
            if shares.isEmpty && !busy {
                ContentUnavailableView("共有フォルダーがありません", systemImage: "externaldrive.badge.questionmark")
            }
        }
    }

    private func pick(_ share: String) async {
        guard let client else { return }
        busy = true
        status = "\(share) を開いています…"
        do {
            try await client.useShare(share)
            currentPath = []
            try await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
        busy = false
    }

    // MARK: - フォルダーの中

    private var browser: some View {
        List {
            if !currentPath.isEmpty {
                Button {
                    Task { await goUp() }
                } label: {
                    Label("ひとつ上へ", systemImage: "arrow.up")
                }
            }
            ForEach(entries) { entry in
                row(entry)
            }
        }
        .navigationTitle(currentPath.last ?? client?.share ?? "NAS")
        .overlay {
            if entries.isEmpty && !busy {
                ContentUnavailableView("空のフォルダー", systemImage: "folder")
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: SMBEntry) -> some View {
        HStack {
            Button {
                if entry.isDirectory {
                    Task { await goInto(entry) }
                } else {
                    Task { await downloadFile(entry) }
                }
            } label: {
                Label(entry.name, systemImage: entry.isDirectory ? "folder" : "doc")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                Task {
                    if entry.isDirectory {
                        await downloadFolder(entry)
                    } else {
                        await downloadFile(entry)
                    }
                }
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.isDirectory ? "フォルダーごとダウンロード" : "ダウンロード")
        }
    }

    private var pathString: String {
        currentPath.joined(separator: "/")
    }

    private func goInto(_ entry: SMBEntry) async {
        currentPath.append(entry.name)
        do { try await reload() } catch { errorMessage = error.localizedDescription }
    }

    private func goUp() async {
        _ = currentPath.popLast()
        do { try await reload() } catch { errorMessage = error.localizedDescription }
    }

    private func reload() async throws {
        guard let client else { return }
        busy = true
        defer { busy = false }
        entries = try await client.list(path: pathString)
    }

    // MARK: - ダウンロード

    private func downloadFile(_ entry: SMBEntry) async {
        guard let client else { return }
        busy = true
        status = "\(entry.name) をダウンロードしています…"
        do {
            _ = try await NASImporter.downloadFile(client: client, entry: entry, library: library)
            doneCount += 1
            status = ""
        } catch {
            errorMessage = error.localizedDescription
        }
        busy = false
    }

    private func downloadFolder(_ entry: SMBEntry) async {
        guard let client else { return }
        busy = true
        do {
            let count = try await NASImporter.downloadFolder(
                client: client,
                entry: entry,
                library: library
            ) { text in
                Task { @MainActor in status = text }
            }
            doneCount += count
            status = ""
        } catch {
            errorMessage = error.localizedDescription
        }
        busy = false
    }
}
