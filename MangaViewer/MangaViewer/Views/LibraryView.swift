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

    private let progress = ReadingProgress.shared

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

    /// ルートに並べるフォルダー。
    private var shownFolders: [String] {
        if needle.isEmpty { return library.folders }
        return library.folders.filter { $0.localizedCaseInsensitiveContains(needle) }
    }

    /// ルートに並べる巻（フォルダー無し）。
    private var shownVolumes: [MangaVolume] {
        let root = library.volumes.filter { $0.folder == nil }
        guard !needle.isEmpty else { return root }
        return root.filter { $0.title.localizedCaseInsensitiveContains(needle) }
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
                            volumeCard(volume)
                        }
                    }
                    .padding(18)

                    Text("build 71eb219")
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
            ToolbarItem(placement: .topBarTrailing) { importMenu }
        }
        .navigationDestination(for: String.self) { name in
            LibraryFolderView(library: library, name: name, onRead: onRead)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: importTypes
        ) { result in
            if case .success(let url) = result {
                do { _ = try library.importURL(url) }
                catch { importError = error.localizedDescription }
            }
        }
        .sheet(isPresented: $showNAS) {
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
                newFolderName = ""
            }
            Button("キャンセル", role: .cancel) { newFolderName = "" }
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
        NavigationLink(value: name) {
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
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("フォルダーを削除", systemImage: "trash", role: .destructive) {
                library.deleteFolder(name)
            }
        }
    }

    // MARK: - 巻カード

    private func volumeCard(_ volume: MangaVolume) -> some View {
        Button { onRead(volume) } label: {
            VStack(alignment: .leading, spacing: 6) {
                cover(for: volume)
                    .resizable()
                    .scaledToFill()
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(alignment: .bottom) { progressBar(volume) }

                Text(volume.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(volume.title) を読む")
        .contextMenu {
            Button("読む", systemImage: "book") { onRead(volume) }
            Button("フォルダーへ移動", systemImage: "folder") { folderTarget = volume }
            if !volume.isBundledSample {
                Button("削除", systemImage: "trash", role: .destructive) {
                    library.delete(volume)
                }
            }
        }
    }

    private func cover(for volume: MangaVolume) -> Image {
        if let url = volume.coverURL(),
           let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            return Image(uiImage: uiImage)
        }
        return Image("sample-cover")
    }

    private func progressBar(_ volume: MangaVolume) -> some View {
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

/// フォルダーの中。巻のグリッドだけ。
struct LibraryFolderView: View {
    @ObservedObject var library: LibraryStore
    let name: String
    let onRead: (MangaVolume) -> Void

    private var volumes: [MangaVolume] {
        library.volumes.filter { $0.folder == name }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: 16)],
                spacing: 22
            ) {
                ForEach(volumes) { volume in
                    VolumeCard(library: library, volume: volume, onRead: onRead)
                }
            }
            .padding(18)
        }
        .navigationTitle(name)
        .overlay {
            if volumes.isEmpty {
                ContentUnavailableView("巻がありません", systemImage: "folder")
            }
        }
    }
}

/// 巻カード（フォルダー内でも共用）。
struct VolumeCard: View {
    @ObservedObject var library: LibraryStore
    let volume: MangaVolume
    let onRead: (MangaVolume) -> Void

    private let progress = ReadingProgress.shared

    var body: some View {
        Button { onRead(volume) } label: {
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

                Text(volume.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(volume.title) を読む")
        .contextMenu {
            Button("読む", systemImage: "book") { onRead(volume) }
            Button("フォルダーから出す", systemImage: "folder") {
                library.move(volume, toFolder: nil)
            }
            if !volume.isBundledSample {
                Button("削除", systemImage: "trash", role: .destructive) {
                    library.delete(volume)
                }
            }
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
