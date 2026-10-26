import Foundation

enum WebDAVClient {
    static func list(source: RemoteSource, path: String) async throws -> [RemoteEntry] {
        let base = try baseURL(source)
        let url = base.appendingPathComponent(trim(path))
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("""
        <?xml version="1.0" encoding="utf-8" ?>
        <d:propfind xmlns:d="DAV:">
          <d:prop><d:displayname/><d:getcontentlength/><d:resourcetype/></d:prop>
        </d:propfind>
        """.utf8)
        applyAuth(&request, source: source)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw RemoteError.requestFailed("WebDAV PROPFIND failed")
        }
        return parsePropfind(xml: data, basePath: trim(path))
    }

    static func download(source: RemoteSource, path: String, to local: URL) async throws {
        let base = try baseURL(source)
        let url = base.appendingPathComponent(trim(path))
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuth(&request, source: source)
        let (temp, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw RemoteError.requestFailed("WebDAV download failed")
        }
        try? FileManager.default.removeItem(at: local)
        try FileManager.default.moveItem(at: temp, to: local)
    }

    private static func baseURL(_ source: RemoteSource) throws -> URL {
        var host = source.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if !host.contains("://") {
            host = (source.useTLS ? "https://" : "http://") + host
        }
        guard var components = URLComponents(string: host) else { throw RemoteError.invalidURL }
        if let port = source.port { components.port = port }
        if !source.shareOrPath.isEmpty {
            let basePath = components.path
            let extra = source.shareOrPath.hasPrefix("/") ? source.shareOrPath : "/" + source.shareOrPath
            components.path = (basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath) + extra
        }
        guard let url = components.url else { throw RemoteError.invalidURL }
        return url
    }

    private static func applyAuth(_ request: inout URLRequest, source: RemoteSource) {
        guard !source.username.isEmpty else { return }
        let raw = "\(source.username):\(source.password)"
        let b64 = Data(raw.utf8).base64EncodedString()
        request.setValue("Basic \(b64)", forHTTPHeaderField: "Authorization")
    }

    private static func trim(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func parsePropfind(xml: Data, basePath: String) -> [RemoteEntry] {
        let text = String(data: xml, encoding: .utf8) ?? ""
        var entries: [RemoteEntry] = []
        // Lightweight parse: split on response blocks.
        let blocks = text.components(separatedBy: "<d:response").dropFirst()
            + text.components(separatedBy: "<D:response").dropFirst()
        for block in blocks {
            let href = firstTag(block, names: ["d:href", "D:href"]) ?? ""
            let name = (firstTag(block, names: ["d:displayname", "D:displayname"]) ?? URL(string: href)?.lastPathComponent ?? href)
                .removingPercentEncoding ?? href
            let isDir = block.contains("<d:collection") || block.contains("<D:collection") || href.hasSuffix("/")
            let lengthStr = firstTag(block, names: ["d:getcontentlength", "D:getcontentlength"])
            let size = lengthStr.flatMap { Int64($0) }
            let path: String
            if let url = URL(string: href), url.scheme != nil {
                path = url.path
            } else {
                path = href
            }
            let normalized = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if normalized.isEmpty || normalized == trim(basePath) { continue }
            entries.append(RemoteEntry(name: name, path: normalized, isDirectory: isDir, size: size, downloadURL: nil))
        }
        // Dedup
        var seen = Set<String>()
        return entries.filter { seen.insert($0.path).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func firstTag(_ text: String, names: [String]) -> String? {
        for name in names {
            guard let start = text.range(of: "<\(name)") else { continue }
            guard let openEnd = text[start.upperBound...].firstIndex(of: ">") else { continue }
            let contentStart = text.index(after: openEnd)
            guard let close = text.range(of: "</\(name)>", range: contentStart..<text.endIndex) else { continue }
            return String(text[contentStart..<close.lowerBound])
                .replacingOccurrences(of: "<![CDATA[", with: "")
                .replacingOccurrences(of: "]]>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}

enum RemoteError: LocalizedError {
    case invalidURL
    case requestFailed(String)
    case unsupported
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL が不正です"
        case .requestFailed(let m): return m
        case .unsupported: return "この形式は未対応です"
        case .notConfigured: return "接続情報が不足しています"
        }
    }
}
