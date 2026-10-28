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

        return try makeVolume(pages: pages, directoryName: directoryName, titleHint: titleHint)
    }

    /// ディレクトリ内の画像をすべて1巻にまとめる（再帰・名前順）。
    static func importImageDirectory(at url: URL, titleHint: String) throws -> MangaVolume {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw NSError(domain: "VolumeImporter", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "画像ページが見つかりません"])
        }
        var files: [URL] = []
        for case let file as URL in enumerator {
            if ZipExtractor.imageExtensions.contains(file.pathExtension.lowercased()) {
                files.append(file)
            }
        }
        files.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        let directoryName = UUID().uuidString
        let dest = LibraryPaths.volumeDirectory(directoryName)
        var pages: [String] = []
        for (i, file) in files.enumerated() {
            let name = String(format: "%04d.%@", i + 1, file.pathExtension.lowercased())
            try fm.copyItem(at: file, to: dest.appendingPathComponent(name))
            pages.append(name)
        }
        return try makeVolume(pages: pages, directoryName: directoryName, titleHint: titleHint)
    }

    private static func makeVolume(pages: [String], directoryName: String, titleHint: String) throws -> MangaVolume {
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
