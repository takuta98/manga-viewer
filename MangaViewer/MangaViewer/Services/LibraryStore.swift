import Combine
import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    static let sampleID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

    @Published private(set) var volumes: [MangaVolume] = []
    @Published private(set) var folders: [String] = []
    @Published var loadError: String?
    private var blockSave = false

    init() {
        load()
        ensureSample()
    }

    // MARK: - フォルダー

    func createFolder(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !folders.contains(name) else { return }
        folders.append(name)
        save()
    }

    /// フォルダーの名前を変える。中の巻の所属も追従する。
    func renameFolder(_ name: String, to newName: String) {
        let newName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != name, !folders.contains(newName) else { return }
        if let i = folders.firstIndex(of: name) {
            folders[i] = newName
        }
        for i in volumes.indices where volumes[i].folder == name {
            volumes[i].folder = newName
        }
        save()
    }

    /// フォルダーを消す。中の巻はフォルダー無しに戻る（巻自体は消さない）。
    func deleteFolder(_ name: String) {
        folders.removeAll { $0 == name }
        for i in volumes.indices where volumes[i].folder == name {
            volumes[i].folder = nil
        }
        save()
    }

    /// 巻をフォルダーへ入れる。nil でフォルダーから出す。
    func move(_ volume: MangaVolume, toFolder name: String?) {
        guard let i = volumes.firstIndex(where: { $0.id == volume.id }) else { return }
        volumes[i].folder = name
        save()
    }

    func updateDirection(_ volume: MangaVolume, direction: ReadingDirection) {
        guard let i = volumes.firstIndex(where: { $0.id == volume.id }) else { return }
        volumes[i].direction = direction
        save()
    }

    func delete(_ volume: MangaVolume) {
        volumes.removeAll { $0.id == volume.id }
        if !volume.isBundledSample {
            try? FileManager.default.removeItem(at: LibraryPaths.volumeDirectory(volume.directoryName))
        }
        ReadingProgress.shared.clear(for: volume.id)
        save()
    }

    /// フォルダー内の画像をまとめて1巻にする（NAS フォルダーDL 用）。
    @discardableResult
    func importImageDirectory(_ url: URL, title: String) throws -> MangaVolume {
        let volume = try VolumeImporter.importImageDirectory(at: url, titleHint: title)
        volumes.insert(volume, at: 0)
        save()
        return volume
    }

    @discardableResult
    func importURL(_ url: URL) throws -> MangaVolume {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let volume = try VolumeImporter.importFile(at: url, titleHint: url.lastPathComponent)
        volumes.insert(volume, at: 0)
        save()
        return volume
    }

    private struct Catalog: Codable {
        var volumes: [MangaVolume]
        var folders: [String]

        init(volumes: [MangaVolume], folders: [String]) {
            self.volumes = volumes
            self.folders = folders
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            volumes = try c.decode([MangaVolume].self, forKey: .volumes)
            folders = try c.decodeIfPresent([String].self, forKey: .folders) ?? []
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: LibraryPaths.catalogURL.path) else {
            volumes = []
            folders = []
            return
        }
        do {
            let data = try Data(contentsOf: LibraryPaths.catalogURL)
            let catalog = try JSONDecoder().decode(Catalog.self, from: data)
            volumes = catalog.volumes.map { volume in
                var copy = volume
                copy.title = TitleCleaner.clean(volume.title)
                return copy
            }
            folders = catalog.folders
            loadError = nil
        } catch {
            blockSave = true
            loadError = "本棚の読み込みに失敗しました。既存データは上書きしていません。"
        }
    }

    private func save() {
        guard !blockSave else { return }
        do {
            let data = try JSONEncoder().encode(Catalog(volumes: volumes, folders: folders))
            try data.write(to: LibraryPaths.catalogURL, options: .atomic)
        } catch {
            loadError = "本棚の保存に失敗しました。"
        }
    }

    private func ensureSample() {
        guard !blockSave else { return }
        guard !volumes.contains(where: \.isBundledSample) else { return }
        let pages = (1...16).map { String(format: "sample-%03d", $0) }
        volumes.append(
            MangaVolume(
                id: Self.sampleID,
                title: "サンプル",
                directoryName: "sample-bundled",
                pageFileNames: pages,
                coverFileName: "sample-cover",
                direction: .rtl,
                importedAt: Date.distantPast,
                isBundledSample: true
            )
        )
        save()
    }
}
