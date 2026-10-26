import Foundation

struct LibraryFolder: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var createdAt: Date

    static func make(name: String) -> LibraryFolder {
        LibraryFolder(id: UUID().uuidString, name: name, createdAt: Date())
    }
}
