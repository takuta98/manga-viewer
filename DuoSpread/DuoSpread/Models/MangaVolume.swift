import Foundation

struct MangaVolume: Identifiable, Hashable {
    let id: String
    let title: String
    let titleEn: String
    let coverAssetName: String
    let pageAssetNames: [String]
    let direction: ReadingDirection

    var pageCount: Int { pageAssetNames.count }
}
