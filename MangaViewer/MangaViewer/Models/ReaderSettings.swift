import Foundation

enum PageFitMode: String, CaseIterable, Identifiable, Codable {
    case fitWidth, fitHeight, fitScreen
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fitWidth: return "幅に合わせる"
        case .fitHeight: return "高さに合わせる"
        case .fitScreen: return "画面に合わせる"
        }
    }
}

enum PageLayoutMode: String, CaseIterable, Identifiable, Codable {
    case single, spread, webtoon
    var id: String { rawValue }
    var label: String {
        switch self {
        case .single: return "単ページ"
        case .spread: return "見開き（横で許可）"
        case .webtoon: return "縦スクロール"
        }
    }
}

enum PageTurnStyle: String, CaseIterable, Identifiable, Codable {
    case slide, curl
    var id: String { rawValue }
    var label: String {
        switch self {
        case .slide: return "スライド"
        case .curl: return "ページめくり"
        }
    }
}

enum LibrarySort: String, CaseIterable, Identifiable, Codable {
    case recent, title, progress
    var id: String { rawValue }
    var label: String {
        switch self {
        case .recent: return "最近"
        case .title: return "タイトル"
        case .progress: return "進捗"
        }
    }
}

enum LibraryDisplayMode: String, CaseIterable, Identifiable, Codable {
    case list, grid
    var id: String { rawValue }
    var label: String { self == .list ? "リスト" : "グリッド" }
    var systemImage: String { self == .list ? "list.bullet" : "square.grid.2x2" }
    var toggled: LibraryDisplayMode { self == .list ? .grid : .list }
}

struct ReaderPreferences: Codable, Equatable {
    var direction: ReadingDirection = .rtl
    var layoutMode: PageLayoutMode = .spread
    var fitMode: PageFitMode = .fitScreen
    var coverAlone: Bool = true
    var brightness: Double = 1.0
    var keepScreenOn: Bool = true
    var turnStyle: PageTurnStyle = .curl
}

enum AppSettingsStore {
    private static let prefsKey = "manga-viewer.reader-prefs"
    private static let sortKey = "manga-viewer.library-sort"
    private static let displayKey = "manga-viewer.library-display"

    static func loadPrefs() -> ReaderPreferences {
        guard let data = UserDefaults.standard.data(forKey: prefsKey),
              let prefs = try? JSONDecoder().decode(ReaderPreferences.self, from: data) else {
            return ReaderPreferences()
        }
        return prefs
    }

    static func savePrefs(_ prefs: ReaderPreferences) {
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: prefsKey)
        }
    }

    static func loadSort() -> LibrarySort {
        LibrarySort(rawValue: UserDefaults.standard.string(forKey: sortKey) ?? "") ?? .recent
    }

    static func saveSort(_ sort: LibrarySort) {
        UserDefaults.standard.set(sort.rawValue, forKey: sortKey)
    }

    static func loadLibraryDisplayMode() -> LibraryDisplayMode {
        LibraryDisplayMode(rawValue: UserDefaults.standard.string(forKey: displayKey) ?? "") ?? .grid
    }

    static func saveLibraryDisplayMode(_ mode: LibraryDisplayMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: displayKey)
    }
}
