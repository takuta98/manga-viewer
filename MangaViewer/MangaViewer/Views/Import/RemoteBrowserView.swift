import SwiftUI

struct RemoteBrowserView: View {
    @ObservedObject var library: LibraryStore
    let source: RemoteSource

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var activity = TransferActivityCenter.shared
    @State private var pathStack: [String]
    @State private var entries: [RemoteEntry] = []
    @State private var loading = false
    /// 一覧取得失敗。alert だけでなくインライン再試行を出す。
    @State private var listError: String?
    /// 取込準備など一覧以外のエラー（alert）。
    @State private var errorText: String?
    @State private var probing = false
    @State private var pendingFolderImport: PendingFolderImport?

    private struct PendingFolderImport: Identifiable {
        let id = UUID()
        let path: String
        let title: String
        let unitCount: Int
    }

    init(library: LibraryStore, source: RemoteSource) {
        self.library = library
        self.source = source
        _pathStack = State(initialValue: Self.initialPathStack(for: source))
    }

    /// 前回の閲覧パスがあればそこから。なければ SMB の共有内ルート or 空。
    private static func initialPathStack(for source: RemoteSource) -> [String] {
        if let last = source.lastBrowsePath {
            return pathStack(to: last, source: source)
        }
        if source.kind == .smb,
           let endpoint = try? SMBClientService.Endpoint.resolve(source),
           !endpoint.share.isEmpty {
            return [endpoint.pathInsideShare]
        }
        return [""]
    }

    /// 戻る操作が効くよう、ルートから `path` までのスタックを組み立てる。
    private static func pathStack(to path: String, source: RemoteSource) -> [String] {
        let root: String
        if source.kind == .smb,
           let endpoint = try? SMBClientService.Endpoint.resolve(source),
           !endpoint.share.isEmpty {
            root = endpoint.pathInsideShare
        } else {
            root = ""
        }

        // 空パスはルート扱い（SMB で共有固定時は pathInsideShare）
        if path.isEmpty || path == root {
            return [root]
        }

        var stack = [root]
        let relative: String
        if !root.isEmpty, path.hasPrefix(root + "/") {
            relative = String(path.dropFirst(root.count + 1))
        } else if root.isEmpty {
            relative = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            // ルートと食い違う保存パスはそのまま開く
            return [root, path]
        }
        guard !relative.isEmpty else { return stack }

        var acc = root
        for part in relative.split(separator: "/") {
            acc = acc.isEmpty ? String(part) : "\(acc)/\(part)"
            stack.append(acc)
        }
        return stack
    }

    private var currentPath: String { pathStack.last ?? "" }

    private var showingSharePicker: Bool {
        source.kind == .smb
            && (try? SMBClientService.Endpoint.resolve(source))?.share.isEmpty == true
            && pathStack.count == 1
            && currentPath.isEmpty
    }

    private var canImportFolder: Bool {
        !showingSharePicker && !probing && !loading
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
                if let listError, !loading {
                    Section {
                        Text(listError)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("一覧の読み込みエラー")
                        Button("再試行") {
                            Task { await reload() }
                        }
                        .accessibilityHint("フォルダ一覧を読み込み直す")
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
                        .disabled(probing)
                    } footer: {
                        Text("アプリ内に同名フォルダを作り、中身をその中へ入れます。画像フォルダは1冊にまとめます。取込は裏で進み、閉じても続行します。")
                    }
                }
                ForEach(entries) { entry in
                    if entry.isDirectory {
                        Button {
                            pathStack.append(entry.path)
                        } label: {
                            Label(entry.name, systemImage: "folder.fill")
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(folderAccessibilityLabel(entry))
                        .accessibilityHint("開く")
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                Task { await prepareFolderImport(path: entry.path, title: entry.name) }
                            } label: {
                                Label("取込", systemImage: "square.and.arrow.down")
                            }
                            .tint(.blue)
                            .disabled(busy)
                            .accessibilityLabel("フォルダを取り込む")
                        }
                        .contextMenu {
                            Button {
                                Task { await prepareFolderImport(path: entry.path, title: entry.name) }
                            } label: {
                                Label("フォルダを書庫に取り込む", systemImage: "square.and.arrow.down.on.square")
                            }
                            .disabled(probing)
                        }
                    } else {
                        Button {
                            startFileImport(entry)
                        } label: {
                            HStack {
                                Label(entry.name, systemImage: "doc")
                                Spacer()
                                if let size = entry.size {
                                    Text(Self.formatByteCount(size))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .accessibilityHidden(true)
                                }
                                if ComicFileProbe.isSupportedForImport(entry.name) {
                                    Text("取込")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .accessibilityHidden(true)
                                } else {
                                    Text("非対応")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(fileAccessibilityLabel(entry))
                        .accessibilityHint(
                            ComicFileProbe.isSupportedForImport(entry.name) ? "取り込む" : "取り込み非対応"
                        )
                        .disabled(!ComicFileProbe.isSupportedForImport(entry.name) || busy)
                    }
                }
            }
            .refreshable { await reload() }
            .navigationTitle(showingSharePicker ? "フォルダ選択" : source.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if pathStack.count > 1 {
                        Button("戻る") {
                            _ = pathStack.popLast()
                            Task { await reload() }
                        }
                        .disabled(probing)
                    }
                }
            }
            .overlay(alignment: .top) {
                ActivityOverlayView()
                    .allowsHitTesting(false)
            }
            .task(id: currentPath) { await reload() }
            .onChange(of: currentPath) { _, newPath in
                persistBrowsePath(newPath)
            }
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
                        startFolderImport(path: path, title: title)
                    }
                }
                Button("キャンセル", role: .cancel) {
                    pendingFolderImport = nil
                }
            } message: {
                if let pending = pendingFolderImport {
                    Text("書庫に「\(pending.title)」フォルダを作り、\(pending.unitCount) 冊を入れます。取込は裏で進みます。")
                }
            }
        }
    }

    private var folderTitle: String {
        if currentPath.isEmpty { return source.name }
        return (currentPath as NSString).lastPathComponent
    }

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f
    }()

    private static func formatByteCount(_ size: Int64) -> String {
        byteFormatter.string(fromByteCount: size)
    }

    /// VoiceOver: フォルダ行の日本語ラベル
    private func folderAccessibilityLabel(_ entry: RemoteEntry) -> String {
        "フォルダ、\(entry.name)"
    }

    /// VoiceOver: ファイル行の日本語ラベル（サイズがあれば含める）
    private func fileAccessibilityLabel(_ entry: RemoteEntry) -> String {
        var parts = ["ファイル", entry.name]
        if let size = entry.size {
            parts.append(Self.formatByteCount(size))
        }
        parts.append(ComicFileProbe.isSupportedForImport(entry.name) ? "取込可能" : "非対応")
        return parts.joined(separator: "、")
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        do {
            entries = try await RemoteGateway.list(source: source, path: currentPath)
            listError = nil
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

    /// ファイル取込を裏で開始し、すぐにブラウザを閉じられるようにする。
    private func startFileImport(_ entry: RemoteEntry) {
        let source = self.source
        let library = self.library
        let job = activity.begin(title: entry.name, status: "ダウンロード中…")
        let task = Task { @MainActor in
            do {
                try Task.checkCancellation()
                let tmp = try ImportStaging.fileURL(named: entry.name)
                defer { ImportStaging.removeSession(containing: tmp) }
                try await RemoteGateway.download(source: source, entry: entry, to: tmp)
                if activity.isCancelled(job) || Task.isCancelled { throw CancellationError() }
                activity.update(job, status: "書庫に展開中…")
                let title = UserFacingText.title(fromFileName: entry.name)
                _ = try library.importURL(tmp, folderId: library.currentFolderId, titleOverride: title)
                activity.succeed(job, banner: "取り込み完了: \(title)")
            } catch is CancellationError {
                activity.fail(job, message: "キャンセルしました")
            } catch {
                activity.fail(job, message: error.localizedDescription)
            }
        }
        activity.attachTask(job, task)
        dismiss()
    }

    private func prepareFolderImport(path: String, title: String) async {
        probing = true
        defer { probing = false }
        do {
            let units = try await RemoteGateway.collectImportUnits(source: source, path: path)
            guard !units.isEmpty else {
                errorText = "このフォルダに取込可能なファイル（cbz / zip / pdf / 画像）がありません"
                return
            }
            pendingFolderImport = PendingFolderImport(path: path, title: title, unitCount: units.count)
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// フォルダ取込を裏で開始し、シートを閉じて続行する。
    private func startFolderImport(path: String, title: String) {
        let source = self.source
        let library = self.library
        let job = activity.begin(title: title, status: "準備中…")
        let libraryFolder = library.folderForImport(named: title)
        library.currentFolderId = libraryFolder.id

        do {
            let units = try await RemoteGateway.collectImportUnits(source: source, path: path)
            guard !units.isEmpty else {
                activity.fail(job, message: "取込できるファイルがありません")
                return
            }
            var ok = 0
            var skipped = 0
            var failures: [String] = []
            for (i, unit) in units.enumerated() {
                if activity.isCancelled(job) { throw CancellationError() }
                let base = Double(i) / Double(units.count)
                do {
                    switch unit {
                    case .archive(let entry):
                        let cleanName = UserFacingText.title(fromFileName: entry.name)
                        activity.update(job, status: "ダウンロード \(i + 1)/\(units.count): \(cleanName)", fraction: base)
                        let tmp = try ImportStaging.fileURL(named: entry.name)
                        defer { ImportStaging.removeSession(containing: tmp) }
                        try await RemoteGateway.download(source: source, entry: entry, to: tmp)
                        if activity.isCancelled(job) { throw CancellationError() }
                        activity.update(job, status: "展開 \(i + 1)/\(units.count): \(cleanName)", fraction: base + 0.4 / Double(units.count))
                        let beforeIDs = Set(library.volumes.map(\.id))
                        let imported = try library.importURL(
                            tmp,
                            folderId: libraryFolder.id,
                            titleOverride: cleanName,
                            duplicatePolicy: .skipExactElseRename
                        )
                        if beforeIDs.contains(imported.id) {
                            skipped += 1
                        } else {
                            ok += 1
                        }
                    case .imageFolder(let folderTitle, let images):
                        let cleanFolder = UserFacingText.clean(folderTitle)
                        // ページ数が分かる画像フォルダは、同名・同ページならダウンロード前にスキップ。
                        if library.detectDuplicate(title: cleanFolder, pageCount: images.count) != nil {
                            activity.update(
                                job,
                                status: "スキップ（既存） \(i + 1)/\(units.count): \(cleanFolder)",
                                fraction: base + 1.0 / Double(units.count)
                            )
                            skipped += 1
                            continue
                        }
                        activity.update(job, status: "画像フォルダ \(i + 1)/\(units.count): \(cleanFolder)", fraction: base)
                        let dir = try ImportStaging.directoryURL(named: cleanFolder)
                        defer { ImportStaging.removeSession(containing: dir) }
                        for (j, entry) in images.enumerated() {
                            if activity.isCancelled(job) { throw CancellationError() }
                            // 画像ファイル名は元名を維持（ページ順用）。ディレクトリ名だけ浄化済み。
                            let imageDest = dir.appendingPathComponent((entry.name as NSString).lastPathComponent)
                            activity.update(
                                job,
                                status: "\(cleanFolder): \(j + 1)/\(images.count)",
                                fraction: base + Double(j) / Double(max(images.count, 1)) / Double(units.count)
                            )
                            try await RemoteGateway.download(source: source, entry: entry, to: imageDest)
                        }
                        let beforeIDs = Set(library.volumes.map(\.id))
                        let imported = try library.importURL(
                            dir,
                            folderId: libraryFolder.id,
                            titleOverride: cleanFolder,
                            duplicatePolicy: .skipExactElseRename
                        )
                        if beforeIDs.contains(imported.id) {
                            skipped += 1
                        } else {
                            ok += 1
                        }
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failures.append("\(unit.displayName): \(error.localizedDescription)")
                }
                var ok = 0
                var failures: [String] = []
                for (i, unit) in units.enumerated() {
                    if activity.isCancelled(job) || Task.isCancelled { throw CancellationError() }
                    let base = Double(i) / Double(units.count)
                    do {
                        switch unit {
                        case .archive(let entry):
                            let cleanName = UserFacingText.title(fromFileName: entry.name)
                            activity.update(job, status: "ダウンロード \(i + 1)/\(units.count): \(cleanName)", fraction: base)
                            let tmp = try ImportStaging.fileURL(named: entry.name)
                            defer { ImportStaging.removeSession(containing: tmp) }
                            try await RemoteGateway.download(source: source, entry: entry, to: tmp)
                            if activity.isCancelled(job) || Task.isCancelled { throw CancellationError() }
                            activity.update(job, status: "展開 \(i + 1)/\(units.count): \(cleanName)", fraction: base + 0.4 / Double(units.count))
                            _ = try library.importURL(tmp, folderId: libraryFolder.id, titleOverride: cleanName)
                        case .imageFolder(let folderTitle, let images):
                            let cleanFolder = UserFacingText.clean(folderTitle)
                            activity.update(job, status: "画像フォルダ \(i + 1)/\(units.count): \(cleanFolder)", fraction: base)
                            let dir = try ImportStaging.directoryURL(named: cleanFolder)
                            defer { ImportStaging.removeSession(containing: dir) }
                            for (j, entry) in images.enumerated() {
                                if activity.isCancelled(job) || Task.isCancelled { throw CancellationError() }
                                let imageDest = dir.appendingPathComponent((entry.name as NSString).lastPathComponent)
                                activity.update(
                                    job,
                                    status: "\(cleanFolder): \(j + 1)/\(images.count)",
                                    fraction: base + Double(j) / Double(max(images.count, 1)) / Double(units.count)
                                )
                                try await RemoteGateway.download(source: source, entry: entry, to: imageDest)
                            }
                            _ = try library.importURL(dir, folderId: libraryFolder.id, titleOverride: cleanFolder)
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
            } catch is CancellationError {
                activity.fail(job, message: "キャンセルしました（途中までの取込は残ります）")
            } catch {
                activity.fail(job, message: error.localizedDescription)
            }
            if failures.isEmpty {
                var parts: [String] = []
                if ok > 0 { parts.append("\(ok) 冊を取り込み") }
                if skipped > 0 { parts.append("\(skipped) 冊は既存のためスキップ") }
                let summary = parts.isEmpty ? "取込対象なし" : parts.joined(separator: "、")
                activity.succeed(job, banner: "「\(libraryFolder.name)」: \(summary)")
            } else {
                activity.fail(
                    job,
                    message: "成功 \(ok)/\(units.count)（スキップ \(skipped)）。失敗: \(failures.prefix(2).joined(separator: " / "))"
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
        activity.attachTask(job, task)
        dismiss()
    }
}
