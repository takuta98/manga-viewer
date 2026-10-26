import SwiftUI

@main
struct MangaViewerApp: App {
    @StateObject private var library = LibraryStore()

    var body: some Scene {
        WindowGroup {
            ContentView(library: library)
        }
    }
}
