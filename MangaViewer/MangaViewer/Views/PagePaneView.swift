import SwiftUI

struct PagePaneView: View {
    let url: URL?
    let pageNumber: Int
    let fitMode: PageFitMode

    var body: some View {
        GeometryReader { geo in
            if let url, let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: fitMode == .fitWidth ? .fit : .fit)
                    .frame(width: geo.size.width, height: geo.size.height)
            } else {
                Color.black.overlay(Text("\(pageNumber)").foregroundStyle(.white.opacity(0.4)))
            }
        }
        .background(Color.black)
    }
}
