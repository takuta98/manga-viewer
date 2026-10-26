import Foundation
import FilesProvider

enum WebDAVClient {
    static func list(source: RemoteSource, path: String) async throws -> [RemoteEntry] {
        let provider = try makeProvider(source)
        let dir = normalizedPath(path)
        let files = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[FileObject], Error>) in
            provider.contentsOfDirectory(path: dir) { contents, error in
                if let error {
                    cont.resume(throwing: RemoteError.requestFailed(error.localizedDescription))
                } else {
                    cont.resume(returning: contents)
                }
            }
        }
        return files.compactMap { file -> RemoteEntry? in
            let name = file.name
            if name == "." || name == ".." || name.isEmpty { return nil }
            let child = dir.isEmpty || dir == "/" ? name : "\(dir.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/\(name)"
            return RemoteEntry(name: name, path: child, isDirectory: file.isDirectory, size: file.size)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func download(source: RemoteSource, entry: RemoteEntry, to dest: URL) async throws {
        let provider = try makeProvider(source)
        try? FileManager.default.removeItem(at: dest)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            _ = provider.copyItem(path: entry.path, toLocalURL: dest) { error in
                if let error {
                    cont.resume(throwing: RemoteError.requestFailed(error.localizedDescription))
                } else {
                    cont.resume()
                }
            }
        }
    }

    private static func makeProvider(_ source: RemoteSource) throws -> WebDAVFileProvider {
        guard let url = baseURL(source) else { throw RemoteError.invalidURL }
        let credential: URLCredential? = source.username.isEmpty
            ? nil
            : URLCredential(user: source.username, password: source.password, persistence: .forSession)
        guard let provider = WebDAVFileProvider(baseURL: url, credential: credential) else {
            throw RemoteError.requestFailed(AppCopy.webdavInitFailed)
        }
        return provider
    }

    private static func baseURL(_ source: RemoteSource) -> URL? {
        var host = source.host.trimmingCharacters(in: .whitespacesAndNewlines)
        host = host.replacingOccurrences(of: "https://", with: "", options: .caseInsensitive)
        host = host.replacingOccurrences(of: "http://", with: "", options: .caseInsensitive)
        guard !host.isEmpty else { return nil }
        let scheme = source.useTLS ? "https" : "http"
        var base = "\(scheme)://\(host)"
        if source.port > 0, source.port != (source.useTLS ? 443 : 80) {
            if !host.contains(":") {
                base = "\(scheme)://\(host):\(source.port)"
            }
        }
        let root = source.shareOrPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !root.isEmpty { base += "/\(root)" }
        if !base.hasSuffix("/") { base += "/" }
        return URL(string: base)
    }

    private static func normalizedPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? "/" : trimmed
    }
}
