import Foundation

final class ProgressStore {
    static let shared = ProgressStore()

    private let defaults: UserDefaults
    private let prefix = "manga-viewer.progress."
    private let bookmarkPrefix = "manga-viewer.bookmarks."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func spreadIndex(for volumeId: String) -> Int {
        defaults.integer(forKey: key(volumeId))
    }

    func setSpreadIndex(_ index: Int, for volumeId: String) {
        defaults.set(max(0, index), forKey: key(volumeId))
    }

    func progressPercent(for volume: MangaVolume, coverAlone: Bool, layout: PageLayoutMode) -> Int {
        let spreads = SpreadIndex.spreadCount(
            pageCount: volume.pageCount,
            coverAlone: coverAlone,
            layout: layout
        )
        let saved = spreadIndex(for: volume.id)
        guard spreads > 1 else { return saved > 0 ? 100 : 0 }
        return min(100, Int((Double(saved) / Double(spreads - 1)) * 100.0))
    }

    func bookmarks(for volumeId: String) -> [Int] {
        defaults.array(forKey: bookmarkKey(volumeId)) as? [Int] ?? []
    }

    func toggleBookmark(pageIndex: Int, for volumeId: String) {
        var list = Set(bookmarks(for: volumeId))
        if list.contains(pageIndex) {
            list.remove(pageIndex)
        } else {
            list.insert(pageIndex)
        }
        defaults.set(Array(list).sorted(), forKey: bookmarkKey(volumeId))
    }

    func isBookmarked(pageIndex: Int, for volumeId: String) -> Bool {
        bookmarks(for: volumeId).contains(pageIndex)
    }

    func clear(for volumeId: String) {
        defaults.removeObject(forKey: key(volumeId))
        defaults.removeObject(forKey: bookmarkKey(volumeId))
    }

    private func key(_ volumeId: String) -> String { prefix + volumeId }
    private func bookmarkKey(_ volumeId: String) -> String { bookmarkPrefix + volumeId }
}
