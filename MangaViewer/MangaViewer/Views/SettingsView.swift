import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var prefs = AppSettingsStore.loadPrefs()

    var body: some View {
        NavigationStack {
            Form {
                Section("読み方") {
                    Picker("方向", selection: $prefs.direction) {
                        ForEach(ReadingDirection.allCases) { dir in
                            Text(dir.label).tag(dir)
                        }
                    }
                    Picker("ページ", selection: $prefs.layoutMode) {
                        ForEach(PageLayoutMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    Picker("フィット", selection: $prefs.fitMode) {
                        ForEach(PageFitMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    Picker("ページ送り", selection: $prefs.turnStyle) {
                        ForEach(PageTurnStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    Toggle("表紙を単独表示", isOn: $prefs.coverAlone)
                }

                Section("表示") {
                    HStack {
                        Text("明るさ")
                        Slider(value: $prefs.brightness, in: 0.3...1.0)
                    }
                    Toggle("読んでいる間はスリープしない", isOn: $prefs.keepScreenOn)
                }

                Section {
                    Text("全体設定の「方向」は、これから取り込む作品の初期値です。作品ごとの方向は読書中の設定から変えられます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("ファイルの入れ方") {
                    Text("書庫の + から SMB / WebDAV / SFTP / FTP / OPDS / S3 / URL / Wi-Fi転送 / Files（iCloud・各クラウド）に対応。参考実装の対象: Andrea / Comink / KedaReader 系の取得経路。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        AppSettingsStore.savePrefs(prefs)
                        dismiss()
                    }
                }
            }
            .onChange(of: prefs) { _, newValue in
                AppSettingsStore.savePrefs(newValue)
            }
        }
    }
}
