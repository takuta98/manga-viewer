import Foundation

/// Physical reading pose inspired by iPhone Duo fold states.
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

enum ReadingDirection: String, Codable {
    case rtl
    case ltr
}
