import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
    @ObservedObject var library: LibraryStore
    var onOpen: (MangaVolume) -> Void

    @State private var showImporter = false
    @State private var showNAS = false
    @State private var importError: String?

    var body: some View {
        Group {
            if library.sortedVolumes.isEmpty {
                ContentUnavailableView(
                    "作品がありません",
                    systemImage: "books.vertical",
                    description: Text("ファイルから CBZ / ZIP / 画像を追加してください。")
                )
            } else {
                List {
                    ForEach(library.sortedVolumes) { volume in
                        Button {
                            onOpen(volume)
                        } label: {
                            HStack(spacing: 12) {
                                cover(for: volume)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(volume.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text("\(volume.pageCount) ページ · \(ReadingProgress.shared.percent(for: volume))%")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Text("読む")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.tint)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(volume.title)、読む")
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if !volume.isBundledSample {
                                Button("削除", role: .destructive) {
                                    library.delete(volume)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("本棚")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showImporter = true
                    } label: {
                        Label("ファイルから", systemImage: "folder")
                    }
                    Button {
                        showNAS = true
                    } label: {
                        Label("NAS から入手", systemImage: "server.rack")
                    }
                } label: {
                    Label("作品を入手", systemImage: "plus")
                }
                .accessibilityLabel("作品を入手")
            }
        }
        .sheet(isPresented: $showNAS) {
            NASBrowserView(library: library)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: importTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    do {
                        try library.importURL(url)
                    } catch {
                        importError = error.localizedDescription
                    }
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .alert("取り込みに失敗しました", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("閉じる", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private var importTypes: [UTType] {
        var types: [UTType] = [.zip, .png, .jpeg, .gif, .heic, .webP, .image]
        if let cbz = UTType(filenameExtension: "cbz") {
            types.insert(cbz, at: 0)
        }
        return types
    }

    @ViewBuilder
    private func cover(for volume: MangaVolume) -> some View {
        Group {
            if let url = volume.coverURL(),
               let image = UIImage(contentsOfFile: url.path)
                ?? Bundle.main.url(
                    forResource: "sample-cover",
                    withExtension: "png",
                    subdirectory: "SampleManga/sample"
                ).flatMap({ UIImage(contentsOfFile: $0.path) })
            {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray.opacity(0.25)
                    .overlay(Image(systemName: "book.closed").foregroundStyle(.secondary))
            }
        }
        .frame(width: 48, height: 72)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
