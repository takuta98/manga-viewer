import Foundation

enum FTPClient {
    static func list(source: RemoteSource, path: String) async throws -> [RemoteEntry] {
        let url = try makeURL(source, path: path, isDir: true)
        var req = URLRequest(url: url)
        applyAuth(&req, source)
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw RemoteError.message("FTPの一覧取得に失敗しました")
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.split(whereSeparator: \.isNewline).compactMap { line -> RemoteEntry? in
            let name = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != "." , name != ".." else { return nil }
            let isDir = name.hasSuffix("/")
            let clean = name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let full = path.isEmpty ? clean : path + "/" + clean
            return RemoteEntry(name: clean, path: full, isDirectory: isDir, size: nil)
        }
    }

    static func download(source: RemoteSource, entry: RemoteEntry, to dest: URL) async throws {
        let url = try makeURL(source, path: entry.path, isDir: false)
        var req = URLRequest(url: url)
        applyAuth(&req, source)
        let (tmp, response) = try await URLSession.shared.download(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw RemoteError.message("FTPのダウンロードに失敗しました")
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
    }

    private static func makeURL(_ source: RemoteSource, path: String, isDir: Bool) throws -> URL {
        var c = URLComponents()
        c.scheme = source.useTLS ? "ftps" : "ftp"
        c.host = source.host
        c.port = source.port
        let root = source.shareOrPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let rel = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var p = "/"
        if !root.isEmpty { p += root + "/" }
        if !rel.isEmpty { p += rel }
        if isDir && !p.hasSuffix("/") { p += "/" }
        c.path = p
        guard let url = c.url else { throw RemoteError.message("FTPのURLが不正です") }
        return url
    }

    private static func applyAuth(_ req: inout URLRequest, _ source: RemoteSource) {
        guard !source.username.isEmpty else { return }
        let raw = "\(source.username):\(source.password)"
        req.setValue("Basic \(Data(raw.utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")
    }
}
