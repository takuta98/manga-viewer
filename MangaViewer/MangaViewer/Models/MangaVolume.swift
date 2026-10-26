import Foundation

struct MangaVolume: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    /// Absolute path under app sandbox, or empty for bundled sample.
    var pagesDirectory: String
    var pageFileNames: [String]
    var coverFileName: String?
    var direction: ReadingDirection
    var isBundledSample: Bool
    var importedAt: Date
    var lastOpenedAt: Date?
    /// 書庫フォルダ。未分類は `nil`。
    var folderId: String?

    var pageCount: Int { pageFileNames.count }

    func pageURL(at index: Int) -> URL? {
        guard index >= 0, index < pageFileNames.count else { return nil }
        let name = pageFileNames[index]
        if isBundledSample {
            return Bundle.main.url(
                forResource: name,
                withExtension: "png",
                subdirectory: "SampleManga/sample"
            ) ?? Bundle.main.url(forResource: name, withExtension: "png")
        }
        return URL(fileURLWithPath: pagesDirectory).appendingPathComponent(name)
    }

    func coverURL() -> URL? {
        if let coverFileName {
            if isBundledSample {
                return Bundle.main.url(
                    forResource: coverFileName,
                    withExtension: "png",
                    subdirectory: "SampleManga/sample"
                )
            }
            return URL(fileURLWithPath: pagesDirectory)
                .deletingLastPathComponent()
                .appendingPathComponent(coverFileName)
        }
        return pageURL(at: 0)
    }
}
