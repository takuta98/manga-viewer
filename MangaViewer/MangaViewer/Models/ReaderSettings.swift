import Foundation
import SwiftUI

enum PageFitMode: String, CaseIterable, Identifiable, Codable {
    case fitWidth
    case fitHeight
    case fitScreen

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
    case single
    case spread
    case webtoon

    var id: String { rawValue }

    var label: String {
        switch self {
        case .single: return "単ページ"
        case .spread: return "見開き"
        case .webtoon: return "縦スクロール"
        }
    }
}

enum LibrarySort: String, CaseIterable, Identifiable, Codable {
    case recent
    case title
    case progress

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent: return "最近"
        case .title: return "タイトル"
        case .progress: return "進捗"
        }
    }
}

struct ReaderPreferences: Codable, Equatable {
    var direction: ReadingDirection = .rtl
    var layoutMode: PageLayoutMode = .spread
    var fitMode: PageFitMode = .fitScreen
    var coverAlone: Bool = true
    var backgroundBlack: Bool = true
    var brightness: Double = 1.0
    var keepScreenOn: Bool = true
    var cropMargins: Bool = false
    var turnStyle: PageTurnStyle = .slide
}

enum AppSettingsStore {
    private static let prefsKey = "manga-viewer.reader-prefs"
    private static let sortKey = "manga-viewer.library-sort"

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
        guard let raw = UserDefaults.standard.string(forKey: sortKey),
              let sort = LibrarySort(rawValue: raw) else {
            return .recent
        }
        return sort
    }

    static func saveSort(_ sort: LibrarySort) {
        UserDefaults.standard.set(sort.rawValue, forKey: sortKey)
    }
}
