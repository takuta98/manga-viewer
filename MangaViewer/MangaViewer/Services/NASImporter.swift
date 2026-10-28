import Foundation

/// NAS からの取り込み。ファイル1本か、フォルダー再帰DL を取り込み経路に乗せる。
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

        // NAS のフォルダー名で本棚のフォルダーを作り、取り込んだ巻はそこに入れる
        library.createFolder(entry.name)

        // cbz/zip は各1巻
        for file in wanted where archiveExtensions.contains((file.name as NSString).pathExtension.lowercased()) {
            let local = stage.appendingPathComponent(relativePath(file.path, under: entry.path))
            let volume = try library.importURL(local)
            library.move(volume, toFolder: entry.name)
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
            let volume = try library.importImageDirectory(imageDir, title: entry.name)
            library.move(volume, toFolder: entry.name)
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

/// ダウンロードを裏で動かす窓口。開始だけ通知して、進捗は別画面で見る。
@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    struct Job: Identifiable {
        let id = UUID()
        var name: String
        var status: String
        var failed: String?
        var finished = false
    }

    @Published private(set) var jobs: [Job] = []

    private init() {}

    /// ファイル1本を裏でダウンロード。
    func startFile(client: SMBClient, entry: SMBEntry, library: LibraryStore) {
        let job = Job(name: entry.name, status: "ダウンロードしています…")
        jobs.insert(job, at: 0)
        let id = job.id
        Task {
            do {
                _ = try await NASImporter.downloadFile(client: client, entry: entry, library: library)
                update(id) { $0.status = "完了"; $0.finished = true }
            } catch {
                update(id) { $0.status = ""; $0.failed = error.localizedDescription }
            }
        }
    }

    /// フォルダーごと裏でダウンロード。
    func startFolder(client: SMBClient, entry: SMBEntry, library: LibraryStore) {
        let job = Job(name: entry.name, status: "一覧を取得しています…")
        jobs.insert(job, at: 0)
        let id = job.id
        Task {
            do {
                let count = try await NASImporter.downloadFolder(
                    client: client,
                    entry: entry,
                    library: library
                ) { text in
                    Task { @MainActor in
                        DownloadManager.shared.update(id) { $0.status = text }
                    }
                }
                update(id) { $0.status = "完了（\(count) 冊）"; $0.finished = true }
            } catch {
                update(id) { $0.status = ""; $0.failed = error.localizedDescription }
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout Job) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[i])
    }
}
