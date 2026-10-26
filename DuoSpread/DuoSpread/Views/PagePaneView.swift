import SwiftUI
import UIKit

struct PagePaneView: View {
    let imageName: String?
    let pageNumber: Int?
    var emptyLabel: String = "—"

    var body: some View {
        ZStack {
            Color("Paper")
            if let imageName, let image = SampleImage.load(named: imageName) {
                image
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(pageNumber.map { "Page \($0)" } ?? "Page")
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Color.primary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .frame(maxWidth: 220, maxHeight: 330)
                    .overlay {
                        Text(emptyLabel)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

enum SampleImage {
    static func load(named name: String) -> Image? {
        if let ui = UIImage(named: name) {
            return Image(uiImage: ui)
        }

        let subdirectories = [
            "SampleManga/night-station",
            "night-station",
            nil as String?
        ]

        for subdirectory in subdirectories {
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
