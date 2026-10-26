import Foundation
import AMSMB2

enum SMBClientService {
    static func list(source: RemoteSource, path: String) async throws -> [RemoteEntry] {
        let endpoint = try Endpoint.resolve(source)
        let target = try resolveTarget(endpoint: endpoint, path: path)

        if target.share.isEmpty {
            return try await listAvailableShares(endpoint)
        }

        return try await SMBShareSession.shared.withConnected(endpoint: endpoint, share: target.share) { manager in
            let files = try await manager.contentsOfDirectory(atPath: target.directory)
            return files.compactMap { entry -> RemoteEntry? in
                guard let name = entry[.nameKey] as? String else { return nil }
                if name == "." || name == ".." { return nil }
                let childInside = target.directory.isEmpty ? name : "\(target.directory)/\(name)"
                let childPath = composePath(share: target.share, inside: childInside, shareFixed: !endpoint.share.isEmpty)
                let type = entry[.fileResourceTypeKey] as? URLFileResourceType
                let isDir = type == .directory
                let size = entry[.fileSizeKey] as? Int64
                return RemoteEntry(name: name, path: childPath, isDirectory: isDir, size: size)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    static func download(source: RemoteSource, path: String, to local: URL) async throws {
        let endpoint = try Endpoint.resolve(source)
        let target = try resolveTarget(endpoint: endpoint, path: path)
        guard !target.share.isEmpty else {
            throw RemoteError.requestFailed("フォルダを選んでからファイルを取り込んでください")
        }
        try await SMBShareSession.shared.withConnected(endpoint: endpoint, share: target.share) { manager in
            // 大きな CBZ をメモリに載せないよう、ディスクへ直接ストリームする。
            // AMSMB2 の OutputStream(url:append:false) は既存ファイルだと nil になるため、作らずに渡す。
            try? FileManager.default.removeItem(at: local)
            do {
                try await manager.downloadItem(atPath: target.directory, to: local, progress: nil)
            } catch {
                try? FileManager.default.removeItem(at: local)
                throw error
            }
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
                size: nil
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func fetchShares(_ endpoint: Endpoint) async throws -> [(name: String, comment: String)] {
        // 共有一覧は専用接続。キャッシュ中の share セッションとは分離する。
        let manager = try makeManager(endpoint)
        do {
            let shares = try await manager.listShares(enumerateHidden: false)
            try? await manager.disconnectShare()
            let filtered = shares.filter { share in
                let name = share.name
                if name.isEmpty { return false }
                if name.hasSuffix("$") { return false }
                let lower = name.lowercased()
                return lower != "ipc$" && lower != "print$"
            }
            return filtered
        } catch {
            try? await manager.disconnectShare()
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

    fileprivate static func connect(_ manager: SMB2Manager, share: String) async throws {
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

    fileprivate static func makeManager(_ endpoint: Endpoint) throws -> SMB2Manager {
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

    fileprivate static func mapError(_ error: Error) -> RemoteError {
        if let remote = error as? RemoteError { return remote }
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

        var sessionKey: String {
            "\(urlString)|\(domain)|\(username)|\(password)"
        }

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
            if port != 445 {
                urlString = "smb://\(hostField):\(port)"
            }

            var domain = source.domain.trimmingCharacters(in: .whitespacesAndNewlines)
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

/// 同一 NAS / 共有への連続 list・download で TCP/SMB を張り直さない。
private actor SMBShareSession {
    static let shared = SMBShareSession()

    private struct Slot {
        let endpointKey: String
        let share: String
        let manager: SMB2Manager
        var lastUsed: Date
    }

    private var slot: Slot?
    private let idleTTL: TimeInterval = 90

    func withConnected<T>(
        endpoint: SMBClientService.Endpoint,
        share: String,
        _ body: (SMB2Manager) async throws -> T
    ) async throws -> T {
        let manager = try await acquire(endpoint: endpoint, share: share)
        do {
            let value = try await body(manager)
            if var current = slot,
               current.endpointKey == endpoint.sessionKey,
               current.share == share {
                current.lastUsed = Date()
                slot = current
            }
            return value
        } catch {
            await invalidate()
            throw SMBClientService.mapError(error)
        }
    }

    private func acquire(endpoint: SMBClientService.Endpoint, share: String) async throws -> SMB2Manager {
        if let current = slot {
            if current.endpointKey == endpoint.sessionKey,
               current.share == share,
               Date().timeIntervalSince(current.lastUsed) < idleTTL {
                return current.manager
            }
            await drop(current.manager)
            slot = nil
        }

        let manager = try SMBClientService.makeManager(endpoint)
        do {
            try await SMBClientService.connect(manager, share: share)
        } catch {
            try? await manager.disconnectShare()
            throw error
        }
        slot = Slot(endpointKey: endpoint.sessionKey, share: share, manager: manager, lastUsed: Date())
        return manager
    }

    private func invalidate() async {
        guard let current = slot else { return }
        slot = nil
        await drop(current.manager)
    }

    private func drop(_ manager: SMB2Manager) async {
        try? await manager.disconnectShare()
    }
}
