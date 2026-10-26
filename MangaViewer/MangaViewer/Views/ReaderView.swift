import SwiftUI
import UIKit

struct ReaderView: View {
    @ObservedObject var library: LibraryStore
    let volume: MangaVolume

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var prefs = AppSettingsStore.load()
    @State private var direction: ReadingDirection
    @State private var pageIndex = 0
    @State private var showChrome = false
    @State private var showSettings = false

    private let progress = ReadingProgress.shared

    init(library: LibraryStore, volume: MangaVolume) {
        self.library = library
        self.volume = volume
        _direction = State(initialValue: volume.direction)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if volume.pageCount <= 0 {
                    ContentUnavailableView("ページがありません", systemImage: "doc.questionmark")
                        .foregroundStyle(.white)
                } else {
                    PageBrowser(
                        pageCount: volume.pageCount,
                        index: $pageIndex,
                        style: prefs.turnStyle,
                        rtl: direction == .rtl,
                        reduceMotion: reduceMotion,
                        onToggleChrome: {
                            withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() }
                        }
                    ) { index in
                        AnyView(
                            PageImageView(
                                url: volume.pageURL(at: index),
                                pageNumber: index + 1,
                                fitMode: prefs.fitMode
                            )
                        )
                    }
                    .id("\(prefs.turnStyle.rawValue)-\(direction.rawValue)")
                    .opacity(prefs.brightness)
                }

                if showChrome {
                    chrome(safeTop: geo.safeAreaInsets.top, safeBottom: geo.safeAreaInsets.bottom)
                }
            }
        }
        .statusBarHidden(!showChrome)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            prefs = AppSettingsStore.load()
            pageIndex = min(progress.pageIndex(for: volume.id), max(volume.pageCount - 1, 0))
            UIApplication.shared.isIdleTimerDisabled = prefs.keepScreenOn
            showChrome = false
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: pageIndex) { _, value in
            progress.setPageIndex(value, for: volume.id)
        }
        .onChange(of: direction) { _, value in
            library.updateDirection(volume, direction: value)
        }
        .onChange(of: prefs) { _, value in
            AppSettingsStore.save(value)
            UIApplication.shared.isIdleTimerDisabled = value.keepScreenOn
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                Form {
                    Picker("ページ送り", selection: $prefs.turnStyle) {
                        ForEach(PageTurnStyle.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("開き方向", selection: $direction) {
                        ForEach(ReadingDirection.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("表示", selection: $prefs.fitMode) {
                        ForEach(PageFitMode.allCases) { Text($0.label).tag($0) }
                    }
                    HStack {
                        Text("明るさ")
                        Slider(value: $prefs.brightness, in: 0.2...1)
                    }
                    Toggle("自動ロックしない", isOn: $prefs.keepScreenOn)
                }
                .navigationTitle("読書設定")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") { showSettings = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func chrome(safeTop: CGFloat, safeBottom: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down").frame(width: 36, height: 36)
                }
                .accessibilityLabel("本棚に戻る")

                VStack(spacing: 2) {
                    Text(volume.title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    Text("\(pageIndex + 1) / \(volume.pageCount)")
                        .font(.caption.monospacedDigit())
                }
                Spacer(minLength: 0)
                Button { showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3").frame(width: 36, height: 36)
                }
                .accessibilityLabel("読書設定")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.top, safeTop + 4)
            .padding(.bottom, 12)
            .background(
                LinearGradient(colors: [.black.opacity(0.85), .clear], startPoint: .top, endPoint: .bottom)
            )

            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

            Slider(
                value: Binding(
                    get: { Double(pageIndex) },
                    set: { pageIndex = Int($0.rounded()) }
                ),
                in: 0...Double(max(volume.pageCount - 1, 0)),
                step: 1
            )
            .padding(.horizontal, 20)
            .padding(.bottom, safeBottom + 12)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            )
        }
        .ignoresSafeArea()
    }
}
