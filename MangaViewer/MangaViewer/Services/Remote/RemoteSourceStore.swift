import Foundation
import Combine

@MainActor
final class RemoteSourceStore: ObservableObject {
    static let shared = RemoteSourceStore()

    @Published private(set) var sources: [RemoteSource] = []

    private let url: URL
    private let fm = FileManager.default

    init() {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = docs.appendingPathComponent("remote-sources.json")
        load()
    }

    func add(_ source: RemoteSource) {
        sources.removeAll { $0.id == source.id }
        sources.insert(source, at: 0)
        save()
    }

    func update(_ source: RemoteSource) {
        guard let idx = sources.firstIndex(where: { $0.id == source.id }) else {
            add(source)
            return
        }
        sources[idx] = source
        save()
    }

    func delete(_ source: RemoteSource) {
        sources.removeAll { $0.id == source.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([RemoteSource].self, from: data) else {
            sources = []
            return
        }
        sources = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sources) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
