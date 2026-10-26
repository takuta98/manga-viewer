import Foundation

enum HTTPDownloadService {
    static func list(source: RemoteSource, path: String) async throws -> [RemoteEntry] {
        let base = path.isEmpty ? source.host : path
        let raw = base.hasPrefix("http") ? base : ((source.useTLS ? "https://" : "http://") + base)
        guard let url = URL(string: raw) else { throw RemoteError.invalidURL }
        return [
            RemoteEntry(
                name: url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent,
                path: url.absoluteString,
                isDirectory: false,
                size: nil,
                downloadURL: url
            )
        ]
    }

    static func download(source: RemoteSource, entry: RemoteEntry, to dest: URL) async throws {
        guard let url = entry.downloadURL ?? URL(string: entry.path) else {
            throw RemoteError.invalidURL
        }
        var request = URLRequest(url: url)
        if !source.username.isEmpty {
            let token = Data("\(source.username):\(source.password)".utf8).base64EncodedString()
            request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }
        let (tmp, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw RemoteError.requestFailed("\(AppCopy.downloadFailedHTTP)（\(http.statusCode)）")
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
    }
}
