import SwiftUI
import UIKit

struct PagePaneView: View {
    let url: URL?
    let pageNumber: Int?
    var fitMode: PageFitMode = .fitScreen

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let url, let uiImage = SampleImage.uiImage(url: url) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .accessibilityLabel(pageNumber.map { "Page \($0)" } ?? "Page")
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }
}

enum SampleImage {
    static func uiImage(url: URL) -> UIImage? {
        if let ui = UIImage(contentsOfFile: url.path) {
            return ui
        }
        let name = url.deletingPathExtension().lastPathComponent
        if let ui = UIImage(named: name) {
            return ui
        }
        if let bundled = Bundle.main.url(
            forResource: name,
            withExtension: url.pathExtension.isEmpty ? "png" : url.pathExtension,
            subdirectory: "SampleManga/sample"
        ) {
            return UIImage(contentsOfFile: bundled.path)
        }
        return nil
    }

    static func load(url: URL) -> Image? {
        uiImage(url: url).map { Image(uiImage: $0) }
    }

    static func load(named name: String) -> Image? {
        if let ui = UIImage(named: name) {
            return Image(uiImage: ui)
        }
        for subdirectory in ["SampleManga/sample", "sample", nil as String?] {
            let url: URL?
            if let subdirectory {
                url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: subdirectory)
            } else {
                url = Bundle.main.url(forResource: name, withExtension: "png")
            }
            if let url, let ui = UIImage(contentsOfFile: url.path) {
                return Image(uiImage: ui)
            }
        }
        return nil
    }
}
