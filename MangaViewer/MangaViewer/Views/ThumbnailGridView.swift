import SwiftUI

struct ThumbnailGridView: View {
    let volume: MangaVolume
    let currentPage: Int
    var onSelect: (Int) -> Void

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 8)]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(0..<volume.pageCount, id: \.self) { index in
                        Button {
                            onSelect(index)
                        } label: {
                            VStack(spacing: 4) {
                                Group {
                                    if let url = volume.pageURL(at: index),
                                       let image = SampleImage.load(url: url) {
                                        image.resizable().scaledToFill()
                                    } else {
                                        Rectangle().fill(Color.secondary.opacity(0.2))
                                    }
                                }
                                .frame(width: 72, height: 108)
                                .clipped()
                                .overlay {
                                    if index == currentPage {
                                        RoundedRectangle(cornerRadius: 2)
                                            .stroke(Color.accentColor, lineWidth: 2)
                                    }
                                }
                                Text("\(index + 1)")
                                    .font(.caption2)
                                    .foregroundStyle(index == currentPage ? Color.accentColor : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .padding()
            }
            .onAppear {
                proxy.scrollTo(currentPage, anchor: .center)
            }
        }
        .navigationTitle("ページ一覧")
        .navigationBarTitleDisplayMode(.inline)
    }
}
