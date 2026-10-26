import Foundation

enum DuoPose: String, CaseIterable, Identifiable {
    case open
    case closed
    case table

    var id: String { rawValue }

    var label: String {
        switch self {
        case .open: return "見開き"
        case .closed: return "閉じ"
        case .table: return "卓上"
        }
    }
}

enum ReadingDirection: String, Codable, CaseIterable, Identifiable {
    case rtl
    case ltr

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rtl: return "右→左 (漫画)"
        case .ltr: return "左→右"
        }
    }

    var shortLabel: String {
        switch self {
        case .rtl: return "L←R"
        case .ltr: return "L→R"
        }
    }
}
