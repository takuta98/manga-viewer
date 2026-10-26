import SwiftUI
import UIKit

struct ReaderView: View {
    @ObservedObject var library: LibraryStore
    let volume: MangaVolume

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var prefs = AppSettingsStore.load()
    @State private var direction: ReadingDirection
    @State private var spreadIndex = 0
    @State private var showChrome = false
    @State private var showSettings = false
    @State private var containerSize: CGSize = .zero

    private let progress = ReadingProgress.shared

    init(library: LibraryStore, volume: MangaVolume) {
        self.library = library
        self.volume = volume
        _direction = State(initialValue: volume.direction)
    }

    private var layout: PageLayoutMode {
        DuoLayout.resolve(containerSize: containerSize, preference: prefs.layoutMode)
    }

    private var totalSpreads: Int {
        SpreadIndex.totalSpreads(
            pageCount: volume.pageCount,
            coverAlone: prefs.coverAlone,
            layout: layout
        )
    }

    private var currentPageIndex: Int {
        SpreadIndex.pageIndices(
            spreadIndex: spreadIndex,
            pageCount: volume.pageCount,
            coverAlone: prefs.coverAlone,
            layout: layout
        ).0 ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let _ = { containerSize = geo.size }()
            ZStack {
                Color.black.ignoresSafeArea()

                if volume.pageCount <= 0 {
                    ContentUnavailableView("ページがありません", systemImage: "doc.questionmark")
                        .foregroundStyle(.white)
                } else if layout == .duo {
                    duoContent
                        .opacity(prefs.brightness)
                    duoEdgeTaps(width: geo.size.width)
                } else {
                    PageBrowser(
                        pageCount: volume.pageCount,
                        index: Binding(
                            get: { currentPageIndex },
                            set: {
                                spreadIndex = SpreadIndex.spreadIndex(
                                    forPage: $0,
                                    coverAlone: prefs.coverAlone,
                                    layout: .single
                                )
                            }
                        ),
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
        .onAppear(perform: restoreProgress)
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: spreadIndex) { _, _ in
            progress.setPageIndex(currentPageIndex, for: volume.id)
        }
        .onChange(of: containerSize) { _, _ in
            clampSpread()
        }
        .onChange(of: prefs.layoutMode) { _, _ in
            clampSpread()
        }
        .onChange(of: prefs.coverAlone) { _, _ in
            clampSpread()
        }
        .onChange(of: direction) { _, value in
            library.updateDirection(volume, direction: value)
        }
        .onChange(of: prefs) { _, value in
            AppSettingsStore.save(value)
            UIApplication.shared.isIdleTimerDisabled = value.keepScreenOn
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
    }

    private var duoContent: some View {
        let pages = SpreadIndex.pageIndices(
            spreadIndex: spreadIndex,
            pageCount: volume.pageCount,
            coverAlone: prefs.coverAlone,
            layout: .duo
        )
        return DuoFrameView {
            HStack(spacing: 0) {
                if direction == .rtl {
                    pagePane(pages.1)
                    pagePane(pages.0)
                } else {
                    pagePane(pages.0)
                    pagePane(pages.1)
                }
            }
        }
    }

    @ViewBuilder
    private func pagePane(_ index: Int?) -> some View {
        if let index {
            PageImageView(
                url: volume.pageURL(at: index),
                pageNumber: index + 1,
                fitMode: prefs.fitMode
            )
        } else {
            Color.black
        }
    }

    private func duoEdgeTaps(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { turn(forward: direction == .rtl) }
                .frame(width: width * 0.28)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() }
                }
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { turn(forward: direction != .rtl) }
                .frame(width: width * 0.28)
        }
    }

    private func turn(forward: Bool) {
        if forward {
            spreadIndex = min(spreadIndex + 1, max(totalSpreads - 1, 0))
        } else {
            spreadIndex = max(spreadIndex - 1, 0)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func restoreProgress() {
        prefs = AppSettingsStore.load()
        let savedPage = progress.pageIndex(for: volume.id)
        spreadIndex = SpreadIndex.spreadIndex(
            forPage: savedPage,
            coverAlone: prefs.coverAlone,
            layout: layout
        )
        clampSpread()
        UIApplication.shared.isIdleTimerDisabled = prefs.keepScreenOn
        showChrome = false
    }

    private func clampSpread() {
        // 回転で single ↔ Duo が切り替わるとき、ページ番号を基準に見開き位置へ戻す。
        let page = progress.pageIndex(for: volume.id)
        spreadIndex = SpreadIndex.spreadIndex(
            forPage: page,
            coverAlone: prefs.coverAlone,
            layout: layout
        )
        spreadIndex = min(spreadIndex, max(totalSpreads - 1, 0))
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
                    Text("\(currentPageIndex + 1) / \(volume.pageCount) · \(layout == .duo ? "Duo" : "単ページ")")
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
                    get: { Double(spreadIndex) },
                    set: { spreadIndex = Int($0.rounded()) }
                ),
                in: 0...Double(max(totalSpreads - 1, 0)),
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

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Text(DuoLayout.explain)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Picker("レイアウト", selection: $prefs.layoutMode) {
                        ForEach(PageLayoutMode.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("表紙を単独表示", isOn: $prefs.coverAlone)
                } header: {
                    Text("iPhone Duo")
                }
                Section("ページ送り") {
                    Picker("ページ送り", selection: $prefs.turnStyle) {
                        ForEach(PageTurnStyle.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("開き方向", selection: $direction) {
                        ForEach(ReadingDirection.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("表示", selection: $prefs.fitMode) {
                        ForEach(PageFitMode.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section {
                    HStack {
                        Text("明るさ")
                        Slider(value: $prefs.brightness, in: 0.2...1)
                    }
                    Toggle("自動ロックしない", isOn: $prefs.keepScreenOn)
                }
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
