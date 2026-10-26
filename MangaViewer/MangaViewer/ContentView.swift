import SwiftUI

struct ContentView: View {
    @StateObject private var library = LibraryStore.shared

    @State private var selectedVolume: MangaVolume?

    var body: some View {
        NavigationStack {
            LibraryView(library: library) { volume in
                selectedVolume = volume
            }
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) {
            ActivityOverlayView()
        }
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
