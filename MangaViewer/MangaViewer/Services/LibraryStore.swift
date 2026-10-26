import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var volumes: [MangaVolume] = []
    @Published var sort: LibrarySort = AppSettingsStore.loadSort() {
        didSet { AppSettingsStore.saveSort(sort) }
    }

    private let indexURL: URL
    private let fm = FileManager.default

    nonisolated static var libraryRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Library", isDirectory: true)
    }

    init() {
        indexURL = Self.libraryRoot.appendingPathComponent("index.json")
        try? fm.createDirectory(at: Self.libraryRoot, withIntermediateDirectories: true)
        load()
        ensureSample()
    }

    var sortedVolumes: [MangaVolume] {
        switch sort {
        case .title:
            return volumes.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .progress:
            let prefs = AppSettingsStore.loadPrefs()
            return volumes.sorted {
                ProgressStore.shared.progressPercent(for: $0, coverAlone: prefs.coverAlone, layout: prefs.layoutMode)
                    > ProgressStore.shared.progressPercent(for: $1, coverAlone: prefs.coverAlone, layout: prefs.layoutMode)
            }
        case .recent:
            return volumes.sorted {
                ($0.lastOpenedAt ?? $0.importedAt) > ($1.lastOpenedAt ?? $1.importedAt)
            }
        }
    }

    func importURL(_ url: URL) throws {
        let volume = try MangaImporter.importFile(from: url)
        volumes.removeAll { $0.id == volume.id }
        volumes.insert(volume, at: 0)
        save()
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

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([MangaVolume].self, from: data) else {
            volumes = []
            return
        }
        volumes = decoded.filter { volume in
            if volume.isBundledSample { return true }
            return fm.fileExists(atPath: volume.pagesDirectory)
        }
    }

    private func save() {
        try? fm.createDirectory(at: Self.libraryRoot, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(volumes) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    private func ensureSample() {
        guard !volumes.contains(where: { $0.isBundledSample }) else { return }
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
            lastOpenedAt: nil
        )
        volumes.append(sample)
        save()
    }
}
