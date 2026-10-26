import SwiftUI

struct VolumeInfoView: View {
    let volume: MangaVolume
    @Environment(\.dismiss) private var dismiss

    private var prefs: ReaderPreferences { AppSettingsStore.loadPrefs() }

    private var progressPercent: Int {
        ProgressStore.shared.progressPercent(
            for: volume,
            coverAlone: prefs.coverAlone,
            layout: prefs.layoutMode
        )
    }

    private var importedAtText: String {
        volume.importedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("タイトル", value: volume.title)
                    LabeledContent("ページ", value: "\(volume.pageCount)")
                    LabeledContent("方向", value: volume.direction.label)
                    LabeledContent("進捗", value: "\(progressPercent)%")
                    LabeledContent("取り込み", value: importedAtText)
                }
            }
            .navigationTitle("作品情報")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
