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

    @State private var busy = false
    @State private var status = ""
    @State private var errorMessage: String?
    @State private var notice = ""
    @State private var showDownloads = false

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
            // Duo ではシステムがツールバーを右側の縦バーに配置する。
            // 項目ごとに分け、アイコン＋タイトルにすると縦バーではアイコンで出る。
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                if client != nil {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            Task { await reset() }
                        } label: {
                            Label("接続し直す", systemImage: "arrow.uturn.backward")
                        }
                        if client?.share != nil {
                            Button {
                                client?.share = nil
                                entries = []
                                currentPath = []
                                query = ""
                            } label: {
                                Label("共有を選び直す", systemImage: "externaldrive")
                            }
                        }
                        Button { showDownloads = true } label: {
                            Label("ダウンロード進捗", systemImage: "arrow.down.circle")
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $showDownloads) {
                DownloadsView(library: library)
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
        .overlay(alignment: .bottom) {
            if !notice.isEmpty {
                Text(notice)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 16)
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
        saved = SMBServerStore.all()
    }

    // MARK: - 共有の選択

    private var shareList: some View {
        List(
            shares.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending },
            id: \.self
        ) { share in
            Button {
                Task { await pick(share) }
            } label: {
                HStack {
                    Label(share, systemImage: "folder.badge.gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("共有フォルダーを選ぶ")
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
            try await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
        busy = false
    }

    // MARK: - フォルダーの中

    /// 今見ている階層だけを名前で絞る（ネットワークに行かないので瞬時）。
    private var shownEntries: [SMBEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return entries }
        return entries.filter {
            $0.name.localizedCaseInsensitiveContains(needle)
        }
    }

    private var browser: some View {
        List {
            if !currentPath.isEmpty && query.isEmpty {
                Button {
                    Task { await goUp() }
                } label: {
                    Label("ひとつ上へ", systemImage: "arrow.up")
                        .foregroundStyle(.tint)
                }
                Button {
                    downloadCurrentFolder()
                } label: {
                    Label("このフォルダーごとダウンロード", systemImage: "square.and.arrow.down.on.square")
                        .foregroundStyle(.tint)
                }
            }
            ForEach(shownEntries) { entry in
                row(entry)
            }
        }
        .navigationTitle(currentPath.last ?? client?.share ?? "SMB")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(currentPath.last ?? client?.share ?? "SMB")
                        .font(.headline)
                    if !pathString.isEmpty {
                        Text("\(client?.share ?? "")/\(pathString)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
            }
        }
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "このフォルダーの中を検索"
        )
        .overlay {
            if entries.isEmpty && query.isEmpty && !busy {
                ContentUnavailableView("空のフォルダー", systemImage: "folder")
            }
            if !query.isEmpty && shownEntries.isEmpty && !busy {
                ContentUnavailableView.search(text: query)
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
                    downloadFile(entry)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label(entry.name, systemImage: icon(for: entry))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if entry.isDirectory {
                        Text("フォルダー")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(ByteCountFormatter.string(
                            fromByteCount: entry.size ?? 0,
                            countStyle: .file
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                if entry.isDirectory {
                    downloadFolder(entry)
                } else {
                    downloadFile(entry)
                }
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.isDirectory ? "フォルダーごとダウンロード" : "ダウンロード")
        }
    }

    /// 拡張子でアイコンを分ける。
    private func icon(for entry: SMBEntry) -> String {
        if entry.isDirectory { return "folder" }
        switch (entry.name as NSString).pathExtension.lowercased() {
        case "cbz", "zip": return "doc.zipper"
        case "png", "jpg", "jpeg", "gif", "webp", "heic": return "photo"
        default: return "doc"
        }
    }

    private var pathString: String {
        currentPath.joined(separator: "/")
    }

    private func goInto(_ entry: SMBEntry) async {
        currentPath.append(entry.name)
        query = ""
        do { try await reload() } catch { errorMessage = error.localizedDescription }
    }

    private func goUp() async {
        _ = currentPath.popLast()
        query = ""
        do { try await reload() } catch { errorMessage = error.localizedDescription }
    }

    private func reload() async throws {
        guard let client else { return }
        busy = true
        defer { busy = false }
        entries = try await client.list(path: pathString)
    }

    // MARK: - ダウンロード（裏で動かす）

    private func downloadFile(_ entry: SMBEntry) {
        guard let client else { return }
        if DownloadManager.shared.startFile(client: client, entry: entry, library: library) {
            notify("ダウンロードを開始しました")
        } else {
            notify("すでにダウンロード中です")
        }
    }

    private func downloadFolder(_ entry: SMBEntry) {
        guard let client else { return }
        if DownloadManager.shared.startFolder(client: client, entry: entry, library: library) {
            notify("ダウンロードを開始しました")
        } else {
            notify("すでにダウンロード中です")
        }
    }

    /// 今開いているフォルダーをまるごと取り込む。
    private func downloadCurrentFolder() {
        guard !currentPath.isEmpty else { return }
        let entry = SMBEntry(
            name: currentPath.last ?? "",
            path: pathString,
            isDirectory: true
        )
        downloadFolder(entry)
    }

    /// 開始の知らせを短く出す。
    private func notify(_ text: String) {
        notice = text
        Task {
            try? await Task.sleep(for: .seconds(2))
            if notice == text { notice = "" }
        }
    }
}

/// ダウンロード進捗の一覧。
struct DownloadsView: View {
    @ObservedObject private var manager = DownloadManager.shared
    @ObservedObject var library: LibraryStore

    var body: some View {
        List(manager.jobs) { job in
            HStack {
                Image(systemName: job.isFolder ? "folder" : "doc.zipper")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.name)
                        .lineLimit(1)
                    if let failed = job.failed {
                        Text(failed)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text(job.status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if job.failed != nil {
                    Button {
                        manager.retry(job, library: library)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("やり直す")
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                } else if job.finished {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ProgressView()
                    Button {
                        manager.cancel(job)
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("中止する")
                }
            }
        }
        .navigationTitle("ダウンロード")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if manager.jobs.contains(where: { !$0.finished && $0.failed == nil }) {
                    Button("すべて中止") {
                        for job in manager.jobs where !job.finished && job.failed == nil {
                            manager.cancel(job)
                        }
                    }
                }
                Button("完了を消す") {
                    manager.clearFinished()
                }
                .disabled(!manager.jobs.contains { $0.finished || $0.failed != nil })
            }
        }
        .overlay {
            if manager.jobs.isEmpty {
                ContentUnavailableView("ダウンロードはありません", systemImage: "arrow.down.circle")
            }
        }
    }
}
