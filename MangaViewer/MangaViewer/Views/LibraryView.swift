import SwiftUI
import UniformTypeIdentifiers

/// 本棚。フォルダーと表紙のグリッド。タップで開く。
struct LibraryView: View {
    @ObservedObject var library: LibraryStore
    let onRead: (MangaVolume) -> Void

    @State private var showImporter = false
    @State private var showNAS = false
    @State private var importError: String?
    @State private var query = ""

    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var folderTarget: MangaVolume?
    @State private var renameTarget: String?
    @State private var renameText = ""
    @State private var folderDeleteTarget: String?
    @State private var showDownloads = false

    // 複数選択
    @State private var selecting = false
    @State private var selected = Set<UUID>()
    @State private var bulkMove = false
    @State private var bulkDelete = false
    @State private var bulkNewFolder = false
    @AppStorage("library.sortByTitle") private var sortByTitle = false

    private var importTypes: [UTType] {
        var types: [UTType] = [.zip, .png, .jpeg, .gif, .heic, .webP, .image]
        if let cbz = UTType(filenameExtension: "cbz") {
            types.append(cbz)
        }
        return types
    }

    private var needle: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    /// ルートに並べるフォルダー。並びは名前順で安定させる。
    private var shownFolders: [String] {
        let list = needle.isEmpty
            ? library.folders
            : library.folders.filter { $0.localizedCaseInsensitiveContains(needle) }
        return list.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// ルートに並べる巻。検索中はフォルダーの中も含めて全部探す。
    private var shownVolumes: [MangaVolume] {
        let list: [MangaVolume]
        if needle.isEmpty {
            list = library.volumes.filter { $0.folder == nil }
        } else {
            list = library.volumes.filter {
                $0.title.localizedCaseInsensitiveContains(needle)
            }
        }
        if sortByTitle {
            return list.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
        return list
    }

    /// 選択モードでタップされた巻の選択を切り替える。
    private func toggleSelect(_ volume: MangaVolume) {
        if selected.contains(volume.id) {
            selected.remove(volume.id)
        } else {
            selected.insert(volume.id)
        }
    }

    /// 選んだ巻をまとめてフォルダーへ入れて選択を解除する。
    private func moveSelected(to folder: String) {
        for id in selected {
            if let volume = library.volumes.first(where: { $0.id == id }) {
                library.move(volume, toFolder: folder)
            }
        }
        selected = []
        selecting = false
        bulkMove = false
    }

    var body: some View {
        Group {
            if library.volumes.isEmpty && library.folders.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 160), spacing: 16)],
                        spacing: 22
                    ) {
                        ForEach(shownFolders, id: \.self) { name in
                            folderCard(name)
                        }
                        ForEach(shownVolumes) { volume in
                            VolumeCard(
                                library: library,
                                volume: volume,
                                onRead: onRead,
                                onMove: { folderTarget = volume },
                                showFolderBadge: !needle.isEmpty,
                                selecting: selecting,
                                isSelected: selected.contains(volume.id),
                                onToggleSelect: { toggleSelect(volume) }
                            )
                        }
                    }
                    .padding(18)

                    Text("build 2026-10-28c")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 12)
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("本棚")
        .searchable(text: $query, prompt: "タイトルで検索")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if selecting {
                    Button("やめる") {
                        selecting = false
                        selected = []
                    }
                } else {
                    HStack(spacing: 16) {
                        Button { showDownloads = true } label: {
                            Image(systemName: "arrow.down.circle")
                        }
                        .accessibilityLabel("ダウンロード進捗")
                        Button("選択") {
                            selecting = true
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !selecting {
                    HStack(spacing: 16) {
                        Menu {
                            Button("追加順") { sortByTitle = false }
                            Button("タイトル順") { sortByTitle = true }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        .accessibilityLabel("並び替え")
                        importMenu
                    }
                }
            }
        }
        .navigationDestination(for: String.self) { name in
            LibraryFolderView(library: library, name: name, onRead: onRead)
        }
        .overlay {
            if !library.volumes.isEmpty,
               !needle.isEmpty,
               shownVolumes.isEmpty,
               shownFolders.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationDestination(isPresented: $showDownloads) {
            DownloadsView(library: library)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: importTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                var succeeded = 0
                var lastError: String?
                for url in urls {
                    do {
                        _ = try library.importURL(url)
                        succeeded += 1
                    } catch {
                        lastError = error.localizedDescription
                    }
                }
                if succeeded == 0, let lastError {
                    importError = lastError
                }
            }
        }
        // カード表示だと外タップで閉じてしまうのでフルスクリーンにする
        .fullScreenCover(isPresented: $showNAS) {
            NASBrowserView(library: library)
        }
        .alert("取り込みに失敗しました", isPresented: .constant(importError != nil)) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .alert("フォルダーを作る", isPresented: $showNewFolder) {
            TextField("フォルダー名", text: $newFolderName)
            Button("作成") {
                library.createFolder(newFolderName)
                if bulkNewFolder {
                    moveSelected(to: newFolderName.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                newFolderName = ""
                bulkNewFolder = false
            }
            Button("キャンセル", role: .cancel) {
                newFolderName = ""
                bulkNewFolder = false
            }
        }
        .alert("フォルダー名を変える", isPresented: .constant(renameTarget != nil)) {
            TextField("フォルダー名", text: $renameText)
            Button("変更") {
                if let old = renameTarget {
                    library.renameFolder(old, to: renameText)
                }
                renameTarget = nil
                renameText = ""
            }
            Button("キャンセル", role: .cancel) {
                renameTarget = nil
                renameText = ""
            }
        }
        .alert("フォルダーを削除しますか？", isPresented: .constant(folderDeleteTarget != nil)) {
            Button("削除", role: .destructive) {
                if let name = folderDeleteTarget {
                    library.deleteFolder(name)
                }
                folderDeleteTarget = nil
            }
            Button("キャンセル", role: .cancel) { folderDeleteTarget = nil }
        } message: {
            Text("中の巻は消えずに本棚へ戻ります")
        }
        .alert("\(selected.count) 冊をフォルダーへ移動", isPresented: $bulkMove) {
            ForEach(library.folders, id: \.self) { name in
                Button(name) {
                    moveSelected(to: name)
                }
            }
            Button("新しいフォルダー") {
                bulkNewFolder = true
                showNewFolder = true
            }
            Button("キャンセル", role: .cancel) { bulkMove = false }
        }
        .alert("\(selected.count) 冊を削除しますか？", isPresented: $bulkDelete) {
            Button("削除", role: .destructive) {
                for id in selected {
                    if let volume = library.volumes.first(where: { $0.id == id }),
                       !volume.isBundledSample {
                        library.delete(volume)
                    }
                }
                selected = []
                selecting = false
                bulkDelete = false
            }
            Button("キャンセル", role: .cancel) { bulkDelete = false }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                HStack(spacing: 0) {
                    Button("すべて選ぶ") {
                        selected = Set(shownVolumes.map(\.id))
                    }
                    Spacer()
                    Button("フォルダーへ移動") { bulkMove = true }
                        .disabled(selected.isEmpty)
                    Spacer()
                    Button("削除", role: .destructive) { bulkDelete = true }
                        .disabled(selected.isEmpty)
                }
                .font(.callout)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
        .alert("フォルダーへ移動", isPresented: .constant(folderTarget != nil)) {
            if let target = folderTarget {
                ForEach(library.folders, id: \.self) { name in
                    Button(name) {
                        library.move(target, toFolder: name)
                        folderTarget = nil
                    }
                }
                Button("フォルダーから出す") {
                    library.move(target, toFolder: nil)
                    folderTarget = nil
                }
                Button("キャンセル", role: .cancel) { folderTarget = nil }
            }
        } message: {
            Text(folderTarget?.title ?? "")
        }
    }

    // MARK: - フォルダーカード

    private func folderCard(_ name: String) -> some View {
        let count = library.volumes.filter { $0.folder == name }.count
        return NavigationLink(value: name) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    Image(systemName: "folder.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.tint)
                }
                .aspectRatio(2 / 3, contentMode: .fit)
                .frame(maxWidth: .infinity)

                Text(name)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Text("\(count) 冊")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("名前を変える", systemImage: "pencil") {
                renameTarget = name
                renameText = name
            }
            Button("フォルダーを削除", systemImage: "trash", role: .destructive) {
                folderDeleteTarget = name
            }
        }
    }

    // MARK: - 入手

    private var importMenu: some View {
        Menu {
            Button {
                showImporter = true
            } label: {
                Label("ファイルから追加", systemImage: "doc.badge.plus")
            }
            // 入手元はここに並べる。Google ドライブ・iCloud はここに追加する。
            Section("サーバー・クラウド") {
                Button {
                    showNAS = true
                } label: {
                    Label("SMB サーバー", systemImage: "externaldrive.connected.to.line.below")
                }
            }
            Divider()
            Button {
                showNewFolder = true
            } label: {
                Label("フォルダーを作る", systemImage: "folder.badge.plus")
            }
        } label: {
            Label("作品を入手", systemImage: "plus")
        }
        .accessibilityLabel("作品を入手")
    }

    // MARK: - 空の本棚

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "books.vertical")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("本棚は空です")
                .font(.headline)
            VStack(spacing: 10) {
                Button { showNAS = true } label: {
                    Label("SMB サーバー", systemImage: "externaldrive.connected.to.line.below")
                        .frame(maxWidth: 240)
                }
                .buttonStyle(.borderedProminent)
                Button { showImporter = true } label: {
                    Label("ファイルから追加", systemImage: "doc.badge.plus")
                        .frame(maxWidth: 240)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// フォルダーの中。巻のグリッドだけ。巻数順に並べる。
struct LibraryFolderView: View {
    @ObservedObject var library: LibraryStore
    let name: String
    let onRead: (MangaVolume) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var folderTarget: MangaVolume?
    @State private var selecting = false
    @State private var selected = Set<UUID>()
    @State private var bulkMove = false
    @State private var bulkDelete = false
    @State private var bulkNewFolder = false
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var query = ""
    @State private var renaming = false
    @State private var renameText = ""
    @State private var confirmDelete = false

    private var needle: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// シリーズの巻はタイトル順（数字は数値として）が自然。
    private var volumes: [MangaVolume] {
        library.volumes
            .filter { $0.folder == name }
            .filter {
                needle.isEmpty || $0.title.localizedCaseInsensitiveContains(needle)
            }
            .sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    private func toggleSelect(_ volume: MangaVolume) {
        if selected.contains(volume.id) {
            selected.remove(volume.id)
        } else {
            selected.insert(volume.id)
        }
    }

    private func moveSelected(to folder: String?) {
        for id in selected {
            if let volume = library.volumes.first(where: { $0.id == id }) {
                library.move(volume, toFolder: folder)
            }
        }
        selected = []
        selecting = false
        bulkMove = false
    }

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: 16)],
                spacing: 22
            ) {
                ForEach(volumes) { volume in
                    VolumeCard(
                        library: library,
                        volume: volume,
                        onRead: onRead,
                        onMove: { folderTarget = volume },
                        selecting: selecting,
                        isSelected: selected.contains(volume.id),
                        onToggleSelect: { toggleSelect(volume) }
                    )
                }
            }
            .padding(18)
        }
        .navigationTitle(name)
        .searchable(text: $query, prompt: "このフォルダーの中を検索")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if selecting {
                    Button("やめる") {
                        selecting = false
                        selected = []
                    }
                } else {
                    HStack(spacing: 16) {
                        Button("選択") { selecting = true }
                        Menu {
                            Button("名前を変える", systemImage: "pencil") {
                                renameText = name
                                renaming = true
                            }
                            Button("フォルダーを削除", systemImage: "trash", role: .destructive) {
                                confirmDelete = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .overlay {
            if volumes.isEmpty {
                if !needle.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ContentUnavailableView("巻がありません", systemImage: "folder")
                }
            }
        }
        .alert("フォルダー名を変える", isPresented: $renaming) {
            TextField("フォルダー名", text: $renameText)
            Button("変更") {
                library.renameFolder(name, to: renameText)
                dismiss()
            }
            Button("キャンセル", role: .cancel) { renameText = "" }
        }
        .alert("フォルダーを削除しますか？", isPresented: $confirmDelete) {
            Button("削除", role: .destructive) {
                library.deleteFolder(name)
                dismiss()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("中の巻は消えずに本棚へ戻ります")
        }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                HStack(spacing: 0) {
                    Button("すべて選ぶ") {
                        selected = Set(volumes.map(\.id))
                    }
                    Spacer()
                    Button("フォルダーへ移動") { bulkMove = true }
                        .disabled(selected.isEmpty)
                    Spacer()
                    Button("削除", role: .destructive) { bulkDelete = true }
                        .disabled(selected.isEmpty)
                }
                .font(.callout)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
        .alert("\(selected.count) 冊をフォルダーへ移動", isPresented: $bulkMove) {
            ForEach(library.folders, id: \.self) { other in
                if other != name {
                    Button(other) { moveSelected(to: other) }
                }
            }
            Button("本棚へ戻す") { moveSelected(to: nil) }
            Button("新しいフォルダー") {
                bulkNewFolder = true
                showNewFolder = true
            }
            Button("キャンセル", role: .cancel) { bulkMove = false }
        }
        .alert("\(selected.count) 冊を削除しますか？", isPresented: $bulkDelete) {
            Button("削除", role: .destructive) {
                for id in selected {
                    if let volume = library.volumes.first(where: { $0.id == id }),
                       !volume.isBundledSample {
                        library.delete(volume)
                    }
                }
                selected = []
                selecting = false
                bulkDelete = false
            }
            Button("キャンセル", role: .cancel) { bulkDelete = false }
        }
        .alert("フォルダーを作る", isPresented: $showNewFolder) {
            TextField("フォルダー名", text: $newFolderName)
            Button("作成") {
                library.createFolder(newFolderName)
                if let target = folderTarget {
                    library.move(
                        target,
                        toFolder: newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    folderTarget = nil
                } else if bulkNewFolder {
                    moveSelected(to: newFolderName.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                newFolderName = ""
                bulkNewFolder = false
            }
            Button("キャンセル", role: .cancel) {
                newFolderName = ""
                bulkNewFolder = false
            }
        }
        .alert("フォルダーへ移動", isPresented: .constant(folderTarget != nil)) {
            if let target = folderTarget {
                ForEach(library.folders, id: \.self) { other in
                    if other != name {
                        Button(other) {
                            library.move(target, toFolder: other)
                            folderTarget = nil
                        }
                    }
                }
                Button("フォルダーから出す") {
                    library.move(target, toFolder: nil)
                    folderTarget = nil
                }
                Button("新しいフォルダー") {
                    showNewFolder = true
                }
                Button("キャンセル", role: .cancel) { folderTarget = nil }
            }
        } message: {
            Text(folderTarget?.title ?? "")
        }
    }
}

/// 巻カード。本棚のルートでもフォルダー内でも使う。
struct VolumeCard: View {
    @ObservedObject var library: LibraryStore
    let volume: MangaVolume
    let onRead: (MangaVolume) -> Void
    /// 渡すとコンテキストメニューに「フォルダーへ移動」が出る。
    var onMove: (() -> Void)? = nil
    /// 検索結果など、どのフォルダーに入っているか見せたいときに true。
    var showFolderBadge = false
    /// 選択モード中はタップで選択切替になる。
    var selecting = false
    var isSelected = false
    var onToggleSelect: (() -> Void)? = nil

    @State private var confirmDelete = false
    @State private var renaming = false
    @State private var renameText = ""

    private let progress = ReadingProgress.shared

    var body: some View {
        Button {
            if selecting {
                onToggleSelect?()
            } else {
                onRead(volume)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                cover
                    .resizable()
                    .scaledToFill()
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(alignment: .bottom) { progressBar }
                    .overlay(alignment: .topTrailing) {
                        if selecting {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isSelected ? .blue : .white)
                                .shadow(radius: 2)
                                .padding(6)
                        }
                    }
                    .overlay {
                        if selecting && isSelected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.blue, lineWidth: 3)
                        }
                    }

                Text(volume.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                if showFolderBadge, let folder = volume.folder {
                    Label(folder, systemImage: "folder")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("\(volume.pageCount) ページ")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(volume.title) を読む")
        .contextMenu {
            Button("読む", systemImage: "book") { onRead(volume) }
            Button("名前を変える", systemImage: "pencil") {
                renameText = volume.title
                renaming = true
            }
            Button("最初から読む", systemImage: "arrow.counterclockwise") {
                progress.clear(for: volume.id)
            }
            Menu {
                ForEach(ReadingDirection.allCases) { d in
                    Button(d.label) { library.updateDirection(volume, direction: d) }
                }
            } label: {
                Label("開き方向", systemImage: "arrow.left.arrow.right")
            }
            if let onMove {
                Button("フォルダーへ移動", systemImage: "folder") { onMove() }
            }
            if volume.folder != nil {
                Button("フォルダーから出す", systemImage: "arrow.uturn.backward") {
                    library.move(volume, toFolder: nil)
                }
            }
            if !volume.isBundledSample {
                Button("削除", systemImage: "trash", role: .destructive) {
                    confirmDelete = true
                }
            }
        }
        .alert("削除しますか？", isPresented: $confirmDelete) {
            Button("削除", role: .destructive) { library.delete(volume) }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text(volume.title)
        }
        .alert("名前を変える", isPresented: $renaming) {
            TextField("タイトル", text: $renameText)
            Button("変更") {
                library.rename(volume, to: renameText)
                renameText = ""
            }
            Button("キャンセル", role: .cancel) { renameText = "" }
        }
    }

    private var cover: Image {
        if let url = volume.coverURL(),
           let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            return Image(uiImage: uiImage)
        }
        return Image("sample-cover")
    }

    private var progressBar: some View {
        let fraction = progress.fraction(for: volume)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.black.opacity(0.001)
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: max(geo.size.width * fraction, 4), height: 3)
                    .padding(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 11)
        .opacity(fraction > 0 ? 1 : 0)
        .allowsHitTesting(false)
    }
}
