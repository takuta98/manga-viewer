import Foundation

struct MangaVolume: Identifiable, Hashable, Codable {
    var id: UUID
    var title: String
    var directoryName: String
    var pageFileNames: [String]
    var coverFileName: String?
    var direction: ReadingDirection
    var folderId: UUID?
    var importedAt: Date

    var pageCount: Int { pageFileNames.count }

    func pageURL(at index: Int) -> URL? {
        guard pageFileNames.indices.contains(index) else { return nil }
        return Catalog.pagesDirectory(for: directoryName).appendingPathComponent(pageFileNames[index])
    }

    func coverURL() -> URL? {
        if let coverFileName {
            return Catalog.pagesDirectory(for: directoryName).appendingPathComponent(coverFileName)
        }
        return pageURL(at: 0)
    }
}

enum ReadingDirection: String, CaseIterable, Identifiable, Codable {
    case rtl
    case ltr

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rtl: return "右開き（日本語）"
        case .ltr: return "左開き"
        }
    }

    var shortLabel: String {
        switch self {
        case .rtl: return "右開き"
        case .ltr: return "左開き"
        }
    }
}
