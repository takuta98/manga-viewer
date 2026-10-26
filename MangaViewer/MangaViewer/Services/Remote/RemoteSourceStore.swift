import Foundation
import Combine

@MainActor
final class RemoteSourceStore: ObservableObject {
    static let shared = RemoteSourceStore()

    @Published private(set) var sources: [RemoteSource] = []

    private let url: URL
    private let fm = FileManager.default

    init() {
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MangaViewer", isDirectory: true)
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        let modern = support.appendingPathComponent("remote-sources.json")
        let legacy = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("remote-sources.json")
        if fm.fileExists(atPath: modern.path) {
            url = modern
        } else if fm.fileExists(atPath: legacy.path) {
            url = modern
            try? fm.copyItem(at: legacy, to: modern)
        } else {
            url = modern
        }
        load()
    }

    func add(_ source: RemoteSource) {
        var s = source
        KeychainStore.savePassword(s.password, forSourceID: s.id)
        sources.removeAll { $0.id == s.id }
        sources.insert(s, at: 0)
        save()
    }

    func update(_ source: RemoteSource) {
        var s = source
        KeychainStore.savePassword(s.password, forSourceID: s.id)
        guard let idx = sources.firstIndex(where: { $0.id == s.id }) else {
            add(s)
            return
        }
        sources[idx] = s
        save()
    }

    func delete(_ source: RemoteSource) {
        KeychainStore.deletePassword(forSourceID: source.id)
        sources.removeAll { $0.id == source.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else {
            sources = []
            return
        }
        guard var decoded = try? JSONDecoder().decode([RemoteSource].self, from: data) else {
            // 壊れていてもファイルは消さない
            sources = []
            return
        }
        var migrated = false
        for i in decoded.indices {
            let id = decoded[i].id
            if !decoded[i].password.isEmpty {
                KeychainStore.savePassword(decoded[i].password, forSourceID: id)
                decoded[i].password = ""
                migrated = true
            }
            decoded[i].password = KeychainStore.loadPassword(forSourceID: id)
        }
        sources = decoded
        if migrated {
            save()
            // Documents の旧平文を削除
            let legacy = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("remote-sources.json")
            try? fm.removeItem(at: legacy)
        }
    }

    private func save() {
        // JSON にはパスワードを含めない（RemoteSource.encode）
        if let data = try? JSONEncoder().encode(sources) {
            try? data.write(to: url, options: .atomic)
        }
        for source in sources {
            KeychainStore.savePassword(source.password, forSourceID: source.id)
        }
    }
}
