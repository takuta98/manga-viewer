import Foundation

enum OPDSClient {
    static func list(source: RemoteSource, path: String) async throws -> [RemoteEntry] {
        let url = try feedURL(source, path: path)
        var req = URLRequest(url: url)
        applyAuth(&req, source)
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw RemoteError.message("OPDSの取得に失敗しました")
        }
        return parse(data)
    }

    static func download(source: RemoteSource, entry: RemoteEntry, to dest: URL) async throws {
        guard let url = URL(string: entry.path) else { throw RemoteError.message("OPDSのリンクが不正です") }
        var req = URLRequest(url: url)
        applyAuth(&req, source)
        let (tmp, response) = try await URLSession.shared.download(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw RemoteError.message("OPDSのダウンロードに失敗しました")
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
    }

    private static func feedURL(_ source: RemoteSource, path: String) throws -> URL {
        if path.hasPrefix("http") { return URL(string: path)! }
        let scheme = source.useTLS ? "https" : "http"
        var s = "\(scheme)://\(source.host)"
        if source.port > 0 { s += ":\(source.port)" }
        let root = source.shareOrPath.isEmpty ? "/" : source.shareOrPath
        s += root.hasPrefix("/") ? root : "/\(root)"
        if !path.isEmpty { s = path }
        guard let url = URL(string: s) else { throw RemoteError.message("OPDSのURLが不正です") }
        return url
    }

    private static func applyAuth(_ req: inout URLRequest, _ source: RemoteSource) {
        guard !source.username.isEmpty else { return }
        let raw = "\(source.username):\(source.password)"
        req.setValue("Basic \(Data(raw.utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")
    }

    private static func parse(_ data: Data) -> [RemoteEntry] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var entries: [RemoteEntry] = []
        for chunk in text.components(separatedBy: "<entry>").dropFirst() {
            let title = slice(chunk, "<title>", "</title>") ?? "無題"
            let isNav = chunk.contains("rel=\"subsection\"") || chunk.contains("type=\"application/atom+xml")
            if let href = attr(chunk, "href=\"", "\"") {
                entries.append(RemoteEntry(name: title, path: href, isDirectory: isNav, size: nil))
            }
        }
        return entries
    }

    private static func slice(_ s: String, _ a: String, _ b: String) -> String? {
        guard let r = s.range(of: a), let e = s.range(of: b, range: r.upperBound..<s.endIndex) else { return nil }
        return String(s[r.upperBound..<e.lowerBound])
    }
    private static func attr(_ s: String, _ a: String, _ b: String) -> String? {
        guard let r = s.range(of: a) else { return nil }
        guard let e = s.range(of: b, range: r.upperBound..<s.endIndex) else { return nil }
        return String(s[r.upperBound..<e.lowerBound])
    }
}
