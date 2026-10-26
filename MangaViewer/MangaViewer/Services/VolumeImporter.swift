import Foundation

enum VolumeImporter {
    static func importFile(at url: URL, titleHint: String) throws -> MangaVolume {
        let directoryName = UUID().uuidString
        let dest = LibraryPaths.volumeDirectory(directoryName)
        let ext = url.pathExtension.lowercased()
        let pages: [String]

        if ext == "cbz" || ext == "zip" {
            pages = try ZipExtractor.extractImages(from: url, into: dest)
        } else if ZipExtractor.imageExtensions.contains(ext) {
            let name = "0001.\(ext)"
            try FileManager.default.copyItem(at: url, to: dest.appendingPathComponent(name))
            pages = [name]
        } else {
            throw NSError(
                domain: "VolumeImporter",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "未対応の形式です"]
            )
        }

        guard !pages.isEmpty else {
            throw NSError(
                domain: "VolumeImporter",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "画像ページが見つかりません"]
            )
        }

        return MangaVolume(
            id: UUID(),
            title: TitleCleaner.clean(titleHint),
            directoryName: directoryName,
            pageFileNames: pages,
            coverFileName: pages.first,
            direction: AppSettingsStore.load().direction,
            importedAt: Date(),
            isBundledSample: false
        )
    }
}
