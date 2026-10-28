import Foundation

/// NAS (SMB) 接続先。ホスト・共有名・ユーザーは UserDefaults、パスワードは Keychain。
struct SMBServerSettings: Codable, Equatable {
    var host: String = ""
    var share: String = ""
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
        let settings = load()
        return try SMBClient(settings: settings, password: loadPassword())
    }
}
