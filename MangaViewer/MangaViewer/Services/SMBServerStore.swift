import Foundation

/// SMB 接続先。ホスト・ユーザーは UserDefaults に一覧で保存、パスワードは Keychain。
/// 共有名は保存せず、接続後に列挙して選ぶ。
struct SMBServerSettings: Codable, Equatable, Identifiable {
    var host: String = ""
    var username: String = ""

    var id: String { "\(username)@\(host)" }
    var label: String { username.isEmpty ? host : "\(username)@\(host)" }
}

enum SMBServerStore {
    private static let defaultsKey = "manga-viewer.smb-servers.v2"
    private static let legacyKey = "manga-viewer.smb-server.v1"
    private static let legacyPasswordAccount = "smb-default"

    /// 保存済み接続先の一覧。旧形式の1件分があれば先頭に載せる。
    static func all() -> [SMBServerSettings] {
        var list = decodeList(UserDefaults.standard.data(forKey: defaultsKey))
        if let legacy = loadLegacy(), !list.contains(legacy) {
            list.insert(legacy, at: 0)
        }
        return list
    }

    static func password(for settings: SMBServerSettings) -> String {
        let stored = KeychainStore.load(account: account(for: settings))
        if !stored.isEmpty { return stored }
        return KeychainStore.load(account: legacyPasswordAccount)
    }

    /// 接続先を保存し、パスワードがあれば Keychain に入れる。
    static func save(_ settings: SMBServerSettings, password: String) {
        var list = decodeList(UserDefaults.standard.data(forKey: defaultsKey))
        list.removeAll { $0 == settings }
        list.insert(settings, at: 0)
        persist(list)
        if !password.isEmpty {
            KeychainStore.save(password: password, account: account(for: settings))
        }
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: legacyKey)
        }
    }

    static func remove(_ settings: SMBServerSettings) {
        var list = decodeList(UserDefaults.standard.data(forKey: defaultsKey))
        list.removeAll { $0 == settings }
        persist(list)
        KeychainStore.delete(account: account(for: settings))
    }

    /// 互換のため残す単発アクセス。一覧の先頭を返す。
    static func load() -> SMBServerSettings {
        all().first ?? SMBServerSettings()
    }

    static func loadPassword() -> String {
        KeychainStore.load(account: legacyPasswordAccount)
    }

    static func makeClient() throws -> SMBClient {
        let settings = load()
        return try SMBClient(settings: settings, password: password(for: settings))
    }

    private static func account(for settings: SMBServerSettings) -> String {
        "smb-" + settings.id
    }

    private static func decodeList(_ data: Data?) -> [SMBServerSettings] {
        guard let data,
              let list = try? JSONDecoder().decode([SMBServerSettings].self, from: data)
        else { return [] }
        return list
    }

    private static func persist(_ list: [SMBServerSettings]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private static func loadLegacy() -> SMBServerSettings? {
        guard let data = UserDefaults.standard.data(forKey: legacyKey),
              let settings = try? JSONDecoder().decode(SMBServerSettings.self, from: data),
              !settings.host.isEmpty
        else { return nil }
        return settings
    }
}
