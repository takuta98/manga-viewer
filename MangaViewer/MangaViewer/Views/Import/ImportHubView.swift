import SwiftUI
import UniformTypeIdentifiers

struct ImportHubView: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var sources = RemoteSourceStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showFiles = false
    @State private var showWiFi = false
    @State private var addingKind: RemoteSourceKind?
    @State private var browseSource: RemoteSource?
    @ObservedObject private var activity = TransferActivityCenter.shared

    var body: some View {
        NavigationStack {
            List {
                Section("この端末") {
                    Button("ファイル App から選ぶ") { showFiles = true }
                    Button("Wi‑Fi 転送") { showWiFi = true }
                }
                Section("接続") {
                    ForEach(RemoteSourceKind.allCases) { kind in
                        Button("\(kind.label) を追加") { addingKind = kind }
                    }
                }
                if !sources.sources.isEmpty {
                    Section("保存済み") {
                        ForEach(sources.sources) { source in
                            Button {
                                browseSource = sources.hydrated(source)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(source.name)
                                    Text(source.kind.label + (source.host.isEmpty ? "" : " · \(source.host)"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) { sources.delete(source) } label: { Label("削除", systemImage: "trash") }
                            }
                        }
                    }
                }
            }
            .navigationTitle("取り込む")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
            .overlay(alignment: .top) { ActivityOverlayView().allowsHitTesting(false) }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [UTType.zip, .image, .folder], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    for url in urls { startLocalImport(url) }
                }
            }
            .sheet(isPresented: Binding(get: { addingKind != nil }, set: { if !$0 { addingKind = nil } })) {
                if let kind = addingKind {
                    AddSourceView(kind: kind) { source in
                        sources.add(source)
                        browseSource = sources.hydrated(source)
                        addingKind = nil
                    }
                }
            }
            .sheet(item: $browseSource) { source in
                RemoteBrowserView(library: library, source: source)
            }
            .sheet(isPresented: $showWiFi) { WiFiTransferView(library: library) }
        }
    }

    private func startLocalImport(_ url: URL) {
        let job = activity.begin(title: url.lastPathComponent)
        let task = Task { @MainActor in
            do {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let staged = try ImportStaging.fileURL(named: url.lastPathComponent)
                defer { ImportStaging.removeSession(containing: staged) }
                if url.startAccessingSecurityScopedResource() || true {
                    try? FileManager.default.copyItem(at: url, to: staged)
                }
                let src = FileManager.default.fileExists(atPath: staged.path) ? staged : url
                let title = UserFacingText.title(fromFileName: url.lastPathComponent)
                _ = try library.importURL(src, folderId: library.currentFolderId, titleOverride: title)
                activity.succeed(job, banner: "取り込み完了: \(title)")
            } catch {
                activity.fail(job, message: error.localizedDescription)
            }
        }
        activity.attachTask(job, task)
    }
}
