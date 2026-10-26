import Foundation
import FilesProvider

enum FTPClient {
    static func list(source: RemoteSource, path: String) async throws -> [RemoteEntry] {
        let provider = try makeProvider(source)
        let dir = path.isEmpty ? (source.shareOrPath.isEmpty ? "/" : source.shareOrPath) : path
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
            let base = dir.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let child = base.isEmpty ? name : "\(base)/\(name)"
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

    private static func makeProvider(_ source: RemoteSource) throws -> FTPFileProvider {
        guard let url = baseURL(source) else { throw RemoteError.invalidURL }
        let credential: URLCredential? = source.username.isEmpty
            ? nil
            : URLCredential(user: source.username, password: source.password, persistence: .forSession)
        guard let provider = FTPFileProvider(baseURL: url, mode: .default, credential: credential) else {
            throw RemoteError.requestFailed("FTP クライアントを初期化できません")
        }
        return provider
    }

    private static func baseURL(_ source: RemoteSource) -> URL? {
        var host = source.host.trimmingCharacters(in: .whitespacesAndNewlines)
        host = host.replacingOccurrences(of: "ftps://", with: "", options: .caseInsensitive)
        host = host.replacingOccurrences(of: "ftp://", with: "", options: .caseInsensitive)
        guard !host.isEmpty else { return nil }
        let scheme = source.useTLS ? "ftps" : "ftp"
        let port = source.port > 0 ? source.port : (source.useTLS ? 990 : 21)
        var s = "\(scheme)://\(host):\(port)/"
        let root = source.shareOrPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !root.isEmpty { s = "\(scheme)://\(host):\(port)/\(root)/" }
        return URL(string: s)
    }
}
