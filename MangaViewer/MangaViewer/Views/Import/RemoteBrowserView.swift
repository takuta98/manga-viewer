import SwiftUI

struct RemoteBrowserView: View {
    @ObservedObject var library: LibraryStore
    let source: RemoteSource
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var activity = TransferActivityCenter.shared
    @State private var pathStack: [String]
    @State private var entries: [RemoteEntry] = []
    @State private var loading = false
    @State private var listError: String?
    @State private var errorText: String?

    init(library: LibraryStore, source: RemoteSource) {
        self.library = library
        self.source = source
        if let last = source.lastBrowsePath, !last.isEmpty {
            _pathStack = State(initialValue: ["", last])
        } else {
            _pathStack = State(initialValue: [""])
        }
    }

    private var currentPath: String { pathStack.last ?? "" }

    var body: some View {
        NavigationStack {
            Group {
                if let listError {
                    ContentUnavailableView("一覧を取得できません", systemImage: "wifi.exclamationmark", description: Text(listError))
                        .overlay(alignment: .bottom) {
                            Button("再試行") { Task { await reload() } }.buttonStyle(.borderedProminent).padding()
                        }
                } else {
                    List {
                        if loading { ProgressView("読み込み中…") }
                        ForEach(entries) { entry in
                            if entry.isDirectory {
                                Button {
                                    pathStack.append(entry.path)
                                } label: {
                                    Label(entry.name, systemImage: "folder")
                                }
                            } else {
                                Button {
                                    startFileImport(entry)
                                } label: {
                                    HStack {
                                        Label(entry.name, systemImage: "doc")
                                        Spacer()
                                        if let size = entry.size {
                                            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .disabled(!ComicFileProbe.isSupportedForImport(entry.name))
                            }
                        }
                    }
                }
            }
            .navigationTitle(currentPath.isEmpty ? source.name : (currentPath as NSString).lastPathComponent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    if pathStack.count > 1 {
                        Button("戻る") { _ = pathStack.popLast(); Task { await reload() } }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !currentPath.isEmpty {
                        Button("このフォルダを取込") { startFolderImport() }
                    }
                }
            }
            .overlay(alignment: .top) { ActivityOverlayView().allowsHitTesting(false) }
            .task(id: currentPath) { await reload() }
            .onChange(of: currentPath) { _, newPath in persistBrowsePath(newPath) }
            .alert("エラー", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) { errorText = nil }
            } message: { Text(errorText ?? "") }
        }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        do {
            entries = try await RemoteGateway.list(source: source, path: currentPath)
            listError = nil
            markLastSuccess()
        } catch {
            listError = error.localizedDescription
            entries = []
        }
    }

    private func markLastSuccess() {
        guard var updated = RemoteSourceStore.shared.sources.first(where: { $0.id == source.id }) else { return }
        updated.lastSuccessAt = Date()
        RemoteSourceStore.shared.update(updated)
    }

    private func persistBrowsePath(_ path: String) {
        guard var updated = RemoteSourceStore.shared.sources.first(where: { $0.id == source.id }) else { return }
        guard updated.lastBrowsePath != path else { return }
        updated.lastBrowsePath = path
        RemoteSourceStore.shared.update(updated)
    }

    private func startFileImport(_ entry: RemoteEntry) {
        let job = activity.begin(title: entry.name, status: "ダウンロード中…")
        let task = Task { @MainActor in
            do {
                let tmp = try ImportStaging.fileURL(named: entry.name)
                defer { ImportStaging.removeSession(containing: tmp) }
                try await RemoteGateway.download(source: source, entry: entry, to: tmp)
                activity.update(job, status: "書庫に展開中…")
                let title = UserFacingText.title(fromFileName: entry.name)
                _ = try library.importURL(tmp, folderId: library.currentFolderId, titleOverride: title)
                activity.succeed(job, banner: "取り込み完了: \(title)")
                dismiss()
            } catch is CancellationError {
                activity.fail(job, message: "キャンセルしました")
            } catch {
                activity.fail(job, message: error.localizedDescription)
            }
        }
        activity.attachTask(job, task)
    }

    private func startFolderImport() {
        let title = currentPath.isEmpty ? source.name : (currentPath as NSString).lastPathComponent
        let job = activity.begin(title: title, status: "フォルダを収集中…")
        let path = currentPath
        let task = Task { @MainActor in
            do {
                let units = try await RemoteGateway.collectImportUnits(source: source, folderPath: path)
                let folder = library.folderForImport(named: title)
                var i = 0
                for unit in units {
                    i += 1
                    activity.update(job, status: "取込中 \(i)/\(units.count)…", fraction: Double(i - 1) / Double(max(units.count, 1)))
                    switch unit {
                    case .archive(let entry):
                        let tmp = try ImportStaging.fileURL(named: entry.name)
                        defer { ImportStaging.removeSession(containing: tmp) }
                        try await RemoteGateway.download(source: source, entry: entry, to: tmp)
                        let t = UserFacingText.title(fromFileName: entry.name)
                        _ = try library.importURL(tmp, folderId: folder.id, titleOverride: t)
                    case .imageFolder(_, let folderTitle, let files):
                        let dir = try ImportStaging.fileURL(named: folderTitle).deletingLastPathComponent()
                            .appendingPathComponent(folderTitle, isDirectory: true)
                        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                        for f in files {
                            let dest = dir.appendingPathComponent(f.name)
                            try await RemoteGateway.download(source: source, entry: f, to: dest)
                        }
                        _ = try library.importURL(dir, folderId: folder.id, titleOverride: UserFacingText.title(fromFileName: folderTitle))
                        try? FileManager.default.removeItem(at: dir)
                    }
                }
                activity.succeed(job, banner: "フォルダ取り込み完了: \(title)")
                dismiss()
            } catch is CancellationError {
                activity.fail(job, message: "キャンセルしました")
            } catch {
                activity.fail(job, message: error.localizedDescription)
            }
        }
        activity.attachTask(job, task)
    }
}
