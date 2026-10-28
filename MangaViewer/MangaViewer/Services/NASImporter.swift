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
        /// やり直し・重複防止用。
        var entry: SMBEntry?
        var client: SMBClient?
        var isFolder = false
        /// 中止用。実行中のタスク。
        var task: Task<Void, Never>?
        /// 進行中の同じ対象を二重に走らせないためのキー。
        var key: String { entry?.path ?? name }
    }

    @Published private(set) var jobs: [Job] = []

    private init() {}

    /// 進行中の同じ対象があるか。
    private func alreadyRunning(_ entry: SMBEntry) -> Bool {
        jobs.contains { $0.key == entry.path && !$0.finished && $0.failed == nil }
    }

    /// ファイル1本を裏でダウンロード。進行中なら false。
    @discardableResult
    func startFile(client: SMBClient, entry: SMBEntry, library: LibraryStore) -> Bool {
        guard !alreadyRunning(entry) else { return false }
        let job = Job(
            name: entry.name,
            status: "ダウンロードしています…",
            entry: entry,
            client: client,
            isFolder: false
        )
        jobs.insert(job, at: 0)
        let id = job.id
        let task = Task {
            do {
                try Task.checkCancellation()
                _ = try await NASImporter.downloadFile(client: client, entry: entry, library: library)
                update(id) { $0.status = "完了"; $0.finished = true }
            } catch is CancellationError {
                update(id) { $0.status = ""; $0.failed = "中止しました" }
            } catch {
                update(id) { $0.status = ""; $0.failed = error.localizedDescription }
            }
        }
        update(id) { $0.task = task }
        return true
    }

    /// フォルダーごと裏でダウンロード。進行中なら false。
    @discardableResult
    func startFolder(client: SMBClient, entry: SMBEntry, library: LibraryStore) -> Bool {
        guard !alreadyRunning(entry) else { return false }
        let job = Job(
            name: entry.name,
            status: "一覧を取得しています…",
            entry: entry,
            client: client,
            isFolder: true
        )
        jobs.insert(job, at: 0)
        let id = job.id
        let task = Task {
            do {
                try Task.checkCancellation()
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
            } catch is CancellationError {
                update(id) { $0.status = ""; $0.failed = "中止しました" }
            } catch {
                update(id) { $0.status = ""; $0.failed = error.localizedDescription }
            }
        }
        update(id) { $0.task = task }
        return true
    }

    /// 失敗したジョブをもう一度走らせる。接続が残っていなければやり直せない。
    func retry(_ job: Job, library: LibraryStore) {
        guard let entry = job.entry, let client = job.client, job.failed != nil else { return }
        jobs.removeAll { $0.id == job.id }
        if job.isFolder {
            _ = startFolder(client: client, entry: entry, library: library)
        } else {
            _ = startFile(client: client, entry: entry, library: library)
        }
    }

    /// 実行中のダウンロードを中止する。
    func cancel(_ job: Job) {
        job.task?.cancel()
        update(job.id) { $0.status = ""; $0.failed = "中止しました" }
    }

    /// 終わった分（成功・失敗）を一覧から消す。
    func clearFinished() {
        jobs.removeAll { $0.finished || $0.failed != nil }
    }

    private func update(_ id: UUID, _ change: (inout Job) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[i])
    }
}
