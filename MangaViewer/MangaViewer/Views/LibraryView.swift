import SwiftUI

struct LibraryView: View {
    @ObservedObject var library: LibraryStore
    var onOpen: (MangaVolume) -> Void

    @State private var showImportHub = false
    @State private var renameTarget: MangaVolume?
    @State private var renameText = ""
    @State private var showSettings = false
    @State private var query = ""
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var renameFolderTarget: LibraryFolder?
    @State private var renameFolderText = ""
    @State private var moveTarget: MangaVolume?

    private var prefs: ReaderPreferences { AppSettingsStore.loadPrefs() }

    private var inFolder: Bool { library.currentFolderId != nil }

    private var currentFolder: LibraryFolder? {
        guard let id = library.currentFolderId else { return nil }
        return library.folders.first { $0.id == id }
    }

    private var displayedVolumes: [MangaVolume] {
        let base = library.volumes(in: library.currentFolderId)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
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
        List {
            if !inFolder {
                ForEach(displayedFolders) { folder in
                    Button {
                        library.currentFolderId = folder.id
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "folder.fill")
                                .font(.title2)
                                .foregroundStyle(.yellow.opacity(0.9))
                                .frame(width: 56, height: 84)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(folder.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("\(library.volumeCount(in: folder.id)) 冊")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .contextMenu {
                        Button("名前を変更") {
                            renameFolderTarget = folder
                            renameFolderText = folder.name
                        }
                        Button("削除", role: .destructive) {
                            library.deleteFolder(folder)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            library.deleteFolder(folder)
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
                }
            }

            ForEach(displayedVolumes) { volume in
                Button {
                    onOpen(volume)
                } label: {
                    HStack(spacing: 14) {
                        cover(for: volume)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(volume.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            let pct = ProgressStore.shared.progressPercent(
                                for: volume,
                                coverAlone: prefs.coverAlone,
                                layout: prefs.layoutMode
                            )
                            Text("\(volume.pageCount) ページ · \(volume.direction.shortLabel)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            ProgressView(value: Double(pct), total: 100)
                                .tint(pct >= 100 ? .green : .accentColor)
                            Text(pct > 0 ? "\(pct)%" : "未読")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
                .contextMenu {
                    Button("名前を変更") {
                        renameTarget = volume
                        renameText = volume.title
                    }
                    Menu("フォルダへ移動") {
                        Button("未分類") { library.move(volume, to: nil) }
                        ForEach(library.sortedFolders) { folder in
                            Button(folder.name) { library.move(volume, to: folder.id) }
                        }
                    }
                    Button("削除", role: .destructive) {
                        library.delete(volume)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        library.delete(volume)
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        moveTarget = volume
                    } label: {
                        Label("移動", systemImage: "folder")
                    }
                    .tint(.indigo)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $query, prompt: "タイトル検索")
        .navigationTitle(currentFolder?.name ?? "書庫")
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
        .navigationBarBackButtonHidden(false)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if inFolder {
                    Button {
                        library.currentFolderId = nil
                    } label: {
                        Label("書庫", systemImage: "chevron.left")
                    }
                } else {
                    Menu {
                        Picker("並び替え", selection: $library.sort) {
                            ForEach(LibrarySort.allCases) { sort in
                                Text(sort.label).tag(sort)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    if !inFolder {
                        Button {
                            newFolderName = ""
                            showNewFolder = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                        }
                        .accessibilityLabel("フォルダを作成")
                    }
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    Button { showImportHub = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("取り込む")
                }
            }
        }
        .overlay {
            if displayedFolders.isEmpty && displayedVolumes.isEmpty {
                ContentUnavailableView(
                    inFolder ? "このフォルダは空です" : "書庫が空です",
                    systemImage: "books.vertical",
                    description: Text(inFolder ? "右上の + から作品を取り込み、ここに移動できます" : "右上の + から取り込み、フォルダで整理できます")
                )
            }
        }
        .sheet(isPresented: $showImportHub) {
            ImportHubView(library: library)
        }
        .sheet(item: $renameTarget) { volume in
            NavigationStack {
                Form {
                    TextField("タイトル", text: $renameText)
                }
                .navigationTitle("名前を変更")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { renameTarget = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            library.rename(volume, title: renameText)
                            renameTarget = nil
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $renameFolderTarget) { folder in
            NavigationStack {
                Form {
                    TextField("フォルダ名", text: $renameFolderText)
                }
                .navigationTitle("フォルダ名を変更")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { renameFolderTarget = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            library.renameFolder(folder, name: renameFolderText)
                            renameFolderTarget = nil
                        }
                        .disabled(renameFolderText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .alert("新しいフォルダ", isPresented: $showNewFolder) {
            TextField("フォルダ名", text: $newFolderName)
            Button("キャンセル", role: .cancel) {}
            Button("作成") {
                let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    _ = library.createFolder(name: name)
                }
            }
        } message: {
            Text("書庫をフォルダで分けて整理できます")
        }
        .confirmationDialog("フォルダへ移動", isPresented: Binding(
            get: { moveTarget != nil },
            set: { if !$0 { moveTarget = nil } }
        ), titleVisibility: .visible) {
            Button("未分類") {
                if let volume = moveTarget { library.move(volume, to: nil) }
                moveTarget = nil
            }
            ForEach(library.sortedFolders) { folder in
                Button(folder.name) {
                    if let volume = moveTarget { library.move(volume, to: folder.id) }
                    moveTarget = nil
                }
            }
            Button("キャンセル", role: .cancel) { moveTarget = nil }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    @ViewBuilder
    private func cover(for volume: MangaVolume) -> some View {
        Group {
            if let url = volume.coverURL(), let image = SampleImage.load(url: url) {
                image.resizable().scaledToFill()
            } else if let name = volume.coverFileName, let image = SampleImage.load(named: name) {
                image.resizable().scaledToFill()
            } else {
                Rectangle().fill(Color.secondary.opacity(0.3))
            }
        }
        .frame(width: 56, height: 84)
        .clipped()
        .cornerRadius(4)
    }
}
