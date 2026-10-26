import Foundation

enum PageFitMode: String, CaseIterable, Identifiable, Codable {
    case fitWidth, fitHeight, fitScreen
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fitWidth: return AppCopy.fitWidth
        case .fitHeight: return AppCopy.fitHeight
        case .fitScreen: return AppCopy.fitScreen
        }
    }
}

enum PageLayoutMode: String, CaseIterable, Identifiable, Codable {
    case single, spread, webtoon
    var id: String { rawValue }
    var label: String {
        switch self {
        case .single: return AppCopy.layoutSingle
        case .spread: return AppCopy.layoutSpread
        case .webtoon: return AppCopy.layoutWebtoon
        }
    }
}

enum PageTurnStyle: String, CaseIterable, Identifiable, Codable {
    case slide, curl
    var id: String { rawValue }
    var label: String {
        switch self {
        case .slide: return AppCopy.turnSlide
        case .curl: return AppCopy.turnCurl
        }
    }
}

enum LibrarySort: String, CaseIterable, Identifiable, Codable {
    case recent, title, progress
    var id: String { rawValue }
    var label: String {
        switch self {
        case .recent: return AppCopy.sortRecent
        case .title: return AppCopy.sortTitle
        case .progress: return AppCopy.sortProgress
        }
    }
}

enum LibraryDisplayMode: String, CaseIterable, Identifiable, Codable {
    case list, grid
    var id: String { rawValue }
    var label: String { self == .list ? AppCopy.displayList : AppCopy.displayGrid }
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
