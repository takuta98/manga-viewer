import SwiftUI

struct CoverThumbView: View {
    let imageURL: URL?
    var cornerRadius: CGFloat = 8

    var body: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                Group {
                    if let imageURL, let ui = UIImage(contentsOfFile: imageURL.path) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            Color.secondary.opacity(0.16)
                            Image(systemName: "book.closed")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct FolderThumbView: View {
    var body: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.yellow.opacity(0.16))
                    Image(systemName: "folder.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                }
            }
            .accessibilityHidden(true)
    }
}
