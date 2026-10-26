import SwiftUI

struct ContentView: View {
    @ObservedObject var library: LibraryStore
    @State private var reading: MangaVolume?

    var body: some View {
        NavigationStack {
            LibraryView(library: library) { volume in
                reading = volume
            }
        }
        .fullScreenCover(item: $reading) { volume in
            ReaderView(library: library, volume: volume)
        }
    }
}
