import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var volumes: [MangaVolume] = []
    @Published private(set) var folders: [LibraryFolder] = []
    @Published var sort: LibrarySort = AppSettingsStore.loadSort() {
        didSet { AppSettingsStore.saveSort(sort) }
    }
    @Published var currentFolderId: UUID?
    @Published var catalogLoadError: String?
    private var blockPersistence = false

    var sortedFolders: [LibraryFolder] {
        // 読書中のシリーズを先に、同ランクは最大進み％→しおり件数→名前
        folders.sorted { a, b in
            func stats(_ folder: LibraryFolder) -> (reading: Int, maxPct: Int, marks: Int) {
                var reading = 0
                var maxPct = 0
                var marks = 0
                for vol in volumes where vol.folderId == folder.id {
                    let pct = ProgressStore.shared.progressPercent(
                        for: vol, coverAlone: true, layout: .single
                    )
                    if pct > 0 && pct < 100 {
                        reading += 1
                        maxPct = max(maxPct, pct)
                    }
                    marks += ProgressStore.shared.bookmarks(for: vol.id).count
                }
                return (reading, maxPct, marks)
            }
            let sa = stats(a)
            let sb = stats(b)
            if (sa.reading > 0) != (sb.reading > 0) { return sa.reading > 0 }
            if sa.reading != sb.reading { return sa.reading > sb.reading }
            if sa.maxPct != sb.maxPct { return sa.maxPct > sb.maxPct }
            if sa.marks != sb.marks { return sa.marks > sb.marks }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    var sortedVolumes: [MangaVolume] {
        switch sort {
        case .recent: return volumes.sorted { $0.importedAt > $1.importedAt }
        case .title: return volumes.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .progress:
            // 続き → 未読 → 読了。同ランクは進み％降順 → しおり件数降順 → タイトル
            return volumes.sorted { a, b in
                func rank(_ v: MangaVolume) -> Int {
                    let pct = ProgressStore.shared.progressPercent(
                        for: v, coverAlone: true, layout: .single
                    )
                    if pct > 0 && pct < 100 { return 0 }
                    if pct == 0 { return 1 }
                    return 2
                }
                let ra = rank(a)
                let rb = rank(b)
                if ra != rb { return ra < rb }
                let pa = ProgressStore.shared.progressPercent(
                    for: a, coverAlone: true, layout: .single
                )
                let pb = ProgressStore.shared.progressPercent(
                    for: b, coverAlone: true, layout: .single
                )
                if pa != pb { return pa > pb }
                let ma = ProgressStore.shared.bookmarks(for: a.id).count
                let mb = ProgressStore.shared.bookmarks(for: b.id).count
                if ma != mb { return ma > mb }
                return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
        }
    }

    init() { load() }

    func volumes(in folderId: UUID?) -> [MangaVolume] {
        sortedVolumes.filter { $0.folderId == folderId }
    }

    func volumeCount(in folderId: UUID) -> Int {
        volumes.filter { $0.folderId == folderId }.count
    }

    func createFolder(name: String) -> LibraryFolder {
        let folder = LibraryFolder(id: UUID(), name: name, createdAt: Date())
        folders.append(folder)
        persist()
        return folder
    }

    func renameFolder(_ folder: LibraryFolder, name: String) {
        guard let i = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[i].name = name
        persist()
    }

    func deleteFolder(_ folder: LibraryFolder) {
        for i in volumes.indices where volumes[i].folderId == folder.id {
            volumes[i].folderId = nil
        }
        folders.removeAll { $0.id == folder.id }
        if currentFolderId == folder.id { currentFolderId = nil }
        persist()
    }

    func rename(_ volume: MangaVolume, title: String) {
        guard let i = volumes.firstIndex(where: { $0.id == volume.id }) else { return }
        volumes[i].title = UserFacingText.title(fromFileName: title)
        persist()
    }

    func move(_ volume: MangaVolume, to folderId: UUID?) {
        guard let i = volumes.firstIndex(where: { $0.id == volume.id }) else { return }
        volumes[i].folderId = folderId
        persist()
    }

    func updateDirection(_ volume: MangaVolume, direction: ReadingDirection) {
        guard let i = volumes.firstIndex(where: { $0.id == volume.id }) else { return }
        volumes[i].direction = direction
        persist()
    }

    func delete(_ volume: MangaVolume) {
        volumes.removeAll { $0.id == volume.id }
        try? FileManager.default.removeItem(at: Catalog.pagesDirectory(for: volume.directoryName))
        persist()
    }

    func detectDuplicate(title: String) -> MangaVolume? {
        volumes.first { $0.title == title }
    }

    @discardableResult
    func importURL(_ url: URL, folderId: UUID? = nil, titleOverride: String? = nil) throws -> MangaVolume {
        let title = titleOverride ?? UserFacingText.title(fromFileName: url.lastPathComponent)
        if detectDuplicate(title: title) != nil {
            throw NSError(
                domain: "LibraryStore",
                code: 409,
                userInfo: [NSLocalizedDescriptionKey: AppCopy.alreadyHave]
            )
        }
        let volume = try MangaImporter.importFile(at: url, title: title, folderId: folderId)
        volumes.insert(volume, at: 0)
        persist()
        return volume
    }

    func folderForImport(named name: String) -> LibraryFolder {
        if let existing = folders.first(where: { $0.name == name }) { return existing }
        return createFolder(name: name)
    }

    private struct Payload: Codable {
        var volumes: [MangaVolume]
        var folders: [LibraryFolder]
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: Catalog.libraryJSON.path) else {
            volumes = []
            folders = []
            return
        }
        do {
            let data = try Data(contentsOf: Catalog.libraryJSON)
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            volumes = payload.volumes.map { v in
                var copy = v
                copy.title = UserFacingText.title(fromFileName: v.title)
                return copy
            }
            folders = payload.folders
            catalogLoadError = nil
        } catch {
            blockPersistence = true
            catalogLoadError = AppCopy.libraryLoadFailed
        }
    }

    private func persist() {
        guard !blockPersistence else { return }
        let payload = Payload(volumes: volumes, folders: folders)
        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: Catalog.libraryJSON, options: .atomic)
        } catch {
            catalogLoadError = AppCopy.librarySaveFailed
        }
    }
}
