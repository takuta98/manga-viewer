import SwiftUI

struct ContentView: View {
    @StateObject private var library = LibraryStore.shared
    @State private var selectedVolume: MangaVolume?

    var body: some View {
        NavigationStack {
            LibraryView(library: library) { volume in
                selectedVolume = volume
            }
            .navigationTitle("manga viewer")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $selectedVolume) { volume in
            ReaderView(
                library: library,
                volume: library.volumes.first(where: { $0.id == volume.id }) ?? volume
            )
        }
    }
}

#Preview {
    ContentView()
}
