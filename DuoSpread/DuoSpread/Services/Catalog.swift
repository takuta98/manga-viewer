import Foundation

enum Catalog {
    static let volumes: [MangaVolume] = [
        MangaVolume(
            id: "night-station",
            title: "夜の駅",
            titleEn: "Night Station",
            coverAssetName: "night-station-cover",
            pageAssetNames: (1...16).map { String(format: "night-station-%03d", $0) },
            direction: .rtl
        )
    ]

    static func volume(id: String) -> MangaVolume? {
        volumes.first { $0.id == id }
    }
}
