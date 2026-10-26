import Foundation
import AMSMB2

enum SMBClientService {
    static func list(source: RemoteSource, path: String) async throws -> [RemoteEntry] {
        let endpoint = try Endpoint.resolve(source)
        let target = try resolveTarget(endpoint: endpoint, path: path)

        if target.share.isEmpty {
            return try await listAvailableShares(endpoint)
        }

        let manager = try makeManager(endpoint)
        try await connect(manager, share: target.share)
        do {
            let files = try await manager.contentsOfDirectory(atPath: target.directory)
            try? await manager.disconnectShare()
            return files.compactMap { entry -> RemoteEntry? in
                guard let name = entry[.nameKey] as? String else { return nil }
                if name == "." || name == ".." { return nil }
                let childInside = target.directory.isEmpty ? name : "\(target.directory)/\(name)"
                let childPath = composePath(share: target.share, inside: childInside, shareFixed: !endpoint.share.isEmpty)
                let type = entry[.fileResourceTypeKey] as? URLFileResourceType
                let isDir = type == .directory
                let size = entry[.fileSizeKey] as? Int64
                return RemoteEntry(name: name, path: childPath, isDirectory: isDir, size: size, downloadURL: nil)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            try? await manager.disconnectShare()
            throw mapError(error)
        }
    }

    static func download(source: RemoteSource, path: String, to local: URL) async throws {
        let endpoint = try Endpoint.resolve(source)
        let target = try resolveTarget(endpoint: endpoint, path: path)
        guard !target.share.isEmpty else {
            throw RemoteError.requestFailed("フォルダを選んでからファイルを取り込んでください")
        }
        let manager = try makeManager(endpoint)
        try await connect(manager, share: target.share)
        do {
            let data = try await manager.contents(atPath: target.directory)
            try data.write(to: local)
            try? await manager.disconnectShare()
        } catch {
            try? await manager.disconnectShare()
            throw mapError(error)
        }
    }

    /// IP だけで届くか確認。フォルダ名は不要。
    static func testConnection(source: RemoteSource) async throws {
        let endpoint = try Endpoint.resolve(source)
        let shares = try await fetchShares(endpoint)
        if shares.isEmpty {
            throw RemoteError.requestFailed("接続はできましたが、見えるフォルダがありません。ユーザー権限を確認してください。")
        }
    }

    // MARK: - Shares

    private static func listAvailableShares(_ endpoint: Endpoint) async throws -> [RemoteEntry] {
        let shares = try await fetchShares(endpoint)
        return shares.map { share in
            RemoteEntry(
                name: share.comment.isEmpty ? share.name : "\(share.name)（\(share.comment)）",
                path: share.name,
                isDirectory: true,
                size: nil,
                downloadURL: nil
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func fetchShares(_ endpoint: Endpoint) async throws -> [(name: String, comment: String)] {
        let manager = try makeManager(endpoint)
        do {
            let shares = try await manager.listShares(enumerateHidden: false)
            let filtered = shares.filter { share in
                let name = share.name
                if name.isEmpty { return false }
                if name.hasSuffix("$") { return false }
                let lower = name.lowercased()
                return lower != "ipc$" && lower != "print$"
            }
            return filtered
        } catch {
            throw mapError(error)
        }
    }

    // MARK: - Path / target

    private struct Target {
        var share: String
        var directory: String
    }

    private static func resolveTarget(endpoint: Endpoint, path: String) throws -> Target {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !endpoint.share.isEmpty {
            let dir = joinedPath(endpoint.pathInsideShare, trimmed)
            return Target(share: endpoint.share, directory: dir)
        }
        if trimmed.isEmpty {
            return Target(share: "", directory: "")
        }
        let parts = trimmed.split(separator: "/").map(String.init)
        let share = parts[0]
        let directory = parts.dropFirst().joined(separator: "/")
        return Target(share: share, directory: directory)
    }

    private static func composePath(share: String, inside: String, shareFixed: Bool) -> String {
        if shareFixed {
            return inside
        }
        if inside.isEmpty { return share }
        return "\(share)/\(inside)"
    }

    private static func joinedPath(_ base: String, _ path: String) -> String {
        let a = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let b = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return "\(a)/\(b)"
    }

    // MARK: - Connection

    private static func connect(_ manager: SMB2Manager, share: String) async throws {
        do {
            try await manager.connectShare(name: share, encrypted: false)
        } catch {
            do {
                try await manager.connectShare(name: share, encrypted: true)
            } catch {
                throw mapError(error)
            }
        }
    }

    private static func makeManager(_ endpoint: Endpoint) throws -> SMB2Manager {
        guard let url = URL(string: endpoint.urlString) else {
            throw RemoteError.invalidURL
        }
        let user = endpoint.username.isEmpty ? "guest" : endpoint.username
        let credential = URLCredential(
            user: user,
            password: endpoint.password,
            persistence: .forSession
        )
        guard let manager = SMB2Manager(url: url, domain: endpoint.domain, credential: credential) else {
            throw RemoteError.requestFailed("SMB クライアントを初期化できません（IP の形式を確認してください）")
        }
        manager.timeout = 20
        return manager
    }

    private static func mapError(_ error: Error) -> RemoteError {
        let ns = error as NSError
        let detail = ns.localizedDescription
        let lower = detail.lowercased()
        if lower.contains("permission") || lower.contains("access") || ns.code == 13 {
            return .requestFailed("ログインできませんでした。ユーザー名とパスワードを確認してください。\n\(detail)")
        }
        if lower.contains("not found") || lower.contains("no such") || ns.code == 2 {
            return .requestFailed("フォルダが見つかりません。\n\(detail)")
        }
        if lower.contains("timed out") || lower.contains("timeout") || lower.contains("host is down") {
            return .requestFailed("NAS に届きません。同じ Wi‑Fi か、IP が合っているか、ローカルネットワーク許可を確認してください。\n\(detail)")
        }
        if lower.contains("connection") || lower.contains("refused") || lower.contains("unreachable") {
            return .requestFailed("接続できませんでした。IP と、NAS 側の SMB が有効かを確認してください。\n\(detail)")
        }
        return .requestFailed("接続エラー: \(detail)")
    }

    // MARK: - Endpoint parsing

    struct Endpoint {
        var urlString: String
        /// 空なら接続後にフォルダ一覧を出す。
        var share: String
        var pathInsideShare: String
        var username: String
        var password: String
        var domain: String

        static func resolve(_ source: RemoteSource) throws -> Endpoint {
            var hostField = source.host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !hostField.isEmpty else { throw RemoteError.notConfigured }

            hostField = hostField.replacingOccurrences(of: "smb://", with: "", options: .caseInsensitive)

            var username = source.username
            var password = source.password
            if let at = hostField.lastIndex(of: "@") {
                let cred = String(hostField[..<at])
                hostField = String(hostField[hostField.index(after: at)...])
                if let colon = cred.firstIndex(of: ":") {
                    if username.isEmpty { username = String(cred[..<colon]) }
                    if password.isEmpty { password = String(cred[cred.index(after: colon)...]) }
                } else if username.isEmpty {
                    username = cred
                }
            }

            var pathFromHost = ""
            if let slash = hostField.firstIndex(of: "/") {
                pathFromHost = String(hostField[hostField.index(after: slash)...])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                hostField = String(hostField[..<slash])
            }

            var port = source.port
            if !hostField.hasPrefix("["), hostField.filter({ $0 == ":" }).count == 1,
               let colon = hostField.lastIndex(of: ":") {
                let portPart = String(hostField[hostField.index(after: colon)...])
                if let p = Int(portPart), (1...65535).contains(p) {
                    port = p
                    hostField = String(hostField[..<colon])
                }
            }

            hostField = hostField.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !hostField.isEmpty else { throw RemoteError.invalidURL }

            var shareField = source.shareOrPath.trimmingCharacters(in: .whitespacesAndNewlines)
            shareField = shareField.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if shareField.isEmpty {
                shareField = pathFromHost
                pathFromHost = ""
            }

            let shareParts = shareField.split(separator: "/").map(String.init)
            let share = shareParts.first ?? ""
            var inside = shareParts.dropFirst().joined(separator: "/")
            if inside.isEmpty, !pathFromHost.isEmpty, !share.isEmpty {
                let pathParts = pathFromHost.split(separator: "/").map(String.init)
                if pathParts.first == share {
                    inside = pathParts.dropFirst().joined(separator: "/")
                } else {
                    inside = pathFromHost
                }
            }

            var urlString = "smb://\(hostField)"
            if let port, port != 445 {
                urlString = "smb://\(hostField):\(port)"
            }

            var domain = (source.domain ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if domain.isEmpty, username.contains(";") {
                let comps = username.split(separator: ";", maxSplits: 1).map(String.init)
                if comps.count == 2 {
                    domain = comps[0]
                    username = comps[1]
                }
            }

            return Endpoint(
                urlString: urlString,
                share: share,
                pathInsideShare: inside,
                username: username,
                password: password,
                domain: domain
            )
        }
    }
}
