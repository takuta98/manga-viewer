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
                                    Text("\(source.kind.label) · \(source.host)")
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
                    }
                    .navigationTitle("URL から取得")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("キャンセル") { showURLSheet = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("ダウンロード") {
                                Task { await downloadURL() }
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

    private func downloadURL() async {
        let name = URL(string: urlText)?.lastPathComponent ?? "download.cbz"
        let job = activity.begin(title: name, status: "ダウンロード中…")
        do {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "-" + name)
            try await HTTPDownloadService.download(urlString: urlText, to: tmp) { fraction in
                Task { @MainActor in
                    activity.update(job, status: "ダウンロード中…", fraction: fraction)
                }
            }
            activity.update(job, status: "書庫に展開中…", fraction: 0.9)
            _ = try library.importURL(tmp)
            activity.succeed(job, banner: "取り込み完了: \(name)")
            showURLSheet = false
            dismiss()
        } catch {
            activity.fail(job, message: error.localizedDescription)
            errorText = error.localizedDescription
        }
    }
}

extension RemoteSourceKind: Hashable {}
