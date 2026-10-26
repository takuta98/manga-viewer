import Foundation
import PDFKit
import UniformTypeIdentifiers
import UIKit

enum MangaImporter {
    static let supportedTypes: [UTType] = {
        var types: [UTType] = [.pdf, .jpeg, .png, .webP, .image, .folder, .zip]
        if let cbz = UTType(filenameExtension: "cbz") {
            types.append(cbz)
        }
        types.append(UTType(exportedAs: "com.comicbook.zip-archive", conformingTo: .zip))
        return types
    }()

    static func importFile(from sourceURL: URL, titleOverride: String? = nil) throws -> MangaVolume {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let fm = FileManager.default
        let id = UUID().uuidString
        let volumeRoot = LibraryStore.libraryRoot.appendingPathComponent(id, isDirectory: true)
        let pagesDir = volumeRoot.appendingPathComponent("pages", isDirectory: true)
        try fm.createDirectory(at: pagesDir, withIntermediateDirectories: true)

        let ext = sourceURL.pathExtension.lowercased()
        // タイトルは必ず UserFacingText 経由。一時パスの UUID 等を絶対に混ぜない。
        var title = UserFacingText.title(from: sourceURL)
        if let titleOverride {
            let cleaned = UserFacingText.clean(titleOverride)
            if cleaned != "無題" {
                title = cleaned
            }
        }
        var direction: ReadingDirection = AppSettingsStore.loadPrefs().direction

        if ext == "cbr" || ext == "rar" || ext == "7z" || ext == "cb7" {
            try? fm.removeItem(at: volumeRoot)
            throw ImportError.unsupportedArchive(ext)
        } else if ext == "cbz" || ext == "zip" {
            let temp = volumeRoot.appendingPathComponent("extract", isDirectory: true)
            try ZipUnarchiver.unzip(archiveURL: sourceURL, to: temp)
            if let info = ComicInfoParser.parse(in: temp) {
                if let t = info.title, !t.isEmpty {
                    title = UserFacingText.clean(t)
                }
                if let d = info.direction { direction = d }
            }
            try collectImages(from: temp, into: pagesDir)
            try? fm.removeItem(at: temp)
        } else if ext == "pdf" {
            try renderPDF(sourceURL, into: pagesDir)
        } else if isImage(ext) {
            let dest = pagesDir.appendingPathComponent("0001.\(ext)")
            try fm.copyItem(at: sourceURL, to: dest)
        } else {
            try collectImages(from: sourceURL, into: pagesDir)
        }

        let pages = sortedPageNames(in: pagesDir)
        guard !pages.isEmpty else {
            try? fm.removeItem(at: volumeRoot)
            throw ImportError.noPages
        }

        if let first = pages.first {
            let cover = volumeRoot.appendingPathComponent("cover.jpg")
            try? fm.copyItem(at: pagesDir.appendingPathComponent(first), to: cover)
        }

        return MangaVolume(
            id: id,
            title: UserFacingText.clean(title),
            pagesDirectory: pagesDir.path,
            pageFileNames: pages,
            coverFileName: fm.fileExists(atPath: volumeRoot.appendingPathComponent("cover.jpg").path) ? "cover.jpg" : nil,
            direction: direction,
            isBundledSample: false,
            importedAt: Date(),
            lastOpenedAt: nil,
            folderId: nil
        )
    }

    enum ImportError: LocalizedError {
        case noPages
        case unsupportedArchive(String)

        var errorDescription: String? {
            switch self {
            case .noPages: return "画像ページが見つかりませんでした"
            case .unsupportedArchive(let ext):
                return ".\(ext) は未対応です。CBZ/ZIP/PDF/画像に変換してください"
            }
        }
    }

    private static func isImage(_ ext: String) -> Bool {
        ["jpg", "jpeg", "png", "webp", "gif", "heic"].contains(ext)
    }

    private static func collectImages(from root: URL, into pagesDir: URL) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var images: [URL] = []
        for case let fileURL as URL in enumerator {
            if isImage(fileURL.pathExtension.lowercased()) {
                images.append(fileURL)
            }
        }
        images.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        for (idx, url) in images.enumerated() {
            let ext = url.pathExtension.lowercased()
            let name = String(format: "%04d.%@", idx + 1, ext)
            try fm.copyItem(at: url, to: pagesDir.appendingPathComponent(name))
        }
    }

    private static func sortedPageNames(in pagesDir: URL) -> [String] {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(atPath: pagesDir.path)) ?? []
        return files
            .filter { isImage(($0 as NSString).pathExtension.lowercased()) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func renderPDF(_ url: URL, into pagesDir: URL) throws {
        guard let doc = PDFDocument(url: url) else { throw ImportError.noPages }
        let fm = FileManager.default
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: 0, y: size.height)
                ctx.cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: ctx.cgContext)
                ctx.cgContext.restoreGState()
            }
            let out = pagesDir.appendingPathComponent(String(format: "%04d.jpg", i + 1))
            guard let data = image.jpegData(compressionQuality: 0.9) else { continue }
            try data.write(to: out)
            _ = fm
        }
        if sortedPageNames(in: pagesDir).isEmpty { throw ImportError.noPages }
    }
}
