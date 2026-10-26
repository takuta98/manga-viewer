import Foundation
import Combine

@MainActor
final class RemoteSourceStore: ObservableObject {
    static let shared = RemoteSourceStore()
    @Published private(set) var sources: [RemoteSource] = []

    private var fileURL: URL {
        Catalog.root.appendingPathComponent("remote-sources.json")
    }

    init() { load() }

    func add(_ source: RemoteSource) {
        var s = source
        KeychainStore.save(password: s.password, for: s.id)
        s.password = ""
        sources.append(s)
        persist()
    }

    func update(_ source: RemoteSource) {
        guard let i = sources.firstIndex(where: { $0.id == source.id }) else { return }
        var s = source
        if !source.password.isEmpty {
            KeychainStore.save(password: source.password, for: source.id)
        }
        s.password = ""
        sources[i] = s
        persist()
    }

    func delete(_ source: RemoteSource) {
        sources.removeAll { $0.id == source.id }
        KeychainStore.delete(for: source.id)
        persist()
    }

    func hydrated(_ source: RemoteSource) -> RemoteSource {
        var s = source
        s.password = KeychainStore.load(for: source.id)
        return s
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([RemoteSource].self, from: data) else { return }
        sources = list
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(sources) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
