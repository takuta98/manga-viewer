import Foundation
import FeedKit

enum OPDSClient {
    static func list(source: RemoteSource, path: String) async throws -> [RemoteEntry] {
        let url = try feedURL(source: source, path: path)
        var request = URLRequest(url: url)
        applyAuth(&request, source: source)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw RemoteError.requestFailed(AppCopy.opdsFetchFailed)
        }
        let feed = try Feed(data: data)
        guard case .atom(let atom) = feed else {
            throw RemoteError.requestFailed(AppCopy.opdsNotAtom)
        }
        return (atom.entries ?? []).compactMap { entry -> RemoteEntry? in
            let title = entry.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let title, !title.isEmpty else { return nil }
            let links = entry.links ?? []
            let acquisition = links.first { link in
                let rel = link.attributes?.rel?.lowercased() ?? ""
                let type = link.attributes?.type?.lowercased() ?? ""
                return rel.contains("acquisition") || type.contains("zip") || type.contains("cbz") || type.contains("epub")
            }
            let navigation = links.first {
                let rel = $0.attributes?.rel ?? ""
                return rel.contains("subsection") || rel == "alternate"
            }
            let href = acquisition?.attributes?.href ?? navigation?.attributes?.href ?? links.first?.attributes?.href
            guard let href, let absolute = absoluteURL(href, relativeTo: url) else { return nil }
            let isDir = acquisition == nil
            return RemoteEntry(
                name: title,
                path: absolute.absoluteString,
                isDirectory: isDir,
                size: acquisition?.attributes?.length,
                downloadURL: isDir ? nil : absolute
            )
        }
    }

    static func download(source: RemoteSource, entry: RemoteEntry, to local: URL) async throws {
        guard let url = entry.downloadURL ?? URL(string: entry.path) else {
            throw RemoteError.notConfigured
        }
        var request = URLRequest(url: url)
        applyAuth(&request, source: source)
        let (temp, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw RemoteError.requestFailed(AppCopy.opdsDownloadFailed)
        }
        try? FileManager.default.removeItem(at: local)
        try FileManager.default.moveItem(at: temp, to: local)
    }

    private static func feedURL(source: RemoteSource, path: String) throws -> URL {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            guard let u = URL(string: path) else { throw RemoteError.invalidURL }
            return u
        }
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
                let base = host.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let part = source.shareOrPath.hasPrefix("/") ? source.shareOrPath : "/" + source.shareOrPath
                guard let u = URL(string: base + part) else { throw RemoteError.invalidURL }
                return u
            }
            guard let u = URL(string: host) else { throw RemoteError.invalidURL }
            return u
        }
        let base = host.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let part = path.hasPrefix("/") ? path : "/" + path
        guard let u = URL(string: base + part) else { throw RemoteError.invalidURL }
        return u
    }

    private static func absoluteURL(_ href: String, relativeTo base: URL) -> URL? {
        if href.hasPrefix("http://") || href.hasPrefix("https://") {
            return URL(string: href)
        }
        return URL(string: href, relativeTo: base)?.absoluteURL
    }

    private static func applyAuth(_ request: inout URLRequest, source: RemoteSource) {
        guard !source.username.isEmpty else { return }
        let raw = "\(source.username):\(source.password)"
        request.setValue("Basic \(Data(raw.utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")
    }
}
