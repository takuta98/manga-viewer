import Foundation
import UniformTypeIdentifiers

enum MangaImporter {
    static func importFile(at url: URL, title: String, folderId: UUID?) throws -> MangaVolume {
        let dirName = UUID().uuidString
        let dest = Catalog.pagesDirectory(for: dirName)
        let ext = url.pathExtension.lowercased()
        var pages: [String] = []
        if ["cbz", "zip"].contains(ext) {
            pages = try ZipUnarchiver.extractImages(from: url, to: dest)
        } else if isImage(ext) {
            let name = "0001.\(ext)"
            try FileManager.default.copyItem(at: url, to: dest.appendingPathComponent(name))
            pages = [name]
        } else if url.hasDirectoryPath {
            pages = try importImageFolder(url, to: dest)
        } else {
            throw NSError(domain: "MangaImporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "未対応の形式です"])
        }
        guard !pages.isEmpty else {
            throw NSError(domain: "MangaImporter", code: 2, userInfo: [NSLocalizedDescriptionKey: "画像ページが見つかりません"])
        }
        return MangaVolume(
            id: UUID(),
            title: UserFacingText.title(fromFileName: title),
            directoryName: dirName,
            pageFileNames: pages,
            coverFileName: pages.first,
            direction: AppSettingsStore.loadPrefs().direction,
            folderId: folderId,
            importedAt: Date()
        )
    }

    private static func importImageFolder(_ url: URL, to dest: URL) throws -> [String] {
        let imgs = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            .filter { isImage($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        var names: [String] = []
        for (i, src) in imgs.enumerated() {
            let name = String(format: "%04d.%@", i + 1, src.pathExtension.lowercased())
            try FileManager.default.copyItem(at: src, to: dest.appendingPathComponent(name))
            names.append(name)
        }
        return names
    }

    static func isImage(_ ext: String) -> Bool {
        ["jpg", "jpeg", "png", "webp", "gif", "heic"].contains(ext)
    }
}

enum ComicFileProbe {
    static func isSupportedForImport(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["cbz", "zip", "jpg", "jpeg", "png", "webp", "gif", "heic"].contains(ext)
    }
}
