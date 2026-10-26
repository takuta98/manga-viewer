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
                            Color.clear
                                .aspectRatio(2 / 3, contentMode: .fit)
                                .overlay {
                                    if let url = volume.pageURL(at: i),
                                       let img = UIImage(contentsOfFile: url.path) {
                                        Image(uiImage: img)
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Rectangle().fill(Color.secondary.opacity(0.3))
                                    }
                                }
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .overlay(alignment: .bottom) {
                                    Text("\(i + 1)")
                                        .font(.caption2)
                                        .padding(4)
                                        .frame(maxWidth: .infinity)
                                        .background(.black.opacity(0.55))
                                        .foregroundStyle(.white)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("サムネイル")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.close) { dismiss() }
                }
            }
        }
    }
}
