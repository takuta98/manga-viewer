import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var volumes: [MangaVolume] = []
    @Published private(set) var folders: [LibraryFolder] = []
    @Published var sort: LibrarySort = AppSettingsStore.loadSort() {
        didSet { AppSettingsStore.saveSort(sort) }
    }
    @Published var currentFolderId: String?
    @Published private(set) var catalogLoadError: String?

    private let indexURL: URL
    private let foldersURL: URL
    private let fm = FileManager.default
    private var blockPersistence = false

    nonisolated static var libraryRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Library", isDirectory: true)
    }

    init() {
        indexURL = Self.libraryRoot.appendingPathComponent("index.json")
        foldersURL = Self.libraryRoot.appendingPathComponent("folders.json")
        try? fm.createDirectory(at: Self.libraryRoot, withIntermediateDirectories: true)
        load()
        ensureSample()
    }

    var sortedFolders: [LibraryFolder] {
        folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func volumes(in folderId: String?) -> [MangaVolume] {
        sortVolumes(volumes.filter { $0.folderId == folderId })
    }

    var sortedVolumes: [MangaVolume] {
        sortVolumes(volumes)
    }

    private func sortVolumes(_ list: [MangaVolume]) -> [MangaVolume] {
        switch sort {
        case .title:
            return list.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .progress:
            let prefs = AppSettingsStore.loadPrefs()
            return list.sorted {
                ProgressStore.shared.progressPercent(for: $0, coverAlone: prefs.coverAlone, layout: prefs.layoutMode)
                    > ProgressStore.shared.progressPercent(for: $1, coverAlone: prefs.coverAlone, layout: prefs.layoutMode)
            }
        case .recent:
            return list.sorted {
                ($0.lastOpenedAt ?? $0.importedAt) > ($1.lastOpenedAt ?? $1.importedAt)
            }
        }
    }

    func volumeCount(in folderId: String) -> Int {
        volumes.filter { $0.folderId == folderId }.count
    }

    @discardableResult
    func importURL(_ url: URL, folderId: String? = nil, titleOverride: String? = nil) throws -> MangaVolume {
        var volume = try MangaImporter.importFile(from: url, titleOverride: titleOverride)
        volume.folderId = folderId
        volumes.removeAll { $0.id == volume.id }
        volumes.insert(volume, at: 0)
        save()
        return volume
    }

    func delete(_ volume: MangaVolume) {
        volumes.removeAll { $0.id == volume.id }
        ProgressStore.shared.clear(for: volume.id)
        if !volume.isBundledSample {
            let root = URL(fileURLWithPath: volume.pagesDirectory).deletingLastPathComponent()
            try? fm.removeItem(at: root)
        }
        save()
    }

    func markOpened(_ volume: MangaVolume) {
        guard let idx = volumes.firstIndex(where: { $0.id == volume.id }) else { return }
        volumes[idx].lastOpenedAt = Date()
        save()
    }

    func updateDirection(_ volume: MangaVolume, direction: ReadingDirection) {
        guard let idx = volumes.firstIndex(where: { $0.id == volume.id }) else { return }
        volumes[idx].direction = direction
        save()
    }

    func rename(_ volume: MangaVolume, title: String) {
        guard let idx = volumes.firstIndex(where: { $0.id == volume.id }) else { return }
        volumes[idx].title = title
        save()
    }

    func move(_ volume: MangaVolume, to folderId: String?) {
        guard let idx = volumes.firstIndex(where: { $0.id == volume.id }) else { return }
        volumes[idx].folderId = folderId
        save()
    }

    @discardableResult
    func createFolder(name: String) -> LibraryFolder {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "無題のフォルダ" : trimmed
        if let existing = folders.first(where: { $0.name == finalName }) {
            return existing
        }
        let folder = LibraryFolder.make(name: finalName)
        folders.append(folder)
        saveFolders()
        return folder
    }

    /// 同名があれば再利用し、なければ作る。
    @discardableResult
    func folderForImport(named name: String) -> LibraryFolder {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "取り込み" : trimmed
        if let existing = folders.first(where: { $0.name.caseInsensitiveCompare(finalName) == .orderedSame }) {
            return existing
        }
        return createFolder(name: finalName)
    }

    func renameFolder(_ folder: LibraryFolder, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let idx = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[idx].name = trimmed
        saveFolders()
    }

    func deleteFolder(_ folder: LibraryFolder) {
        for i in volumes.indices where volumes[i].folderId == folder.id {
            volumes[i].folderId = nil
        }
        folders.removeAll { $0.id == folder.id }
        if currentFolderId == folder.id {
            currentFolderId = nil
        }
        save()
        saveFolders()
    }

    private func load() {
        catalogLoadError = nil
        blockPersistence = false

        if fm.fileExists(atPath: indexURL.path) {
            if let data = try? Data(contentsOf: indexURL),
               let decoded = try? JSONDecoder().decode([MangaVolume].self, from: data) {
                volumes = decoded
            } else {
                catalogLoadError = "書庫インデックスを読めませんでした。ファイルは消していません。"
                blockPersistence = true
                volumes = []
                return
            }
        } else {
            volumes = []
        }

        if fm.fileExists(atPath: foldersURL.path) {
            if let data = try? Data(contentsOf: foldersURL),
               let decoded = try? JSONDecoder().decode([LibraryFolder].self, from: data) {
                folders = decoded
            } else {
                catalogLoadError = (catalogLoadError ?? "") + " フォルダ一覧を読めませんでした。"
                // フォルダだけ壊れている場合は空にして、巻の folderId を正規化
                folders = []
            }
        } else {
            folders = []
        }

        let validFolderIDs = Set(folders.map(\.id))
        for i in volumes.indices {
            if let fid = volumes[i].folderId, !validFolderIDs.contains(fid) {
                volumes[i].folderId = nil
            }
        }
    }

    private func save() {
        guard !blockPersistence else { return }
        try? fm.createDirectory(at: Self.libraryRoot, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(volumes) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    private func saveFolders() {
        guard !blockPersistence else { return }
        try? fm.createDirectory(at: Self.libraryRoot, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(folders) {
            try? data.write(to: foldersURL, options: .atomic)
        }
    }

    private func ensureSample() {
        guard !blockPersistence else { return }
        guard !volumes.contains(where: { $0.isBundledSample }) else { return }
        // 既存 index があるのに空＝異常時はサンプルで上書きしない
        if fm.fileExists(atPath: indexURL.path), volumes.isEmpty, catalogLoadError != nil {
            return
        }
        let pages = (1...16).map { String(format: "sample-%03d", $0) }
        let sample = MangaVolume(
            id: "sample-bundled",
            title: "Sample",
            pagesDirectory: "",
            pageFileNames: pages,
            coverFileName: "sample-cover",
            direction: .rtl,
            isBundledSample: true,
            importedAt: Date.distantPast,
            lastOpenedAt: nil,
            folderId: nil
        )
        volumes.append(sample)
        save()
    }
}
