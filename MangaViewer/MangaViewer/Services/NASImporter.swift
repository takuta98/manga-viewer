import Foundation

/// NAS からの取り込み。ファイル1本か、フォルダー再帰DL を既存の取り込み経路に乗せる。
enum NASImporter {
    static let archiveExtensions: Set<String> = ["cbz", "zip"]

    static var stagingRoot: URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nas-import", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// ファイル1本（cbz/zip/画像）を DL して1巻にする。
    @MainActor
    static func downloadFile(client: SMBClient, entry: SMBEntry, library: LibraryStore) async throws -> MangaVolume {
        let local = stagingRoot.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension((entry.name as NSString).pathExtension)
        defer { try? FileManager.default.removeItem(at: local) }
        try await client.download(remotePath: entry.path, to: local)
        return try library.importURL(local)
    }

    /// フォルダーごと DL: 画像はまとめて1巻、cbz/zip は各1巻。
    /// 戻り値は取り込んだ巻数。
    @MainActor
    static func downloadFolder(
        client: SMBClient,
        entry: SMBEntry,
        library: LibraryStore,
        status: @escaping (String) -> Void
    ) async throws -> Int {
        status("一覧を取得しています…")
        let files = try await client.filesRecursively(path: entry.path)
        let wanted = files.filter { file in
            let ext = (file.name as NSString).pathExtension.lowercased()
            return ZipExtractor.imageExtensions.contains(ext) || archiveExtensions.contains(ext)
        }
        guard !wanted.isEmpty else {
            throw NASImportError.nothingImportable
        }

        let stage = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: stage) }

        var done = 0
        for file in wanted {
            let relative = relativePath(file.path, under: entry.path)
            let local = stage.appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                at: local.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            done += 1
            status("\(done)/\(wanted.count) \(file.name)")
            try await client.download(remotePath: file.path, to: local)
        }

        status("本棚へ取り込んでいます…")
        var volumes = 0

        // cbz/zip は各1巻
        for file in wanted where archiveExtensions.contains((file.name as NSString).pathExtension.lowercased()) {
            let local = stage.appendingPathComponent(relativePath(file.path, under: entry.path))
            _ = try library.importURL(local)
            volumes += 1
        }

        // 画像はフォルダー全体で1巻
        let images = wanted.filter {
            ZipExtractor.imageExtensions.contains(($0.name as NSString).pathExtension.lowercased())
        }
        if !images.isEmpty {
            let imageDir = stage.appendingPathComponent("__images__", isDirectory: true)
            try FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)
            for file in images {
                let src = stage.appendingPathComponent(relativePath(file.path, under: entry.path))
                let ext = (file.name as NSString).pathExtension.lowercased()
                let dst = imageDir.appendingPathComponent(file.path.replacingOccurrences(of: "/", with: "_"))
                    .deletingPathExtension()
                    .appendingPathExtension(ext)
                try FileManager.default.copyItem(at: src, to: dst)
            }
            _ = try library.importImageDirectory(imageDir, title: entry.name)
            volumes += 1
        }
        return volumes
    }

    private static func relativePath(_ path: String, under base: String) -> String {
        let base = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard path.hasPrefix(base) else { return path }
        return String(path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

enum NASImportError: LocalizedError {
    case nothingImportable
    var errorDescription: String? { "取り込めるファイル（画像 / cbz / zip）がありません" }
}
