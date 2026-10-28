import Foundation

struct MangaVolume: Identifiable, Hashable, Codable {
    var id: UUID
    var title: String
    var directoryName: String
    var pageFileNames: [String]
    var coverFileName: String?
    var direction: ReadingDirection
    var importedAt: Date
    var isBundledSample: Bool
    /// 本棚フォルダー名。nil はフォルダー無し。
    var folder: String? = nil
    /// 見開きのペアずらし。このページ番号（0始まり）の直後に空白ページを1枚挿す。nil は無し。
    var pairBreakAfter: Int? = nil

    var pageCount: Int { pageFileNames.count }

    func pageURL(at index: Int) -> URL? {
        guard pageFileNames.indices.contains(index) else { return nil }
        let name = pageFileNames[index]
        if isBundledSample {
            let base = (name as NSString).deletingPathExtension
            return Bundle.main.url(
                forResource: base,
                withExtension: "png",
                subdirectory: "SampleManga/sample"
            )
        }
        return LibraryPaths.volumeDirectory(directoryName).appendingPathComponent(name)
    }

    func coverURL() -> URL? {
        if let coverFileName {
            if isBundledSample {
                let base = (coverFileName as NSString).deletingPathExtension
                return Bundle.main.url(
                    forResource: base.isEmpty ? coverFileName : base,
                    withExtension: "png",
                    subdirectory: "SampleManga/sample"
                )
            }
            return LibraryPaths.volumeDirectory(directoryName).appendingPathComponent(coverFileName)
        }
        return pageURL(at: 0)
    }
}
