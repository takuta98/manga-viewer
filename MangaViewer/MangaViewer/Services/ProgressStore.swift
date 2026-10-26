import Foundation
import Combine

@MainActor
final class ProgressStore: ObservableObject {
    static let shared = ProgressStore()
    private let key = "manga-viewer.progress"
    @Published private(set) var revision = 0
    private var map: [String: Int] = [:]
    private var bookmarkMap: [String: [Int]] = [:]

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Payload.self, from: data) {
            map = decoded.spreads
            bookmarkMap = decoded.bookmarks
        }
    }

    func spreadIndex(for id: UUID) -> Int { map[id.uuidString] ?? 0 }

    func setSpreadIndex(_ value: Int, for id: UUID) {
        let next = max(0, value)
        guard map[id.uuidString] != next else { return }
        map[id.uuidString] = next
        // ページ送りごとに UI 全体を再描画しない。本棚は notifyLibrary() で更新。
        persist()
    }

    func notifyLibrary() {
        revision += 1
    }

    func progressPercent(for volume: MangaVolume, coverAlone: Bool, layout: PageLayoutMode) -> Int {
        let total = SpreadIndex.totalSpreads(pageCount: volume.pageCount, coverAlone: coverAlone, layout: layout)
        guard total > 0 else { return 0 }
        let cur = spreadIndex(for: volume.id)
        return min(100, Int((Double(cur + 1) / Double(total) * 100).rounded()))
    }

    func bookmarks(for id: UUID) -> [Int] {
        bookmarkMap[id.uuidString] ?? []
    }

    func isBookmarked(pageIndex: Int, for id: UUID) -> Bool {
        bookmarkMap[id.uuidString]?.contains(pageIndex) == true
    }

    func toggleBookmark(pageIndex: Int, for id: UUID) {
        var list = bookmarkMap[id.uuidString] ?? []
        if let i = list.firstIndex(of: pageIndex) { list.remove(at: i) } else { list.append(pageIndex) }
        bookmarkMap[id.uuidString] = list
        revision += 1
        persist()
    }

    func removeBookmark(pageIndex: Int, for id: UUID) {
        guard var list = bookmarkMap[id.uuidString],
              let i = list.firstIndex(of: pageIndex) else { return }
        list.remove(at: i)
        bookmarkMap[id.uuidString] = list
        revision += 1
        persist()
    }

    func clearBookmarks(for id: UUID) {
        guard !(bookmarkMap[id.uuidString] ?? []).isEmpty else { return }
        bookmarkMap[id.uuidString] = []
        revision += 1
        persist()
    }

    func clearProgress(for id: UUID) {
        map[id.uuidString] = 0
        revision += 1
        persist()
    }

    private struct Payload: Codable {
        var spreads: [String: Int]
        var bookmarks: [String: [Int]]
    }

    private func persist() {
        let payload = Payload(spreads: map, bookmarks: bookmarkMap)
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
