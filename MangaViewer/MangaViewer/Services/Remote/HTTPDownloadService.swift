import Foundation

enum HTTPDownloadService {
    static func list(source: RemoteSource, path: String) async throws -> [RemoteEntry] {
        let base = path.isEmpty ? source.host : path
        guard let url = URL(string: base) else { throw RemoteError.message("URLが不正です") }
        return [RemoteEntry(name: url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent, path: url.absoluteString, isDirectory: false, size: nil)]
    }

    static func download(source: RemoteSource, entry: RemoteEntry, to dest: URL) async throws {
        guard let url = URL(string: entry.path) else { throw RemoteError.message("URLが不正です") }
        let (tmp, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw RemoteError.message("ダウンロードに失敗しました（\(http.statusCode)）")
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
    }
}
