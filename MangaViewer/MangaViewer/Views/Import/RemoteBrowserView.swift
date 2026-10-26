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
    @State private var query = ""
    @State private var showTransfers = false

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
    private var folderSourceKey: String { "folder:\(currentPath)" }
    private var folderBusy: Bool { activity.isActive(sourceKey: folderSourceKey) }

    private var visible: [RemoteEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.name.localizedStandardContains(q) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let listError {
                    ContentUnavailableView(
                        AppCopy.browseFailed,
                        systemImage: "wifi.exclamationmark",
                        description: Text(listError)
                    )
                    .overlay(alignment: .bottom) {
                        Button(AppCopy.retry) { Task { await reload() } }
                            .buttonStyle(.borderedProminent)
                            .padding()
                    }
                } else if loading {
                    ProgressView(AppCopy.loading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if visible.isEmpty {
                    ContentUnavailableView(
                        query.isEmpty ? AppCopy.emptyFolder : AppCopy.browseSearchEmpty,
                        systemImage: query.isEmpty ? "folder" : "magnifyingglass"
                    )
                } else {
                    List {
                        ForEach(visible) { entry in
                            remoteRow(entry)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(
                currentPath.isEmpty
                    ? source.name
                    : (currentPath as NSString).lastPathComponent
            )
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: AppCopy.browseSearchPrompt)
            .toolbar { toolbarContent }
            .overlay(alignment: .top) { ActivityOverlayView() }
            .safeAreaInset(edge: .bottom) {
                DownloadStatusChip { showTransfers = true }
            }
            .sheet(isPresented: $showTransfers) { TransferStatusView() }
            .task(id: currentPath) {
                query = ""
                await reload()
            }
            .onChange(of: currentPath) { _, newPath in persistBrowsePath(newPath) }
            .alert(
                AppCopy.errorTitle,
                isPresented: Binding(
                    get: { errorText != nil },
                    set: { if !$0 { errorText = nil } }
                )
            ) {
                Button(AppCopy.ok, role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if pathStack.count > 1 {
                Button(AppCopy.back) {
                    _ = pathStack.popLast()
                }
            } else {
                Button(AppCopy.close) { dismiss() }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if !currentPath.isEmpty {
                Button(folderBusy ? AppCopy.downloadingFolder : AppCopy.downloadThisFolder) {
                    startFolderImport()
                }
                .disabled(folderBusy)
            }
        }
    }

    @ViewBuilder
    private func remoteRow(_ entry: RemoteEntry) -> some View {
        let busy = activity.isActive(sourceKey: entry.path)
        if entry.isDirectory {
            Button {
                pathStack.append(entry.path)
            } label: {
                HStack {
                    Label(entry.name, systemImage: "folder")
                    Spacer()
                    if busy {
                        ProgressView().controlSize(.small)
                    }
                }
            }
        } else {
            Button {
                startFileImport(entry)
            } label: {
                HStack {
                    Label(entry.name, systemImage: "doc")
                    Spacer()
                    if busy {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(AppCopy.queued)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else if let size = entry.size {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(busy || !ComicFileProbe.isSupportedForImport(entry.name))
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
        guard !activity.isActive(sourceKey: entry.path) else { return }
        let job = activity.begin(
            title: entry.name,
            status: AppCopy.downloadingItem,
            sourceKey: entry.path
        )
        let task = Task { @MainActor in
            do {
                if activity.isCancelled(job) { throw CancellationError() }
                let tmp = try ImportStaging.fileURL(named: entry.name)
                defer { ImportStaging.removeSession(containing: tmp) }
                try await RemoteGateway.download(source: source, entry: entry, to: tmp)
                if activity.isCancelled(job) { throw CancellationError() }
                activity.update(job, status: AppCopy.unpacking)
                let title = UserFacingText.title(fromFileName: entry.name)
                _ = try library.importURL(tmp, folderId: library.currentFolderId, titleOverride: title)
                activity.succeed(job)
            } catch is CancellationError {
                activity.fail(job, message: AppCopy.cancelled)
            } catch {
                activity.fail(job, message: error.localizedDescription)
            }
        }
        activity.attachTask(job, task)
    }

    private func startFolderImport() {
        guard !folderBusy else { return }
        let title = currentPath.isEmpty ? source.name : (currentPath as NSString).lastPathComponent
        let path = currentPath
        let job = activity.begin(
            title: title,
            status: AppCopy.collecting,
            sourceKey: folderSourceKey
        )
        let task = Task { @MainActor in
            do {
                let units = try await RemoteGateway.collectImportUnits(source: source, folderPath: path)
                if activity.isCancelled(job) { throw CancellationError() }
                let folder = library.folderForImport(named: title)
                var i = 0
                for unit in units {
                    i += 1
                    if activity.isCancelled(job) { throw CancellationError() }
                    activity.update(
                        job,
                        status: "\(AppCopy.downloading) \(i)/\(units.count)…",
                        fraction: Double(i - 1) / Double(max(units.count, 1))
                    )
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
                            if activity.isCancelled(job) { throw CancellationError() }
                            let dest = dir.appendingPathComponent(f.name)
                            try await RemoteGateway.download(source: source, entry: f, to: dest)
                        }
                        _ = try library.importURL(
                            dir,
                            folderId: folder.id,
                            titleOverride: UserFacingText.title(fromFileName: folderTitle)
                        )
                        try? FileManager.default.removeItem(at: dir)
                    }
                }
                activity.update(job, status: AppCopy.unpacking, fraction: 1)
                activity.succeed(job)
            } catch is CancellationError {
                activity.fail(job, message: AppCopy.cancelled)
            } catch {
                activity.fail(job, message: error.localizedDescription)
            }
        }
        activity.attachTask(job, task)
    }
}
