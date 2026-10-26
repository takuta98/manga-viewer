import Foundation

enum OPDSClient {
    static func list(source: RemoteSource, path: String) async throws -> [RemoteEntry] {
        let url = try feedURL(source: source, path: path)
        var request = URLRequest(url: url)
        applyAuth(&request, source: source)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw RemoteError.requestFailed("OPDS フィードの取得に失敗しました")
        }
        let xml = String(data: data, encoding: .utf8) ?? ""
        return parseAtom(xml)
    }

    static func download(source: RemoteSource, entry: RemoteEntry, to local: URL) async throws {
        guard let url = entry.downloadURL else { throw RemoteError.notConfigured }
        var request = URLRequest(url: url)
        applyAuth(&request, source: source)
        let (temp, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw RemoteError.requestFailed("OPDS のダウンロードに失敗しました")
        }
        try? FileManager.default.removeItem(at: local)
        try FileManager.default.moveItem(at: temp, to: local)
    }

    private static func feedURL(source: RemoteSource, path: String) throws -> URL {
        var host = source.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if !host.contains("://") {
            host = (source.useTLS ? "https://" : "http://") + host
        }
        if path.isEmpty {
            if !source.shareOrPath.isEmpty {
                if source.shareOrPath.hasPrefix("http") {
                    guard let u = URL(string: source.shareOrPath) else { throw RemoteError.invalidURL }
                    return u
                }
                host = host.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let pathPart = source.shareOrPath.hasPrefix("/") ? source.shareOrPath : "/" + source.shareOrPath
                guard let u = URL(string: host + pathPart) else { throw RemoteError.invalidURL }
                return u
            }
            guard let u = URL(string: host) else { throw RemoteError.invalidURL }
            return u
        }
        if path.hasPrefix("http") {
            guard let u = URL(string: path) else { throw RemoteError.invalidURL }
            return u
        }
        guard let base = URL(string: host) else { throw RemoteError.invalidURL }
        return URL(string: path, relativeTo: base)?.absoluteURL ?? base
    }

    private static func applyAuth(_ request: inout URLRequest, source: RemoteSource) {
        guard !source.username.isEmpty else { return }
        let raw = "\(source.username):\(source.password)"
        request.setValue("Basic \(Data(raw.utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")
    }

    private static func parseAtom(_ xml: String) -> [RemoteEntry] {
        var entries: [RemoteEntry] = []
        let chunks = xml.components(separatedBy: "<entry").dropFirst()
        for chunk in chunks {
            let title = tag(chunk, "title") ?? "Untitled"
            let links = linkHrefs(chunk)
            if let acquisition = links.first(where: {
                $0.rel.contains("acquisition") || ComicFileProbe.isImportableFile($0.href)
            }) {
                let url = URL(string: acquisition.href)
                entries.append(RemoteEntry(
                    name: title + fileSuffix(acquisition.href),
                    path: acquisition.href,
                    isDirectory: false,
                    size: nil,
                    downloadURL: url
                ))
            }
            if let nav = links.first(where: { $0.rel.contains("subsection") || $0.rel == "http://opds-spec.org/sort/new" || $0.type.contains("atom") }) {
                entries.append(RemoteEntry(
                    name: "📁 \(title)",
                    path: nav.href,
                    isDirectory: true,
                    size: nil,
                    downloadURL: URL(string: nav.href)
                ))
            }
        }
        // Also top-level navigation links outside entries
        if entries.isEmpty {
            for link in linkHrefs(xml) where link.rel.contains("subsection") || link.type.contains("atom") {
                entries.append(RemoteEntry(
                    name: link.title ?? link.href,
                    path: link.href,
                    isDirectory: true,
                    size: nil,
                    downloadURL: URL(string: link.href)
                ))
            }
        }
        return entries
    }

    private struct Link {
        var href: String
        var rel: String
        var type: String
        var title: String?
    }

    private static func linkHrefs(_ text: String) -> [Link] {
        var result: [Link] = []
        var search = text[...]
        while let range = search.range(of: "<link ") {
            search = search[range.upperBound...]
            guard let end = search.firstIndex(of: ">") else { break }
            let attrs = String(search[..<end])
            let href = attr(attrs, "href") ?? ""
            let rel = attr(attrs, "rel") ?? ""
            let type = attr(attrs, "type") ?? ""
            let title = attr(attrs, "title")
            if !href.isEmpty {
                result.append(Link(href: href, rel: rel, type: type, title: title))
            }
            search = search[end...]
        }
        return result
    }

    private static func attr(_ text: String, _ name: String) -> String? {
        let patterns = ["\(name)=\"", "\(name)='"]
        for p in patterns {
            guard let r = text.range(of: p) else { continue }
            let rest = text[r.upperBound...]
            let quote = p.last!
            guard let end = rest.firstIndex(of: quote) else { continue }
            return String(rest[..<end])
        }
        return nil
    }

    private static func tag(_ text: String, _ name: String) -> String? {
        guard let open = text.range(of: "<\(name)") else { return nil }
        guard let gt = text[open.upperBound...].firstIndex(of: ">") else { return nil }
        let start = text.index(after: gt)
        guard let close = text.range(of: "</\(name)>", range: start..<text.endIndex) else { return nil }
        return String(text[start..<close.lowerBound])
            .replacingOccurrences(of: "<![CDATA[", with: "")
            .replacingOccurrences(of: "]]>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fileSuffix(_ href: String) -> String {
        let ext = URL(string: href)?.pathExtension ?? ""
        return ext.isEmpty ? "" : ".\(ext)"
    }
}
