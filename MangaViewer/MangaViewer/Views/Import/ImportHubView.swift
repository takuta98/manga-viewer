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
                Section(AppCopy.thisDevice) {
                    Button(AppCopy.fromFiles) { showFiles = true }
                    Button(AppCopy.fromWiFi) { showWiFi = true }
                }
                Section(AppCopy.newConnection) {
                    ForEach(RemoteSourceKind.allCases) { kind in
                        Button(AppCopy.addKind(kind.label)) { addingKind = kind }
                    }
                }
                if !sources.sources.isEmpty {
                    Section(AppCopy.savedConnections) {
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
                                Button(role: .destructive) { sources.delete(source) } label: {
                                    Label(AppCopy.delete, systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(AppCopy.getWorks)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.close) { dismiss() }
                }
            }
            .overlay(alignment: .top) { ActivityOverlayView() }
            .fileImporter(
                isPresented: $showFiles,
                allowedContentTypes: [UTType.zip, .image, .folder],
                allowsMultipleSelection: true
            ) { result in
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
                try? FileManager.default.removeItem(at: staged)
                try FileManager.default.copyItem(at: url, to: staged)
                let title = UserFacingText.title(fromFileName: url.lastPathComponent)
                _ = try library.importURL(staged, folderId: library.currentFolderId, titleOverride: title)
                activity.succeed(job)
            } catch {
                activity.fail(job, message: error.localizedDescription)
            }
        }
        activity.attachTask(job, task)
    }
}
