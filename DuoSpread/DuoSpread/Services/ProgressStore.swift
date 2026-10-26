import Foundation

/// Persists the last opened spread index per volume.
final class ProgressStore {
    static let shared = ProgressStore()

    private let defaults: UserDefaults
    private let prefix = "duospread.progress."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func spreadIndex(for volumeId: String) -> Int {
        defaults.integer(forKey: key(volumeId))
    }

    func setSpreadIndex(_ index: Int, for volumeId: String) {
        defaults.set(max(0, index), forKey: key(volumeId))
    }

    func progressPercent(for volume: MangaVolume) -> Int {
        let spreads = SpreadIndex.spreadCount(pageCount: volume.pageCount)
        let saved = spreadIndex(for: volume.id)
        guard spreads > 1 else { return saved > 0 ? 100 : 0 }
        return Int((Double(saved) / Double(spreads - 1)) * 100.0)
    }

    private func key(_ volumeId: String) -> String {
        prefix + volumeId
    }
}
