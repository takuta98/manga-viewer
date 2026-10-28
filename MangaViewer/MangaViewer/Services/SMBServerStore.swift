import Foundation

/// NAS (SMB) 接続先。ホスト・ユーザーは UserDefaults、パスワードは Keychain。
/// 共有名は保存せず、接続後に列挙して選ぶ。
struct SMBServerSettings: Codable, Equatable {
    var host: String = ""
    var username: String = ""
}

enum SMBServerStore {
    private static let defaultsKey = "manga-viewer.smb-server.v1"
    private static let passwordAccount = "smb-default"

    static func load() -> SMBServerSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(SMBServerSettings.self, from: data)
        else { return SMBServerSettings() }
        return settings
    }

    static func loadPassword() -> String {
        KeychainStore.load(account: passwordAccount)
    }

    static func save(_ settings: SMBServerSettings, password: String) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        if !password.isEmpty {
            KeychainStore.save(password: password, account: passwordAccount)
        }
    }

    /// 保存済みの接続先とパスワードからクライアントを作る。
    static func makeClient() throws -> SMBClient {
        try SMBClient(settings: load(), password: loadPassword())
    }
}
