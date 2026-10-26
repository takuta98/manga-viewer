import SwiftUI

struct ContentView: View {
    @State private var selectedVolume: MangaVolume?

    var body: some View {
        NavigationStack {
            LibraryView { volume in
                selectedVolume = volume
            }
            .navigationDestination(item: $selectedVolume) { volume in
                ReaderView(volume: volume)
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
