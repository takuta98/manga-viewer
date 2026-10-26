import Foundation

@MainActor
final class ReadingProgress {
    static let shared = ReadingProgress()
    private let key = "manga-viewer.page-index.v2"
    private var pages: [String: Int] = [:]

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            pages = decoded
        }
    }

    func pageIndex(for id: UUID) -> Int {
        pages[id.uuidString] ?? 0
    }

    func setPageIndex(_ index: Int, for id: UUID) {
        pages[id.uuidString] = max(0, index)
        persist()
    }

    func clear(for id: UUID) {
        pages.removeValue(forKey: id.uuidString)
        persist()
    }

    func percent(for volume: MangaVolume) -> Int {
        guard volume.pageCount > 0 else { return 0 }
        let current = pageIndex(for: volume.id)
        return min(100, Int((Double(current + 1) / Double(volume.pageCount) * 100).rounded()))
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(pages) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
