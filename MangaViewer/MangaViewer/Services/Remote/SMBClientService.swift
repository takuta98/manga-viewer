import Foundation
import AMSMB2

enum SMBClientService {
    static func list(source: RemoteSource, path: String) async throws -> [RemoteEntry] {
        let endpoint = try Endpoint.resolve(source)
        let manager = try makeManager(endpoint)
        try await connect(manager, share: endpoint.share)

        let dir = joinedPath(endpoint.pathInsideShare, path)
        do {
            let files = try await manager.contentsOfDirectory(atPath: dir)
            try? await manager.disconnectShare()
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
        } catch {
            try? await manager.disconnectShare()
            throw mapError(error)
        }
    }

    static func download(source: RemoteSource, path: String, to local: URL) async throws {
        let endpoint = try Endpoint.resolve(source)
        let manager = try makeManager(endpoint)
        try await connect(manager, share: endpoint.share)
        do {
            let data = try await manager.contents(atPath: path)
            try data.write(to: local)
            try? await manager.disconnectShare()
        } catch {
            try? await manager.disconnectShare()
            throw mapError(error)
        }
    }

    /// 接続確認（共有ルートを一覧できるか）。
    static func testConnection(source: RemoteSource) async throws {
        let endpoint = try Endpoint.resolve(source)
        let manager = try makeManager(endpoint)
        try await connect(manager, share: endpoint.share)
        do {
            _ = try await manager.contentsOfDirectory(atPath: endpoint.pathInsideShare)
            try? await manager.disconnectShare()
        } catch {
            try? await manager.disconnectShare()
            throw mapError(error)
        }
    }

    // MARK: - Connection

    private static func connect(_ manager: SMB2Manager, share: String) async throws {
        do {
            try await manager.connectShare(name: share, encrypted: false)
        } catch {
            // Synology 等で SMB 暗号化必須の場合に再試行
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
            throw RemoteError.requestFailed("SMB クライアントを初期化できません（ホスト形式を確認してください）")
        }
        manager.timeout = 20
        return manager
    }

    private static func joinedPath(_ base: String, _ path: String) -> String {
        let a = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let b = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return "\(a)/\(b)"
    }

    private static func mapError(_ error: Error) -> RemoteError {
        let ns = error as NSError
        let detail = ns.localizedDescription
        let lower = detail.lowercased()
        if lower.contains("permission") || lower.contains("access") || ns.code == 13 {
            return .requestFailed("認証に失敗しました。ユーザー名・パスワード・共有のアクセス権を確認してください。\n\(detail)")
        }
        if lower.contains("not found") || lower.contains("no such") || ns.code == 2 {
            return .requestFailed("共有名またはパスが見つかりません。共有名（例: manga）を確認してください。\n\(detail)")
        }
        if lower.contains("timed out") || lower.contains("timeout") || lower.contains("host is down") {
            return .requestFailed("NAS に届きません。同一 Wi‑Fi・IP・ローカルネットワーク許可を確認してください。\n\(detail)")
        }
        if lower.contains("connection") || lower.contains("refused") || lower.contains("unreachable") {
            return .requestFailed("接続できませんでした。ホスト・ポート 445・SMB が有効かを確認してください。\n\(detail)")
        }
        return .requestFailed("SMB エラー: \(detail)")
    }

    // MARK: - Endpoint parsing

    struct Endpoint {
        var urlString: String
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
            // host:port（IPv6 は未対応の簡易分岐）
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
            guard let share = shareParts.first, !share.isEmpty else {
                throw RemoteError.requestFailed("共有名を入力してください（Synology / QNAP の共有フォルダ名。例: manga）")
            }
            var inside = shareParts.dropFirst().joined(separator: "/")
            if inside.isEmpty, !pathFromHost.isEmpty {
                // 共有は share 欄、ホスト URL 側に追加パスがある場合
                let pathParts = pathFromHost.split(separator: "/").map(String.init)
                if pathParts.first == share {
                    inside = pathParts.dropFirst().joined(separator: "/")
                } else if shareField == share {
                    inside = pathFromHost
                }
            }

            var urlString = "smb://\(hostField)"
            if let port, port != 445 {
                urlString = "smb://\(hostField):\(port)"
            }

            var domain = (source.domain ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // DOMAIN\user / DOMAIN;user を分解
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
