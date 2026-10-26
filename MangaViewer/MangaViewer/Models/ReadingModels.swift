import Foundation

enum ReadingDirection: String, CaseIterable, Identifiable, Codable {
    case rtl
    case ltr
    var id: String { rawValue }
    var label: String { self == .rtl ? "右開き" : "左開き" }
}

enum PageTurnStyle: String, CaseIterable, Identifiable, Codable {
    case slide
    case curl
    var id: String { rawValue }
    var label: String { self == .slide ? "スライド" : "ページめくり" }
}

enum PageFitMode: String, CaseIterable, Identifiable, Codable {
    case fitScreen
    case fitWidth
    case fitHeight
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fitScreen: return "画面に合わせる"
        case .fitWidth: return "幅に合わせる"
        case .fitHeight: return "高さに合わせる"
        }
    }
}

struct ReaderPreferences: Codable, Equatable {
    var direction: ReadingDirection = .rtl
    var turnStyle: PageTurnStyle = .slide
    var fitMode: PageFitMode = .fitScreen
    var brightness: Double = 1
    var keepScreenOn: Bool = true
}

enum AppSettingsStore {
    private static let key = "manga-viewer.prefs.v2"

    static func load() -> ReaderPreferences {
        guard let data = UserDefaults.standard.data(forKey: key),
              let prefs = try? JSONDecoder().decode(ReaderPreferences.self, from: data) else {
            return ReaderPreferences()
        }
        return prefs
    }

    static func save(_ prefs: ReaderPreferences) {
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
