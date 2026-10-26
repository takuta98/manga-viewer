import SwiftUI

struct LibraryView: View {
    @ObservedObject var library: LibraryStore
    var onOpen: (MangaVolume) -> Void

    @ObservedObject private var activity = TransferActivityCenter.shared
    @State private var showImportHub = false
    @State private var showTransfers = false
    @State private var showSettings = false
    @State private var query = ""
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var renameTarget: MangaVolume?
    @State private var renameText = ""
    @State private var volumePendingDelete: MangaVolume?
    @State private var folderPendingDelete: LibraryFolder?
    @State private var displayMode: LibraryDisplayMode = AppSettingsStore.loadLibraryDisplayMode()
    @State private var infoTarget: MangaVolume?

    private var inFolder: Bool { library.currentFolderId != nil }
    private var currentFolder: LibraryFolder? {
        library.folders.first { $0.id == library.currentFolderId }
    }
    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displayedVolumes: [MangaVolume] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = library.volumes(in: library.currentFolderId)
        guard !q.isEmpty else { return base }
        return base.filter { $0.title.localizedStandardContains(q) }
    }

    private var displayedFolders: [LibraryFolder] {
        guard !inFolder else { return [] }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = library.sortedFolders
        guard !q.isEmpty else { return list }
        return list.filter { $0.name.localizedStandardContains(q) }
    }

    private var isEmpty: Bool {
        displayedFolders.isEmpty && displayedVolumes.isEmpty
    }

    var body: some View {
        Group {
            if isEmpty {
                emptyState
            } else if displayMode == .grid {
                gridContent
            } else {
                listContent
            }
        }
        .searchable(text: $query, prompt: AppCopy.librarySearchPrompt)
        .navigationTitle(currentFolder?.name ?? AppCopy.libraryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .overlay(alignment: .top) { ActivityOverlayView() }
        .safeAreaInset(edge: .bottom) {
            DownloadStatusChip { showTransfers = true }
        }
        .sheet(isPresented: $showImportHub) { ImportHubView(library: library) }
        .sheet(isPresented: $showTransfers) { TransferStatusView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $infoTarget) { VolumeInfoView(volume: $0) }
        .sheet(item: $renameTarget) { volume in
            NavigationStack {
                Form { TextField(AppCopy.titleField, text: $renameText) }
                    .navigationTitle(AppCopy.rename)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(AppCopy.cancel) { renameTarget = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(AppCopy.save) {
                                library.rename(volume, title: renameText)
                                renameTarget = nil
                            }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
        .alert(AppCopy.newFolder, isPresented: $showNewFolder) {
            TextField(AppCopy.folderName, text: $newFolderName)
            Button(AppCopy.cancel, role: .cancel) {}
            Button(AppCopy.create) {
                let n = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty { _ = library.createFolder(name: n) }
            }
        }
        .alert(
            "フォルダを削除",
            isPresented: Binding(
                get: { folderPendingDelete != nil },
                set: { if !$0 { folderPendingDelete = nil } }
            ),
            presenting: folderPendingDelete
        ) { folder in
            Button(AppCopy.cancel, role: .cancel) { folderPendingDelete = nil }
            Button(AppCopy.delete, role: .destructive) {
                library.deleteFolder(folder)
                folderPendingDelete = nil
            }
        } message: { folder in
            Text("「\(folder.name)」を削除します。フォルダ内の作品は未分類に移されます。")
        }
        .alert(
            "作品を削除",
            isPresented: Binding(
                get: { volumePendingDelete != nil },
                set: { if !$0 { volumePendingDelete = nil } }
            ),
            presenting: volumePendingDelete
        ) { volume in
            Button(AppCopy.cancel, role: .cancel) { volumePendingDelete = nil }
            Button(AppCopy.delete, role: .destructive) {
                library.delete(volume)
                volumePendingDelete = nil
            }
        } message: { volume in
            Text("「\(volume.title)」を削除します。この操作は取り消せません。")
        }
        .onAppear { TransferActivityCenter.requestNotificationPermissionOnce() }
        .onChange(of: library.currentFolderId) { _, _ in query = "" }
        .safeAreaInset(edge: .top) {
            if let err = library.catalogLoadError {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.85))
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if isSearching {
            ContentUnavailableView(
                AppCopy.librarySearchEmptyTitle,
                systemImage: "magnifyingglass",
                description: Text(AppCopy.librarySearchEmptyBody)
            )
        } else {
            ContentUnavailableView(
                AppCopy.libraryEmptyTitle,
                systemImage: "books.vertical",
                description: Text(AppCopy.libraryEmptyBody)
            )
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 118), spacing: 14)],
                spacing: 18
            ) {
                ForEach(displayedFolders) { folder in
                    Button { library.currentFolderId = folder.id } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            FolderThumbView()
                            Text(folder.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(library.volumeCount(in: folder.id)) \(AppCopy.volumeCountSuffix)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(AppCopy.delete, role: .destructive) { folderPendingDelete = folder }
                    }
                }
                ForEach(displayedVolumes) { volume in
                    volumeCell(volume)
                }
            }
            .padding(16)
        }
    }

    private var listContent: some View {
        List {
            ForEach(displayedFolders) { folder in
                Button { library.currentFolderId = folder.id } label: {
                    Label(folder.name, systemImage: "folder.fill")
                }
                .swipeActions {
                    Button(role: .destructive) {
                        folderPendingDelete = folder
                    } label: {
                        Label(AppCopy.delete, systemImage: "trash")
                    }
                }
            }
            ForEach(displayedVolumes) { volume in
                Button { onOpen(volume) } label: {
                    HStack(spacing: 12) {
                        CoverThumbView(imageURL: volume.coverURL(), cornerRadius: 4)
                            .frame(width: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(volume.title).font(.headline).lineLimit(2)
                            Text("\(volume.pageCount) \(AppCopy.pageCountSuffix)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .contextMenu { volumeMenu(volume) }
                .swipeActions {
                    Button(role: .destructive) {
                        volumePendingDelete = volume
                    } label: {
                        Label(AppCopy.delete, systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if inFolder {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    library.currentFolderId = nil
                } label: {
                    Label(AppCopy.backToLibrary, systemImage: "chevron.left")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showImportHub = true } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel(AppCopy.getWorks)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    displayMode = displayMode.toggled
                    AppSettingsStore.saveLibraryDisplayMode(displayMode)
                } label: {
                    Label(AppCopy.displayMode, systemImage: displayMode.toggled.systemImage)
                }
                if !inFolder {
                    Button { showNewFolder = true } label: {
                        Label(AppCopy.newFolder, systemImage: "folder.badge.plus")
                    }
                }
                Button { showTransfers = true } label: {
                    Label(
                        activity.activeCount > 0
                            ? "\(AppCopy.downloads) (\(activity.activeCount))"
                            : AppCopy.downloads,
                        systemImage: "arrow.down.circle"
                    )
                }
                Button { showSettings = true } label: {
                    Label(AppCopy.settings, systemImage: "gearshape")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel(AppCopy.more)
        }
    }

    private func volumeCell(_ volume: MangaVolume) -> some View {
        let pct = ProgressStore.shared.progressPercent(for: volume, coverAlone: true, layout: .single)
        return Button { onOpen(volume) } label: {
            VStack(alignment: .leading, spacing: 8) {
                CoverThumbView(imageURL: volume.coverURL())
                Text(volume.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(pct >= 100 ? AppCopy.finishedReading : (pct > 0 ? "\(pct)%" : AppCopy.unread))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .contextMenu { volumeMenu(volume) }
    }

    @ViewBuilder
    private func volumeMenu(_ volume: MangaVolume) -> some View {
        Button(AppCopy.info) { infoTarget = volume }
        Button(AppCopy.rename) {
            renameTarget = volume
            renameText = volume.title
        }
        Button(AppCopy.delete, role: .destructive) { volumePendingDelete = volume }
    }
}
