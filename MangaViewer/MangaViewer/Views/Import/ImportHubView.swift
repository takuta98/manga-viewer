import SwiftUI
import UniformTypeIdentifiers

struct ImportHubView: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var sources = RemoteSourceStore.shared
    @ObservedObject private var activity = TransferActivityCenter.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showFilesPicker = false
    @State private var showURLSheet = false
    @State private var showWiFi = false
    @State private var showAddSource: RemoteSourceKind?
    @State private var browseSource: RemoteSource?
    @State private var editSource: RemoteSource?
    @State private var errorText: String?
    @State private var urlText = ""
    @State private var importingLocal = false

    var body: some View {
        NavigationStack {
            List {
                Section("この端末 / クラウド") {
                    Button {
                        showFilesPicker = true
                    } label: {
                        Label("Files / iCloud / Dropbox / Google Drive など", systemImage: RemoteSourceKind.files.systemImage)
                    }
                    Text("Files に表示されるプロバイダから選べます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("ネットワーク") {
                    ForEach([RemoteSourceKind.smb, .webdav, .ftp, .sftp, .opds, .s3], id: \.self) { kind in
                        Button {
                            showAddSource = kind
                        } label: {
                            Label("\(kind.label) を追加", systemImage: kind.systemImage)
                        }
                    }
                    Button {
                        showURLSheet = true
                    } label: {
                        Label(RemoteSourceKind.httpURL.label, systemImage: RemoteSourceKind.httpURL.systemImage)
                    }
                    Button {
                        showWiFi = true
                    } label: {
                        Label(RemoteSourceKind.wifiTransfer.label, systemImage: RemoteSourceKind.wifiTransfer.systemImage)
                    }
                }

                if !sources.sources.isEmpty {
                    Section("保存済み接続") {
                        ForEach(sources.sources) { source in
                            Button {
                                browseSource = source
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Label(source.name, systemImage: source.kind.systemImage)
                                    Text(savedSourceCaption(source))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contextMenu {
                                Button {
                                    browseSource = source
                                } label: {
                                    Label("開く", systemImage: "folder")
                                }
                                Button {
                                    editSource = source
                                } label: {
                                    Label("編集", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    sources.delete(source)
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    sources.delete(source)
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    editSource = source
                                } label: {
                                    Label("編集", systemImage: "pencil")
                                }
                                .tint(.indigo)
                            }
                        }
                    }
                }
            }
            .navigationTitle("取り込む")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .overlay { ActivityOverlayView() }
            .fileImporter(
                isPresented: $showFilesPicker,
                allowedContentTypes: MangaImporter.supportedTypes,
                allowsMultipleSelection: true
            ) { result in
                Task { await handleFiles(result) }
            }
            .sheet(item: $showAddSource) { kind in
                AddSourceView(kind: kind) { source in
                    sources.add(source)
                    browseSource = source
                }
            }
            .sheet(item: $editSource) { source in
                AddSourceView(source: source) { updated in
                    sources.update(updated)
                }
            }
            .sheet(item: $browseSource) { source in
                RemoteBrowserView(library: library, source: source)
            }
            .sheet(isPresented: $showURLSheet) {
                NavigationStack {
                    Form {
                        TextField("https://…/book.cbz", text: $urlText)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                        Text("ダウンロードは裏で進み、シートを閉じても続行します。進捗は書庫の転送状況から確認できます。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .navigationTitle("URL から取得")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("キャンセル") { showURLSheet = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("ダウンロード") {
                                startURLDownload()
                            }
                            .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .sheet(isPresented: $showWiFi) {
                WiFiTransferView(library: library)
            }
            .alert("エラー", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("OK", role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
            .disabled(importingLocal)
        }
    }


    private func savedSourceCaption(_ source: RemoteSource) -> String {
        var parts = ["\(source.kind.label) · \(source.host)"]
        if let at = source.lastSuccessAt {
            parts.append("最終成功 \(Self.relativeSuccess.localizedString(for: at, relativeTo: Date()))")
        }
        return parts.joined(separator: " · ")
    }

    private static let relativeSuccess: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = Locale(identifier: "ja_JP")
        return f
    }()

    private func handleFiles(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            importingLocal = true
            defer { importingLocal = false }
            let job = activity.begin(title: "Files から取込", status: "取り込み中…")
            do {
                for (i, url) in urls.enumerated() {
                    activity.update(job, status: url.lastPathComponent, fraction: Double(i) / Double(max(urls.count, 1)))
                    _ = try library.importURL(url)
                }
                activity.succeed(job, banner: "\(urls.count) 件を取り込みました")
                dismiss()
            } catch {
                activity.fail(job, message: error.localizedDescription)
                errorText = error.localizedDescription
            }
        case .failure(let error):
            errorText = error.localizedDescription
        }
    }

    /// URL 取得を裏で開始し、シートを閉じて続行する。
    private func startURLDownload() {
        let rawURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = URL(string: rawURL)?.lastPathComponent ?? "download.cbz"
        let name = UserFacingText.title(fromFileName: fileName)
        let library = self.library
        let job = activity.begin(title: name, status: "ダウンロード中…")

        showURLSheet = false
        dismiss()

        let task = Task { @MainActor in
            do {
                try Task.checkCancellation()
                let tmp = try ImportStaging.fileURL(named: fileName)
                defer { ImportStaging.removeSession(containing: tmp) }
                try await HTTPDownloadService.download(urlString: rawURL, to: tmp) { fraction in
                    Task { @MainActor in
                        if !activity.isCancelled(job) {
                            activity.update(job, status: "ダウンロード中…", fraction: fraction)
                        }
                    }
                }
                if activity.isCancelled(job) || Task.isCancelled { throw CancellationError() }
                activity.update(job, status: "書庫に展開中…")
                _ = try library.importURL(tmp, titleOverride: name)
                activity.succeed(job, banner: "取り込み完了: \(name)")
            } catch is CancellationError {
                activity.fail(job, message: "キャンセルしました")
            } catch {
                activity.fail(job, message: error.localizedDescription)
            }
        }
        activity.attachTask(job, task)
    }
}

extension RemoteSourceKind: Hashable {}
