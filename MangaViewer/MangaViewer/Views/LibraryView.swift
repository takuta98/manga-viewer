import SwiftUI
import UniformTypeIdentifiers

/// 本棚。表紙だけのグリッド。タップでその巻を開く。
struct LibraryView: View {
    @ObservedObject var library: LibraryStore
    let onRead: (MangaVolume) -> Void

    @State private var showImporter = false
    @State private var showNAS = false
    @State private var importError: String?

    private let progress = ReadingProgress.shared

    private var importTypes: [UTType] {
        var types: [UTType] = [.zip, .png, .jpeg, .gif, .heic, .webP, .image]
        if let cbz = UTType(filenameExtension: "cbz") {
            types.append(cbz)
        }
        return types
    }

    var body: some View {
        Group {
            if library.volumes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 108), spacing: 14)],
                        spacing: 18
                    ) {
                        ForEach(library.volumes) { volume in
                            volumeCard(volume)
                        }
                    }
                    .padding(18)
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("本棚")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { importMenu }
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
    }

    // MARK: - 巻カード

    private func volumeCard(_ volume: MangaVolume) -> some View {
        Button { onRead(volume) } label: {
            VStack(alignment: .leading, spacing: 6) {
                cover(for: volume)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
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
            Button {
                showNAS = true
            } label: {
                Label("NAS から入手", systemImage: "externaldrive.connected.to.line.below")
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
                    Label("NAS から入手", systemImage: "externaldrive.connected.to.line.below")
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
