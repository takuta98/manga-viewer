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

    private var displayedVolumes: [MangaVolume] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = library.volumes(in: library.currentFolderId)
        guard !q.isEmpty else { return base }
        return base.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    private var displayedFolders: [LibraryFolder] {
        guard !inFolder else { return [] }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = library.sortedFolders
        guard !q.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        Group {
            if displayMode == .grid {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 14)], spacing: 16) {
                        ForEach(displayedFolders) { folder in
                            Button { library.currentFolderId = folder.id } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Image(systemName: "folder.fill").font(.largeTitle).foregroundStyle(.yellow)
                                    Text(folder.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    Text("\(library.volumeCount(in: folder.id)) 冊").font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("削除", role: .destructive) { folderPendingDelete = folder }
                            }
                        }
                        ForEach(displayedVolumes) { volume in
                            volumeCell(volume)
                        }
                    }
                    .padding()
                }
            } else {
                List {
                    ForEach(displayedFolders) { folder in
                        Button { library.currentFolderId = folder.id } label: {
                            Label(folder.name, systemImage: "folder.fill")
                        }
                        .swipeActions {
                            Button(role: .destructive) { folderPendingDelete = folder } label: { Label("削除", systemImage: "trash") }
                        }
                    }
                    ForEach(displayedVolumes) { volume in
                        Button { onOpen(volume) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(volume.title).font(.headline)
                                Text("\(volume.pageCount) ページ").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu { volumeMenu(volume) }
                        .swipeActions {
                            Button(role: .destructive) { volumePendingDelete = volume } label: { Label("削除", systemImage: "trash") }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $query, prompt: "タイトル検索")
        .navigationTitle(currentFolder?.name ?? "書庫")
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                if inFolder {
                    Button { library.currentFolderId = nil } label: { Label("書庫", systemImage: "chevron.left") }
                }
                Button {
                    displayMode = displayMode.toggled
                    AppSettingsStore.saveLibraryDisplayMode(displayMode)
                } label: {
                    Image(systemName: displayMode.toggled.systemImage)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    if !inFolder {
                        Button { showNewFolder = true } label: { Image(systemName: "folder.badge.plus") }
                    }
                    Button { showTransfers = true } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "arrow.down.circle")
                            if activity.activeCount > 0 {
                                Text("\(activity.activeCount)").font(.caption2.bold()).padding(4)
                                    .background(Circle().fill(.red)).foregroundStyle(.white).offset(x: 8, y: -8)
                            }
                        }
                    }
                    .accessibilityLabel("転送状況")
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    Button { showImportHub = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("取り込む")
                }
            }
        }
        .overlay {
            if displayedFolders.isEmpty && displayedVolumes.isEmpty {
                ContentUnavailableView("書庫が空です", systemImage: "books.vertical", description: Text("右上の + から取り込みできます"))
            }
        }
        .sheet(isPresented: $showImportHub) { ImportHubView(library: library) }
        .sheet(isPresented: $showTransfers) { TransferStatusView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $infoTarget) { VolumeInfoView(volume: $0) }
        .sheet(item: $renameTarget) { volume in
            NavigationStack {
                Form { TextField("タイトル", text: $renameText) }
                    .navigationTitle("名前を変更")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { renameTarget = nil } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("保存") { library.rename(volume, title: renameText); renameTarget = nil }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
        .alert("新しいフォルダ", isPresented: $showNewFolder) {
            TextField("フォルダ名", text: $newFolderName)
            Button("キャンセル", role: .cancel) {}
            Button("作成") {
                let n = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty { _ = library.createFolder(name: n) }
            }
        }
        .alert("フォルダを削除", isPresented: Binding(get: { folderPendingDelete != nil }, set: { if !$0 { folderPendingDelete = nil } }), presenting: folderPendingDelete) { folder in
            Button("キャンセル", role: .cancel) { folderPendingDelete = nil }
            Button("削除", role: .destructive) { library.deleteFolder(folder); folderPendingDelete = nil }
        } message: { folder in
            Text("「\(folder.name)」を削除します。フォルダ内の作品は未分類に移されます。")
        }
        .alert("作品を削除", isPresented: Binding(get: { volumePendingDelete != nil }, set: { if !$0 { volumePendingDelete = nil } }), presenting: volumePendingDelete) { volume in
            Button("キャンセル", role: .cancel) { volumePendingDelete = nil }
            Button("削除", role: .destructive) { library.delete(volume); volumePendingDelete = nil }
        } message: { volume in
            Text("「\(volume.title)」を削除します。この操作は取り消せません。")
        }
        .onAppear { TransferActivityCenter.requestNotificationPermissionOnce() }
        .safeAreaInset(edge: .top) {
            if let err = library.catalogLoadError {
                Text(err).font(.footnote).foregroundStyle(.white).padding(10)
                    .frame(maxWidth: .infinity).background(Color.red.opacity(0.85))
            }
        }
    }

    private func volumeCell(_ volume: MangaVolume) -> some View {
        let pct = ProgressStore.shared.progressPercent(for: volume, coverAlone: true, layout: .single)
        return Button { onOpen(volume) } label: {
            VStack(alignment: .leading, spacing: 8) {
                cover(volume)
                Text(volume.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(pct >= 100 ? "読了" : (pct > 0 ? "\(pct)%" : "未読")).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .contextMenu { volumeMenu(volume) }
    }

    @ViewBuilder private func volumeMenu(_ volume: MangaVolume) -> some View {
        Button("情報") { infoTarget = volume }
        Button("名前を変更") { renameTarget = volume; renameText = volume.title }
        Button("削除", role: .destructive) { volumePendingDelete = volume }
    }

    private func cover(_ volume: MangaVolume) -> some View {
        Group {
            if let url = volume.coverURL(), let ui = UIImage(contentsOfFile: url.path) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                Rectangle().fill(Color.secondary.opacity(0.25))
            }
        }
        .aspectRatio(2/3, contentMode: .fit)
        .clipped()
        .cornerRadius(6)
    }
}
