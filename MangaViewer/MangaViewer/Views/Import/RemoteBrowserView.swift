import SwiftUI

struct RemoteBrowserView: View {
    @ObservedObject var library: LibraryStore
    let source: RemoteSource

    @Environment(\.dismiss) private var dismiss
    @State private var pathStack: [String]
    @State private var entries: [RemoteEntry] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var importingName: String?

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

    var body: some View {
        NavigationStack {
            List {
                if loading {
                    ProgressView("読み込み中…")
                }
                if showingSharePicker && !entries.isEmpty {
                    Text("フォルダを選んでください")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    if entry.isDirectory {
                        Button {
                            pathStack.append(entry.path)
                        } label: {
                            Label(entry.name, systemImage: "folder")
                        }
                    } else {
                        Button {
                            Task { await importEntry(entry) }
                        } label: {
                            HStack {
                                Label(entry.name, systemImage: "doc")
                                Spacer()
                                if importingName == entry.name {
                                    ProgressView()
                                } else if ComicFileProbe.isSupportedForImport(entry.name) {
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
                        .disabled(!ComicFileProbe.isSupportedForImport(entry.name) || importingName != nil)
                    }
                }
            }
            .navigationTitle(showingSharePicker ? "フォルダ選択" : source.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if pathStack.count > 1 {
                        Button("戻る") { _ = pathStack.popLast(); Task { await reload() } }
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

    private func reload() async {
        loading = true
        defer { loading = false }
        do {
            entries = try await RemoteGateway.list(source: source, path: currentPath)
        } catch {
            errorText = error.localizedDescription
            entries = []
        }
    }

    private func importEntry(_ entry: RemoteEntry) async {
        importingName = entry.name
        defer { importingName = nil }
        do {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(entry.name)
            try await RemoteGateway.download(source: source, entry: entry, to: tmp)
            try library.importURL(tmp)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
