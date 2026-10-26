import SwiftUI

struct RemoteBrowserView: View {
    @ObservedObject var library: LibraryStore
    let source: RemoteSource

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var activity = TransferActivityCenter.shared
    @State private var pathStack: [String]
    @State private var entries: [RemoteEntry] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var busy = false
    @State private var activeJobID: UUID?
    @State private var pendingFolderImport: PendingFolderImport?
    @State private var importTask: Task<Void, Never>?

    private struct PendingFolderImport: Identifiable {
        let id = UUID()
        let path: String
        let title: String
        let unitCount: Int
    }

    init(library: LibraryStore, source: RemoteSource) {
        self.library = library
        self.source = source
        if source.kind == .smb {
            if let endpoint = try? SMBClientService.Endpoint.resolve(source), !endpoint.share.isEmpty {
                _pathStack = State(initialValue: [endpoint.pathInsideShare])
            } else {
                _pathStack = State(initialValue: [""])
            }
        } else {
            _pathStack = State(initialValue: [""])
        }
    }

    private var currentPath: String { pathStack.last ?? "" }

    private var showingSharePicker: Bool {
        source.kind == .smb
            && (try? SMBClientService.Endpoint.resolve(source))?.share.isEmpty == true
            && pathStack.count == 1
            && currentPath.isEmpty
    }

    private var canImportFolder: Bool {
        !showingSharePicker && !busy && !loading
    }

    var body: some View {
        NavigationStack {
            List {
                if loading {
                    HStack {
                        ProgressView()
                        Text("読み込み中…")
                            .foregroundStyle(.secondary)
                    }
                }
                if showingSharePicker && !entries.isEmpty {
                    Text("フォルダを選んでください")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if canImportFolder && !showingSharePicker {
                    Section {
                        Button {
                            Task { await prepareFolderImport(path: currentPath, title: folderTitle) }
                        } label: {
                            Label("このフォルダを書庫に取り込む", systemImage: "square.and.arrow.down.on.square")
                        }
                        .disabled(busy)
                    } footer: {
                        Text("アプリ内に同名フォルダを作り、中身をその中へ入れます。画像フォルダは1冊にまとめます。")
                    }
                }
                ForEach(entries) { entry in
                    if entry.isDirectory {
                        Button {
                            pathStack.append(entry.path)
                        } label: {
                            Label(entry.name, systemImage: "folder.fill")
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                Task { await prepareFolderImport(path: entry.path, title: entry.name) }
                            } label: {
                                Label("取込", systemImage: "square.and.arrow.down")
                            }
                            .tint(.blue)
                            .disabled(busy)
                        }
                        .contextMenu {
                            Button {
                                Task { await prepareFolderImport(path: entry.path, title: entry.name) }
                            } label: {
                                Label("フォルダを書庫に取り込む", systemImage: "square.and.arrow.down.on.square")
                            }
                            .disabled(busy)
                        }
                    } else {
                        Button {
                            Task { await importFile(entry) }
                        } label: {
                            HStack {
                                Label(entry.name, systemImage: "doc")
                                Spacer()
                                if ComicFileProbe.isSupportedForImport(entry.name) {
                                    Text("取込")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("非対応")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .disabled(!ComicFileProbe.isSupportedForImport(entry.name) || busy)
                    }
                }
            }
            .navigationTitle(showingSharePicker ? "フォルダ選択" : source.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .disabled(busy)
                }
                ToolbarItem(placement: .topBarLeading) {
                    if pathStack.count > 1 {
                        Button("戻る") {
                            _ = pathStack.popLast()
                            Task { await reload() }
                        }
                        .disabled(busy)
                    }
                }
                if busy, let jobID = activeJobID {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("中止", role: .destructive) {
                            activity.cancel(jobID)
                        }
                    }
                }
            }
            .overlay(alignment: .top) {
                ActivityOverlayView()
                    .allowsHitTesting(false)
            }
            .overlay {
                if busy {
                    ZStack {
                        Color.black.opacity(0.2).ignoresSafeArea()
                    }
                    .allowsHitTesting(false)
                }
            }
            .task(id: currentPath) { await reload() }
            .alert("エラー", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("OK", role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
            .confirmationDialog(
                "フォルダを取り込む",
                isPresented: Binding(
                    get: { pendingFolderImport != nil },
                    set: { if !$0 { pendingFolderImport = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let pending = pendingFolderImport {
                    Button("取り込む（\(pending.unitCount) 冊）") {
                        let path = pending.path
                        let title = pending.title
                        pendingFolderImport = nil
                        importTask = Task { await runFolderImport(path: path, title: title) }
                    }
                }
                Button("キャンセル", role: .cancel) {
                    pendingFolderImport = nil
                }
            } message: {
                if let pending = pendingFolderImport {
                    Text("書庫に「\(pending.title)」フォルダを作り、\(pending.unitCount) 冊を入れます。")
                }
            }
        }
    }

    private var folderTitle: String {
        if currentPath.isEmpty { return source.name }
        return (currentPath as NSString).lastPathComponent
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        do {
            entries = try await RemoteGateway.list(source: source, path: currentPath)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
            entries = []
        }
    }

    private func importFile(_ entry: RemoteEntry) async {
        busy = true
        defer { busy = false }
        let job = activity.begin(title: entry.name, status: "ダウンロード中…")
        activeJobID = job
        defer { activeJobID = nil }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + entry.name)
        defer { try? FileManager.default.removeItem(at: tmp) }
        do {
            try Task.checkCancellation()
            try await RemoteGateway.download(source: source, entry: entry, to: tmp)
            if activity.isCancelled(job) { throw CancellationError() }
            activity.update(job, status: "書庫に展開中…")
            _ = try library.importURL(tmp, folderId: library.currentFolderId)
            activity.succeed(job, banner: "取り込み完了: \(entry.name)")
            errorText = nil
        } catch is CancellationError {
            activity.fail(job, message: "キャンセルしました")
        } catch {
            activity.fail(job, message: error.localizedDescription)
            errorText = error.localizedDescription
        }
    }

    private func prepareFolderImport(path: String, title: String) async {
        busy = true
        defer { busy = false }
        let job = activity.begin(title: title, status: "内容を調べています…")
        activeJobID = job
        defer { activeJobID = nil }
        do {
            let units = try await RemoteGateway.collectImportUnits(source: source, path: path)
            activity.succeed(job, banner: "\(units.count) 冊分見つかりました")
            guard !units.isEmpty else {
                errorText = "このフォルダに取込可能なファイル（cbz / zip / pdf / 画像）がありません"
                return
            }
            pendingFolderImport = PendingFolderImport(path: path, title: title, unitCount: units.count)
        } catch {
            activity.fail(job, message: error.localizedDescription)
            errorText = error.localizedDescription
        }
    }

    private func runFolderImport(path: String, title: String) async {
        busy = true
        defer { busy = false }
        let job = activity.begin(title: title, status: "準備中…")
        activeJobID = job
        defer { activeJobID = nil }

        let libraryFolder = library.folderForImport(named: title)
        library.currentFolderId = libraryFolder.id

        do {
            let units = try await RemoteGateway.collectImportUnits(source: source, path: path)
            guard !units.isEmpty else {
                activity.fail(job, message: "取込できるファイルがありません")
                return
            }
            var ok = 0
            var failures: [String] = []
            for (i, unit) in units.enumerated() {
                if activity.isCancelled(job) { throw CancellationError() }
                let base = Double(i) / Double(units.count)
                do {
                    switch unit {
                    case .archive(let entry):
                        activity.update(job, status: "ダウンロード \(i + 1)/\(units.count): \(entry.name)", fraction: base)
                        let tmp = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString + "-" + entry.name)
                        defer { try? FileManager.default.removeItem(at: tmp) }
                        try await RemoteGateway.download(source: source, entry: entry, to: tmp)
                        if activity.isCancelled(job) { throw CancellationError() }
                        activity.update(job, status: "展開 \(i + 1)/\(units.count): \(entry.name)", fraction: base + 0.4 / Double(units.count))
                        _ = try library.importURL(tmp, folderId: libraryFolder.id)
                    case .imageFolder(let folderTitle, let images):
                        activity.update(job, status: "画像フォルダ \(i + 1)/\(units.count): \(folderTitle)", fraction: base)
                        let dir = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString + "-" + folderTitle, isDirectory: true)
                        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                        defer { try? FileManager.default.removeItem(at: dir) }
                        for (j, entry) in images.enumerated() {
                            if activity.isCancelled(job) { throw CancellationError() }
                            let dest = dir.appendingPathComponent(entry.name)
                            activity.update(
                                job,
                                status: "\(folderTitle): \(j + 1)/\(images.count)",
                                fraction: base + Double(j) / Double(max(images.count, 1)) / Double(units.count)
                            )
                            try await RemoteGateway.download(source: source, entry: entry, to: dest)
                        }
                        _ = try library.importURL(dir, folderId: libraryFolder.id, titleOverride: folderTitle)
                    }
                    ok += 1
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failures.append("\(unit.displayName): \(error.localizedDescription)")
                }
            }
            if failures.isEmpty {
                activity.succeed(job, banner: "「\(libraryFolder.name)」に \(ok) 冊を取り込みました")
            } else {
                activity.fail(
                    job,
                    message: "成功 \(ok)/\(units.count)。失敗: \(failures.prefix(2).joined(separator: " / "))"
                )
            }
            errorText = nil
            dismiss()
        } catch is CancellationError {
            activity.fail(job, message: "キャンセルしました（途中までの取込は残ります）")
        } catch {
            activity.fail(job, message: error.localizedDescription)
            errorText = error.localizedDescription
        }
    }
}
