import SwiftUI
import UniformTypeIdentifiers

struct ImportHubView: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var sources = RemoteSourceStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showFilesPicker = false
    @State private var showURLSheet = false
    @State private var showWiFi = false
    @State private var showAddSource: RemoteSourceKind?
    @State private var browseSource: RemoteSource?
    @State private var errorText: String?
    @State private var urlText = ""

    var body: some View {
        NavigationStack {
            List {
                Section("この端末 / クラウド") {
                    Button {
                        showFilesPicker = true
                    } label: {
                        Label("Files / iCloud / Dropbox / Google Drive など", systemImage: RemoteSourceKind.files.systemImage)
                    }
                    Text("Files に表示されるプロバイダ（iCloud・各クラウドアプリ・SMB 接続済みサーバ）から選べます。")
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
                    Section("保存済みソース") {
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
                            .swipeActions {
                                Button(role: .destructive) {
                                    sources.delete(source)
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
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
            .fileImporter(
                isPresented: $showFilesPicker,
                allowedContentTypes: MangaImporter.supportedTypes,
                allowsMultipleSelection: true
            ) { result in
                handleFiles(result)
            }
            .sheet(item: $showAddSource) { kind in
                AddSourceView(kind: kind) { source in
                    sources.add(source)
                    browseSource = source
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
        }
    }

    private func handleFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                do { try library.importURL(url) }
                catch { errorText = error.localizedDescription }
            }
            dismiss()
        case .failure(let error):
            errorText = error.localizedDescription
        }
    }

    private func downloadURL() async {
        do {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "-" + (URL(string: urlText)?.lastPathComponent ?? "download.cbz"))
            try await HTTPDownloadService.download(urlString: urlText, to: tmp)
            try library.importURL(tmp)
            showURLSheet = false
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

extension RemoteSourceKind: Hashable {}
