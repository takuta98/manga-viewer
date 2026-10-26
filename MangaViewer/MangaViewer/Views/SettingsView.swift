import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var prefs = AppSettingsStore.loadPrefs()

    var body: some View {
        NavigationStack {
            Form {
                Section("読み方") {
                    Picker("方向", selection: $prefs.direction) {
                        ForEach(ReadingDirection.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("ページ", selection: $prefs.layoutMode) {
                        ForEach(PageLayoutMode.allCases) { Text($0.label).tag($0) }
                    }
                    Text(DisplayLayoutResolver.explainsToUser).font(.footnote).foregroundStyle(.secondary)
                    Picker("ページ送り", selection: $prefs.turnStyle) {
                        ForEach(PageTurnStyle.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("表紙を単独表示", isOn: $prefs.coverAlone)
                }
                Section("表示") {
                    Toggle("読んでいる間はスリープしない", isOn: $prefs.keepScreenOn)
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { AppSettingsStore.savePrefs(prefs); dismiss() }
                }
            }
            .onChange(of: prefs) { _, v in AppSettingsStore.savePrefs(v) }
        }
    }
}
