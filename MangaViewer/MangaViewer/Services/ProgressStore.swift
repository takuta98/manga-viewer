import Foundation

@MainActor
final class ProgressStore {
    static let shared = ProgressStore()
    private let key = "manga-viewer.progress"
    private var map: [String: Int] = [:]
    private var bookmarks: [String: [Int]] = [:]

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Payload.self, from: data) {
            map = decoded.spreads
            bookmarks = decoded.bookmarks
        }
    }

    func spreadIndex(for id: UUID) -> Int { map[id.uuidString] ?? 0 }

    func setSpreadIndex(_ value: Int, for id: UUID) {
        map[id.uuidString] = max(0, value)
        persist()
    }

    func progressPercent(for volume: MangaVolume, coverAlone: Bool, layout: PageLayoutMode) -> Int {
        let total = SpreadIndex.totalSpreads(pageCount: volume.pageCount, coverAlone: coverAlone, layout: layout)
        guard total > 0 else { return 0 }
        let cur = spreadIndex(for: volume.id)
        return min(100, Int((Double(cur + 1) / Double(total) * 100).rounded()))
    }

    func isBookmarked(pageIndex: Int, for id: UUID) -> Bool {
        bookmarks[id.uuidString]?.contains(pageIndex) == true
    }

    func toggleBookmark(pageIndex: Int, for id: UUID) {
        var list = bookmarks[id.uuidString] ?? []
        if let i = list.firstIndex(of: pageIndex) { list.remove(at: i) } else { list.append(pageIndex) }
        bookmarks[id.uuidString] = list
        persist()
    }

    private struct Payload: Codable {
        var spreads: [String: Int]
        var bookmarks: [String: [Int]]
    }

    private func persist() {
        let payload = Payload(spreads: map, bookmarks: bookmarks)
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
