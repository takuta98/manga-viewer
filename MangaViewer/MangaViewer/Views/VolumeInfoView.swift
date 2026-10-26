import SwiftUI

struct VolumeInfoView: View {
    let volume: MangaVolume
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                LabeledContent("タイトル", value: volume.title)
                LabeledContent("ページ数", value: "\(volume.pageCount)")
                LabeledContent("方向", value: volume.direction.label)
            }
            .navigationTitle("作品情報")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
        }
    }
}
