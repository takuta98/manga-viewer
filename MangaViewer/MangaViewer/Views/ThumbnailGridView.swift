import SwiftUI

struct ThumbnailGridView: View {
    let volume: MangaVolume
    var onPick: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 10)], spacing: 10) {
                    ForEach(0..<volume.pageCount, id: \.self) { i in
                        Button { onPick(i) } label: {
                            VStack {
                                if let url = volume.pageURL(at: i), let img = UIImage(contentsOfFile: url.path) {
                                    Image(uiImage: img).resizable().scaledToFill()
                                } else {
                                    Rectangle().fill(Color.secondary.opacity(0.3))
                                }
                            }
                            .frame(height: 130).clipped().cornerRadius(4)
                            .overlay(alignment: .bottom) {
                                Text("\(i+1)").font(.caption2).padding(4).background(.black.opacity(0.6)).foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("サムネイル")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
        }
    }
}
