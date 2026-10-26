import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryStore
    @State private var prefs = AppSettingsStore.loadPrefs()
    @State private var displayMode = AppSettingsStore.loadLibraryDisplayMode()
    var onDisplayModeChange: ((LibraryDisplayMode) -> Void)?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(AppCopy.readingDirection, selection: $prefs.direction) {
                        ForEach(ReadingDirection.allCases) { Text($0.label).tag($0) }
                    }
                    Picker(AppCopy.pageLayout, selection: $prefs.layoutMode) {
                        ForEach(PageLayoutMode.allCases) { Text($0.label).tag($0) }
                    }
                    Text(DisplayLayoutResolver.explainsToUser)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Picker(AppCopy.pageTurn, selection: $prefs.turnStyle) {
                        ForEach(PageTurnStyle.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle(AppCopy.coverAlone, isOn: $prefs.coverAlone)
                    Picker(AppCopy.fit, selection: $prefs.fitMode) {
                        ForEach(PageFitMode.allCases) { Text($0.label).tag($0) }
                    }
                    VStack(alignment: .leading) {
                        Text(AppCopy.brightness)
                        Slider(value: $prefs.brightness, in: 0.35...1.0)
                    }
                } header: {
                    Text(AppCopy.settingsReadingDefaults)
                } footer: {
                    Text(AppCopy.settingsReadingFooter)
                }

                Section(AppCopy.settingsDisplay) {
                    Toggle(AppCopy.keepScreenOn, isOn: $prefs.keepScreenOn)
                }

                Section {
                    Picker(AppCopy.sort, selection: $library.sort) {
                        ForEach(LibrarySort.allCases) { Text($0.label).tag($0) }
                    }
                    Picker(AppCopy.displayMode, selection: $displayMode) {
                        ForEach(LibraryDisplayMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                } header: {
                    Text(AppCopy.settingsLibrary)
                } footer: {
                    Text(AppCopy.settingsLibraryFooter)
                }
            }
            .navigationTitle(AppCopy.settingsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.close) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    }
                    .accessibilityLabel(AppCopy.close)
                    .accessibilityValue(
                        "\(library.sort.label) · \(displayMode.label)"
                    )
                    .accessibilityHint(AppCopy.settingsLibraryFooter)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppCopy.done) {
                        AppSettingsStore.savePrefs(prefs)
                        AppSettingsStore.saveLibraryDisplayMode(displayMode)
                        onDisplayModeChange?(displayMode)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    }
                    .accessibilityLabel(AppCopy.done)
                    .accessibilityValue(
                        "\(library.sort.label) · \(displayMode.label)"
                    )
                    .accessibilityHint(AppCopy.settingsLibraryFooter)
                }
            }
            .onChange(of: prefs) { _, v in AppSettingsStore.savePrefs(v) }
            .onChange(of: displayMode) { _, v in
                AppSettingsStore.saveLibraryDisplayMode(v)
                onDisplayModeChange?(v)
            }
        }
    }
}
