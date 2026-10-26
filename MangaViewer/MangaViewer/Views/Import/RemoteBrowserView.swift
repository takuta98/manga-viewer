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
                            Task { await importFolder(path: currentPath, title: folderTitle) }
                        } label: {
                            Label("このフォルダ内をすべて取り込む", systemImage: "square.and.arrow.down.on.square")
                        }
                        .disabled(busy)
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
                                Task { await importFolder(path: entry.path, title: entry.name) }
                            } label: {
                                Label("取込", systemImage: "square.and.arrow.down")
                            }
                            .tint(.blue)
                            .disabled(busy)
                        }
                        .contextMenu {
                            Button {
                                Task { await importFolder(path: entry.path, title: entry.name) }
                            } label: {
                                Label("フォルダを取り込む", systemImage: "square.and.arrow.down.on.square")
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
            }
            .overlay {
                if busy {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("取り込み中…")
                                .font(.subheadline.weight(.semibold))
                            Text("画面上部の進捗も確認できます")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
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
        do {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + entry.name)
            activity.update(job, status: "ダウンロード中…", fraction: 0.15)
            try await RemoteGateway.download(source: source, entry: entry, to: tmp)
            activity.update(job, status: "書庫に展開中…", fraction: 0.7)
            _ = try library.importURL(tmp)
            activity.succeed(job, banner: "取り込み完了: \(entry.name)")
            errorText = nil
        } catch {
            activity.fail(job, message: error.localizedDescription)
            errorText = error.localizedDescription
        }
    }

    private func importFolder(path: String, title: String) async {
        busy = true
        defer { busy = false }
        let job = activity.begin(title: title, status: "ファイルを検索中…")
        do {
            let files = try await RemoteGateway.collectImportableFiles(source: source, path: path)
            guard !files.isEmpty else {
                activity.fail(job, message: "取込できるファイルがありません")
                errorText = "このフォルダに取込可能なファイル（cbz / zip / pdf / 画像）がありません"
                return
            }
            var ok = 0
            for (i, entry) in files.enumerated() {
                let fraction = Double(i) / Double(files.count)
                activity.update(
                    job,
                    status: "ダウンロード中 \(i + 1)/\(files.count): \(entry.name)",
                    fraction: fraction
                )
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + "-" + entry.name)
                try await RemoteGateway.download(source: source, entry: entry, to: tmp)
                activity.update(
                    job,
                    status: "展開中 \(i + 1)/\(files.count): \(entry.name)",
                    fraction: (Double(i) + 0.5) / Double(files.count)
                )
                _ = try library.importURL(tmp)
                ok += 1
            }
            activity.succeed(job, banner: "\(ok) 件を取り込みました")
            errorText = nil
        } catch {
            activity.fail(job, message: error.localizedDescription)
            errorText = error.localizedDescription
        }
    }
}
