import SwiftUI

/// SMB サーバーから作品を持ってくる画面。
/// IP アドレスだけで接続し、共有フォルダーを選んで中を辿る。
/// 一度接続したサーバーは保存され、次はタップだけで繋がる。
struct NASBrowserView: View {
    @ObservedObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    // 入力は画面が持つ。再描画で消えないように View 直下の @State。
    @State private var host = ""
    @State private var username = ""
    @State private var password = ""
    @State private var saved: [SMBServerSettings] = []

    @State private var client: SMBClient?
    @State private var shares: [String] = []
    @State private var currentPath: [String] = []
    @State private var entries: [SMBEntry] = []
    @State private var query = ""
    @State private var searchResults: [SMBEntry]?
    @State private var searching = false

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
            .navigationTitle("SMB")
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
            saved = SMBServerStore.all()
            if let last = saved.first {
                host = last.host
                username = last.username
            }
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
            if !saved.isEmpty {
                Section("保存したサーバー") {
                    ForEach(saved) { server in
                        Button {
                            Task { await connect(server) }
                        } label: {
                            Label(server.label, systemImage: "server.rack")
                        }
                        .swipeActions {
                            Button("削除", role: .destructive) {
                                SMBServerStore.remove(server)
                                saved = SMBServerStore.all()
                            }
                        }
                    }
                }
            }
            Section("新しく接続") {
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
                    var settings = SMBServerSettings()
                    settings.host = host
                    settings.username = username
                    Task { await connect(settings, password: password, remember: true) }
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

    /// 保存済みならタップだけで接続。手入力は remember で保存する。
    private func connect(
        _ settings: SMBServerSettings,
        password: String? = nil,
        remember: Bool = false
    ) async {
        let pw = password ?? SMBServerStore.password(for: settings)
        if remember {
            SMBServerStore.save(settings, password: pw)
            saved = SMBServerStore.all()
        }
        busy = true
        status = "接続しています…"
        do {
            let c = try SMBClient(settings: settings, password: pw)
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
        query = ""
        searchResults = nil
        saved = SMBServerStore.all()
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
            query = ""
            searchResults = nil
            try await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
        busy = false
    }

    // MARK: - フォルダーの中

    private var browser: some View {
        List {
            if query.isEmpty {
                if !currentPath.isEmpty {
                    Button {
                        Task { await goUp() }
                    } label: {
                        Label("ひとつ上へ", systemImage: "arrow.up")
                    }
                    Button {
                        Task { await downloadCurrentFolder() }
                    } label: {
                        Label("このフォルダーごとダウンロード", systemImage: "square.and.arrow.down.on.square")
                    }
                }
                ForEach(entries) { entry in
                    row(entry)
                }
            } else {
                ForEach(searchResults ?? []) { entry in
                    searchRow(entry)
                }
            }
        }
        .navigationTitle(currentPath.last ?? client?.share ?? "SMB")
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "共有の中を検索"
        )
        .task(id: query) {
            await search(query)
        }
        .overlay {
            if entries.isEmpty && query.isEmpty && !busy {
                ContentUnavailableView("空のフォルダー", systemImage: "folder")
            }
            if !query.isEmpty && !busy {
                if searching {
                    ProgressView("探しています…")
                } else if (searchResults ?? []).isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }

    /// 共有全体を再帰で探す。入力が止まってから走査し、結果が出るまで「探しています」を出す。
    private func search(_ text: String) async {
        guard let client else { return }
        let needle = text.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else {
            searchResults = nil
            searching = false
            return
        }
        searching = true
        defer { searching = false }
        // 打つたびに全走査しないよう少し待つ
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        do {
            let all = try await client.filesRecursively(path: "")
            guard !Task.isCancelled else { return }
            searchResults = all.filter {
                $0.name.localizedCaseInsensitiveContains(needle)
            }
        } catch {
            if !Task.isCancelled {
                searchResults = []
                errorMessage = error.localizedDescription
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

    @ViewBuilder
    private func searchRow(_ entry: SMBEntry) -> some View {
        HStack {
            Label {
                VStack(alignment: .leading) {
                    Text(entry.name)
                    Text(entry.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } icon: {
                Image(systemName: "doc")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await downloadFile(entry) }
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ダウンロード")
        }
    }

    private var pathString: String {
        currentPath.joined(separator: "/")
    }

    private func goInto(_ entry: SMBEntry) async {
        currentPath.append(entry.name)
        query = ""
        searchResults = nil
        do { try await reload() } catch { errorMessage = error.localizedDescription }
    }

    private func goUp() async {
        _ = currentPath.popLast()
        query = ""
        searchResults = nil
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

    /// 今開いているフォルダーをまるごと取り込む。
    private func downloadCurrentFolder() async {
        guard !currentPath.isEmpty else { return }
        let entry = SMBEntry(
            name: currentPath.last ?? "",
            path: pathString,
            isDirectory: true
        )
        await downloadFolder(entry)
    }
}
