import Combine
import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    static let sampleID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

    @Published private(set) var volumes: [MangaVolume] = []
    @Published var loadError: String?
    private var blockSave = false

    init() {
        load()
        ensureSample()
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
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: LibraryPaths.catalogURL.path) else {
            volumes = []
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
            loadError = nil
        } catch {
            blockSave = true
            loadError = "本棚の読み込みに失敗しました。既存データは上書きしていません。"
        }
    }

    private func save() {
        guard !blockSave else { return }
        do {
            let data = try JSONEncoder().encode(Catalog(volumes: volumes))
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
