import Foundation
import AMSMB2

/// NAS (SMB) の1接続先。ホストへ接続し、共有名を列挙して選んでからブラウズする。
struct SMBEntry: Identifiable, Hashable {
    var id: String { path }
    var name: String
    /// 共有ルートからの相対パス。
    var path: String
    var isDirectory: Bool
    var size: Int64?
}

final class SMBClient {
    let settings: SMBServerSettings
    private let password: String
    private var manager: SMB2Manager?
    private var connected = false

    init(settings: SMBServerSettings, password: String) throws {
        let host = settings.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { throw SMBError.notConfigured }
        var s = settings
        s.host = host
        self.settings = s
        self.password = password
    }

    // MARK: - 共有

    /// 接続先が公開している共有名の一覧（隠し共有は除く）。
    func listShares() async throws -> [String] {
        let manager = try await connection()
        do {
            return try await manager.listShares(enumerateHidden: false)
                .map { $0.name }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        } catch {
            throw Self.mapError(error)
        }
    }

    /// 使う共有を選んで接続。以後 list/download が使える。
    func useShare(_ name: String) async throws {
        let manager = try await connection()
        do {
            try await manager.connectShare(name: name, encrypted: false)
        } catch {
            do {
                try await manager.connectShare(name: name, encrypted: true)
            } catch {
                throw Self.mapError(error)
            }
        }
        share = name
    }

    var share: String?

    // MARK: - 一覧

    /// path は共有ルートからの相対パス（"" でルート）。
    func list(path: String) async throws -> [SMBEntry] {
        guard share != nil else { throw SMBError.noShareSelected }
        let manager = try await connection()
        let dir = Self.clean(path)
        do {
            let items = try await manager.contentsOfDirectory(atPath: dir.isEmpty ? "/" : dir)
            return items.compactMap { entry -> SMBEntry? in
                guard let name = entry[.nameKey] as? String,
                      name != ".", name != ".." else { return nil }
                let child = dir.isEmpty ? name : "\(dir)/\(name)"
                let isDir = (entry[.fileResourceTypeKey] as? URLFileResourceType) == .directory
                return SMBEntry(
                    name: name,
                    path: child,
                    isDirectory: isDir,
                    size: entry[.fileSizeKey] as? Int64
                )
            }
            .sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        } catch {
            throw Self.mapError(error)
        }
    }

    // MARK: - ダウンロード

    /// ファイル1本をローカルURLへ保存。
    func download(remotePath: String, to local: URL) async throws {
        guard share != nil else { throw SMBError.noShareSelected }
        let manager = try await connection()
        try? FileManager.default.removeItem(at: local)
        try FileManager.default.createDirectory(
            at: local.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            try await manager.downloadItem(atPath: remotePath, to: local, progress: nil)
        } catch {
            try? FileManager.default.removeItem(at: local)
            throw Self.mapError(error)
        }
    }

    /// フォルダー配下を再帰で列挙（ファイルのみ）。
    func filesRecursively(path: String) async throws -> [SMBEntry] {
        var out: [SMBEntry] = []
        var queue = [path]
        while let dir = queue.popLast() {
            for entry in try await list(path: dir) {
                if entry.isDirectory {
                    queue.append(entry.path)
                } else {
                    out.append(entry)
                }
            }
        }
        return out.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func disconnect() async {
        guard let manager else { return }
        try? await manager.disconnectShare()
        connected = false
    }

    // MARK: - 接続

    private func connection() async throws -> SMB2Manager {
        if let manager, connected { return manager }
        guard let url = URL(string: "smb://\(settings.host)") else {
            throw SMBError.invalidHost
        }
        let user = settings.username.isEmpty ? "guest" : settings.username
        let credential = URLCredential(user: user, password: password, persistence: .forSession)
        guard let manager = SMB2Manager(url: url, domain: "", credential: credential) else {
            throw SMBError.connectFailed("SMBクライアントを作れませんでした")
        }
        manager.timeout = 20
        self.manager = manager
        connected = true
        return manager
    }

    private static func clean(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func mapError(_ error: Error) -> Error {
        if let e = error as? SMBError { return e }
        let detail = (error as NSError).localizedDescription
        return SMBError.requestFailed(detail)
    }
}

enum SMBError: LocalizedError {
    case notConfigured
    case invalidHost
    case noShareSelected
    case connectFailed(String)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "サーバーを設定してください"
        case .invalidHost: return "ホスト名が不正です"
        case .noShareSelected: return "共有を選んでください"
        case .connectFailed(let d): return "接続できません: \(d)"
        case .requestFailed(let d): return "失敗しました: \(d)"
        }
    }
}
