import Foundation
import AMSMB2

enum SMBClientService {
    static func list(source: RemoteSource, path: String) async throws -> [RemoteEntry] {
        let manager = try makeManager(source)
        let share = shareName(source)
        try await manager.connectShare(name: share)
        defer { Task { try? await manager.disconnectShare() } }

        let dir = path.isEmpty ? "" : path
        let files = try await manager.contentsOfDirectory(atPath: dir)
        return files.compactMap { entry -> RemoteEntry? in
            guard let name = entry[.nameKey] as? String else { return nil }
            if name == "." || name == ".." { return nil }
            let childPath = dir.isEmpty ? name : "\(dir)/\(name)"
            let type = entry[.fileResourceTypeKey] as? URLFileResourceType
            let isDir = type == .directory
            let size = entry[.fileSizeKey] as? Int64
            return RemoteEntry(name: name, path: childPath, isDirectory: isDir, size: size, downloadURL: nil)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func download(source: RemoteSource, path: String, to local: URL) async throws {
        let manager = try makeManager(source)
        let share = shareName(source)
        try await manager.connectShare(name: share)
        defer { Task { try? await manager.disconnectShare() } }
        let data = try await manager.contents(atPath: path)
        try data.write(to: local)
    }

    private static func makeManager(_ source: RemoteSource) throws -> SMB2Manager {
        var host = source.host.trimmingCharacters(in: .whitespacesAndNewlines)
        host = host.replacingOccurrences(of: "smb://", with: "")
        if let slash = host.firstIndex(of: "/") {
            host = String(host[..<slash])
        }
        var urlString = "smb://\(host)"
        if let port = source.port, port != 445 {
            urlString = "smb://\(host):\(port)"
        }
        guard let url = URL(string: urlString) else { throw RemoteError.invalidURL }
        let credential = URLCredential(
            user: source.username.isEmpty ? "guest" : source.username,
            password: source.password,
            persistence: .forSession
        )
        guard let manager = SMB2Manager(url: url, credential: credential) else {
            throw RemoteError.requestFailed("SMB クライアントを初期化できません")
        }
        return manager
    }

    private static func shareName(_ source: RemoteSource) -> String {
        let raw = source.shareOrPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if raw.isEmpty { return "share" }
        return raw.split(separator: "/").first.map(String.init) ?? raw
    }
}
