import Foundation

enum WebDAVClient {
    static func list(source: RemoteSource, path: String) async throws -> [RemoteEntry] {
        let url = try endpoint(source, path: path)
        var req = URLRequest(url: url)
        req.httpMethod = "PROPFIND"
        req.setValue("0", forHTTPHeaderField: "Depth")
        req.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("""
        <?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><d:resourcetype/><d:getcontentlength/></d:prop></d:propfind>
        """.utf8)
        applyAuth(&req, source)
        // Depth 1 for children
        req.setValue("1", forHTTPHeaderField: "Depth")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) || http.statusCode == 207 else {
            throw RemoteError.message("WebDAVの一覧取得に失敗しました")
        }
        return parse(xml: data, basePath: path)
    }

    static func download(source: RemoteSource, entry: RemoteEntry, to dest: URL) async throws {
        let url = try endpoint(source, path: entry.path)
        var req = URLRequest(url: url)
        applyAuth(&req, source)
        let (tmp, response) = try await URLSession.shared.download(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw RemoteError.message("WebDAVのダウンロードに失敗しました（\(http.statusCode)）")
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
    }

    private static func endpoint(_ source: RemoteSource, path: String) throws -> URL {
        let scheme = source.useTLS ? "https" : "http"
        var base = "\(scheme)://\(source.host)"
        if source.port > 0 { base += ":\(source.port)" }
        let root = source.shareOrPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let rel = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var full = base
        if !root.isEmpty { full += "/\(root)" }
        if !rel.isEmpty { full += "/\(rel)" }
        if !full.hasSuffix("/") { full += "/" }
        guard let url = URL(string: full) else { throw RemoteError.message("WebDAVのURLが不正です") }
        return url
    }

    private static func applyAuth(_ req: inout URLRequest, _ source: RemoteSource) {
        guard !source.username.isEmpty else { return }
        let raw = "\(source.username):\(source.password)"
        let b64 = Data(raw.utf8).base64EncodedString()
        req.setValue("Basic \(b64)", forHTTPHeaderField: "Authorization")
    }

    private static func parse(xml: Data, basePath: String) -> [RemoteEntry] {
        guard let text = String(data: xml, encoding: .utf8) else { return [] }
        var entries: [RemoteEntry] = []
        let parts = text.components(separatedBy: "<d:response>").dropFirst()
        for part in parts {
            let href = slice(part, "<d:href>", "</d:href>") ?? ""
            let decoded = href.removingPercentEncoding ?? href
            let name = (decoded as NSString).lastPathComponent.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if name.isEmpty { continue }
            let isDir = part.contains("<d:collection") || decoded.hasSuffix("/")
            let sizeStr = slice(part, "<d:getcontentlength>", "</d:getcontentlength>")
            let size = sizeStr.flatMap { Int64($0) }
            let path: String
            if basePath.isEmpty { path = name } else { path = basePath + "/" + name }
            if path == basePath || name.isEmpty { continue }
            entries.append(RemoteEntry(name: name, path: path, isDirectory: isDir, size: size))
        }
        return entries
    }

    private static func slice(_ s: String, _ a: String, _ b: String) -> String? {
        guard let r = s.range(of: a), let e = s.range(of: b, range: r.upperBound..<s.endIndex) else { return nil }
        return String(s[r.upperBound..<e.lowerBound])
    }
}
