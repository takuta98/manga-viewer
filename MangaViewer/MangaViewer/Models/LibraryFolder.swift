import Foundation

struct LibraryFolder: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String
    var createdAt: Date
}
