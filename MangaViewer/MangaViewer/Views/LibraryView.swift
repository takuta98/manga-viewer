import SwiftUI

struct LibraryView: View {
    @ObservedObject var library: LibraryStore
    var onOpen: (MangaVolume) -> Void

    @ObservedObject private var activity = TransferActivityCenter.shared
    @State private var showImportHub = false
    @State private var showTransfers = false
    @State private var renameTarget: MangaVolume?
    @State private var renameText = ""
    @State private var showSettings = false
    @State private var query = ""
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var renameFolderTarget: LibraryFolder?
    @State private var renameFolderText = ""
    @State private var moveTarget: MangaVolume?
    @State private var infoTarget: MangaVolume?
    @State private var folderPendingDelete: LibraryFolder?
    @State private var volumePendingDelete: MangaVolume?
    @State private var displayMode: LibraryDisplayMode = AppSettingsStore.loadLibraryDisplayMode()

    private var prefs: ReaderPreferences { AppSettingsStore.loadPrefs() }

    private var inFolder: Bool { library.currentFolderId != nil }

    private var currentFolder: LibraryFolder? {
        guard let id = library.currentFolderId else { return nil }
        return library.folders.first { $0.id == id }
    }

    private var searchingAcrossFolders: Bool {
        !inFolder && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displayedVolumes: [MangaVolume] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // At library root with a query: search unfiled volumes and those inside folders.
        if searchingAcrossFolders {
            return library.sortedVolumes.filter { $0.title.localizedCaseInsensitiveContains(q) }
        }
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

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 110), spacing: 14)]
    }

    private func folderSubtitle(for volume: MangaVolume) -> String? {
        guard searchingAcrossFolders, let folderId = volume.folderId else { return nil }
        return library.folders.first { $0.id == folderId }?.name
    }

    private func progressPercent(for volume: MangaVolume) -> Int {
        ProgressStore.shared.progressPercent(
            for: volume,
            coverAlone: prefs.coverAlone,
            layout: prefs.layoutMode
        )
    }

    private func openFromBeginning(_ volume: MangaVolume) {
        ProgressStore.shared.setSpreadIndex(0, for: volume.id)
        onOpen(volume)
    }

    var body: some View {
        Group {
            if displayMode == .grid {
                gridContent
            } else {
                listContent
            }
        }
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
            ToolbarItemGroup(placement: .topBarLeading) {
                if inFolder {
                    Button {
                        library.currentFolderId = nil
                    } label: {
                        Label("書庫", systemImage: "chevron.left")
                    }
                }
                Menu {
                    Picker("並び替え", selection: $library.sort) {
                        ForEach(LibrarySort.allCases) { sort in
                            Text(sort.label).tag(sort)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                Button {
                    displayMode = displayMode.toggled
                    AppSettingsStore.saveLibraryDisplayMode(displayMode)
                } label: {
                    Image(systemName: displayMode.toggled.systemImage)
                }
                .accessibilityLabel(displayMode == .list ? "グリッド表示" : "リスト表示")
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
                    Button { showTransfers = true } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "arrow.down.circle")
                            if activity.activeCount > 0 {
                                Text("\(activity.activeCount)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .background(Circle().fill(Color.red))
                                    .offset(x: 8, y: -8)
                            }
                        }
                    }
                    .accessibilityLabel("転送状況")
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
        .sheet(isPresented: $showTransfers) {
            TransferStatusView()
        }
        .sheet(item: $infoTarget) { volume in
            VolumeInfoView(volume: volume)
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
        .alert("フォルダを削除", isPresented: Binding(
            get: { folderPendingDelete != nil },
            set: { if !$0 { folderPendingDelete = nil } }
        ), presenting: folderPendingDelete) { folder in
            Button("キャンセル", role: .cancel) { folderPendingDelete = nil }
            Button("削除", role: .destructive) {
                library.deleteFolder(folder)
                folderPendingDelete = nil
            }
        } message: { folder in
            Text("「\(folder.name)」を削除します。フォルダ内の作品は未分類に移されます。")
        }
        .alert("作品を削除", isPresented: Binding(
            get: { volumePendingDelete != nil },
            set: { if !$0 { volumePendingDelete = nil } }
        ), presenting: volumePendingDelete) { volume in
            Button("キャンセル", role: .cancel) { volumePendingDelete = nil }
            Button("削除", role: .destructive) {
                library.delete(volume)
                volumePendingDelete = nil
            }
        } message: { volume in
            Text("「\(volume.title)」を削除します。この操作は取り消せません。")
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
        .onAppear {
            TransferActivityCenter.requestNotificationPermissionOnce()
        }
    }

    private var listContent: some View {
        List {
            if !inFolder {
                ForEach(displayedFolders) { folder in
                    folderListRow(folder)
                }
            }
            ForEach(displayedVolumes) { volume in
                volumeListRow(volume)
            }
        }
        .listStyle(.plain)
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                if !inFolder {
                    ForEach(displayedFolders) { folder in
                        folderGridCell(folder)
                    }
                }
                ForEach(displayedVolumes) { volume in
                    volumeGridCell(volume)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func folderListRow(_ folder: LibraryFolder) -> some View {
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
        .contextMenu { folderContextMenu(folder) }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                folderPendingDelete = folder
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
    }

    private func volumeListRow(_ volume: MangaVolume) -> some View {
        let pct = progressPercent(for: volume)
        return Button {
            onOpen(volume)
        } label: {
            HStack(spacing: 14) {
                cover(for: volume, width: 56, height: 84)
                VStack(alignment: .leading, spacing: 6) {
                    Text(volume.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if let folderName = folderSubtitle(for: volume) {
                        Text(folderName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(volume.pageCount) ページ · \(volume.direction.shortLabel)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(pct), total: 100)
                        .tint(pct >= 100 ? .green : .accentColor)
                    volumeProgressStatus(pct: pct, caption: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
        .contextMenu { volumeContextMenu(volume) }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                        volumePendingDelete = volume
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

    private func folderGridCell(_ folder: LibraryFolder) -> some View {
        Button {
            library.currentFolderId = folder.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.yellow.opacity(0.18))
                    Image(systemName: "folder.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow.opacity(0.9))
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(2 / 3, contentMode: .fit)
                Text(folder.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("\(library.volumeCount(in: folder.id)) 冊")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contextMenu { folderContextMenu(folder) }
    }

    private func volumeGridCell(_ volume: MangaVolume) -> some View {
        let pct = progressPercent(for: volume)
        return Button {
            onOpen(volume)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                cover(for: volume, width: nil, height: nil)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .clipped()
                    .cornerRadius(6)
                Text(volume.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let folderName = folderSubtitle(for: volume) {
                    Text(folderName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                volumeProgressStatus(pct: pct, caption: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contextMenu { volumeContextMenu(volume) }
    }

    /// 進捗表示。100% 以上は明確な「読了」バッジ。
    @ViewBuilder
    private func volumeProgressStatus(pct: Int, caption: Bool) -> some View {
        if pct >= 100 {
            Text("読了")
                .font((caption ? Font.caption : Font.caption2).weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.green.opacity(0.85)))
                .accessibilityLabel("読了")
        } else {
            HStack(spacing: caption ? 6 : 4) {
                if pct > 0 {
                    Text("続きから")
                        .font(caption ? .caption.weight(.semibold) : .caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                Text(pct > 0 ? "\(pct)%" : "未読")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func folderContextMenu(_ folder: LibraryFolder) -> some View {
        Button("名前を変更") {
            renameFolderTarget = folder
            renameFolderText = folder.name
        }
        Button("削除", role: .destructive) {
            folderPendingDelete = folder
        }
    }

    @ViewBuilder
    private func volumeContextMenu(_ volume: MangaVolume) -> some View {
        Button("最初から読む") {
            openFromBeginning(volume)
        }
        Button("情報") {
            infoTarget = volume
        }
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
            volumePendingDelete = volume
        }
    }

    @ViewBuilder
    private func cover(for volume: MangaVolume, width: CGFloat?, height: CGFloat?) -> some View {
        Group {
            if let url = volume.coverURL(), let image = SampleImage.load(url: url) {
                image.resizable().scaledToFill()
            } else if let name = volume.coverFileName, let image = SampleImage.load(named: name) {
                image.resizable().scaledToFill()
            } else {
                Rectangle().fill(Color.secondary.opacity(0.3))
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .cornerRadius(4)
    }
}
