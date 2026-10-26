import SwiftUI

struct LibraryView: View {
    @ObservedObject var library: LibraryStore
    var onOpen: (MangaVolume) -> Void

    @State private var showImportHub = false
    @State private var renameTarget: MangaVolume?
    @State private var renameText = ""
    @State private var showSettings = false
    @State private var query = ""

    private var prefs: ReaderPreferences { AppSettingsStore.loadPrefs() }

    private var filtered: [MangaVolume] {
        let base = library.sortedVolumes
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }
        return base.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        List {
            ForEach(filtered) { volume in
                Button {
                    onOpen(volume)
                } label: {
                    HStack(spacing: 14) {
                        cover(for: volume)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(volume.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            let pct = ProgressStore.shared.progressPercent(
                                for: volume,
                                coverAlone: prefs.coverAlone,
                                layout: prefs.layoutMode
                            )
                            Text("\(volume.pageCount) pages · \(volume.direction.shortLabel) · \(pct > 0 ? "\(pct)%" : "未読")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
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
            }
        }
        .listStyle(.plain)
        .searchable(text: $query, prompt: "タイトル検索")
        .overlay {
            if library.volumes.isEmpty {
                ContentUnavailableView(
                    "書庫が空です",
                    systemImage: "books.vertical",
                    description: Text("右上の + から SMB / WebDAV / OPDS / Files などへ")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
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
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
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
