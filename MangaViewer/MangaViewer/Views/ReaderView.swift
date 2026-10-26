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
    /// 折りたたみ途中の 0 サイズでは更新しない。前回の有効レイアウトを維持する。
    @State private var appliedLayout: PageLayoutMode = .single

    private let progress = ReadingProgress.shared

    init(library: LibraryStore, volume: MangaVolume) {
        self.library = library
        self.volume = volume
        _direction = State(initialValue: volume.direction)
    }

    private var totalSpreads: Int {
        SpreadIndex.totalSpreads(
            pageCount: volume.pageCount,
            coverAlone: prefs.coverAlone,
            layout: appliedLayout
        )
    }

    private var currentPageIndex: Int {
        SpreadIndex.pageIndices(
            spreadIndex: spreadIndex,
            pageCount: volume.pageCount,
            coverAlone: prefs.coverAlone,
            layout: appliedLayout
        ).0 ?? 0
    }

    var body: some View {
        // Duo 指針: 単ページ／見開きで別の View 木に切り替えない（状態と UIPageViewController を壊す）。
        ZStack {
            Color.black.ignoresSafeArea()

            if volume.pageCount <= 0 {
                ContentUnavailableView("ページがありません", systemImage: "doc.questionmark")
                    .foregroundStyle(.white)
            } else {
                PageBrowser(
                    pageCount: max(totalSpreads, 1),
                    index: $spreadIndex,
                    // 見開き合成ページは pageCurl と相性が悪いので Duo 中はスライドにする。
                    style: appliedLayout == .duo ? .slide : prefs.turnStyle,
                    rtl: direction == .rtl,
                    reduceMotion: reduceMotion,
                    onToggleChrome: {
                        withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() }
                    }
                ) { index in
                    AnyView(spreadPage(index))
                }
                // Duo 切替で木を破棄しない。送り方と方向の変更時だけ再生成。
                .id("\(direction.rawValue)-\(appliedLayout == .duo ? "slide" : prefs.turnStyle.rawValue)")
                .opacity(prefs.brightness)
            }

            if showChrome {
                chromeOverlay
            }
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { adoptSize(geo.size) }
                    .onChange(of: geo.size) { _, newSize in
                        adoptSize(newSize)
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
        .onChange(of: prefs.layoutMode) { _, _ in
            rematerializeFromProgress(layout: appliedLayout)
        }
        .onChange(of: prefs.coverAlone) { _, _ in
            rematerializeFromProgress(layout: appliedLayout)
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

    private func spreadPage(_ index: Int) -> some View {
        let pages = SpreadIndex.pageIndices(
            spreadIndex: index,
            pageCount: volume.pageCount,
            coverAlone: prefs.coverAlone,
            layout: appliedLayout
        )
        return DuoFrameView {
            GeometryReader { geo in
                HStack(spacing: hingeGutter(in: geo)) {
                    if appliedLayout == .duo {
                        if direction == .rtl {
                            pagePane(pages.1, size: geo.size)
                            pagePane(pages.0, size: geo.size)
                        } else {
                            pagePane(pages.0, size: geo.size)
                            pagePane(pages.1, size: geo.size)
                        }
                    } else {
                        pagePane(pages.0, size: geo.size)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    /// 将来の reservedRegions(.division) 用。SDK が無い環境では 0。
    private func hingeGutter(in geo: GeometryProxy) -> CGFloat {
        0
    }

    @ViewBuilder
    private func pagePane(_ index: Int?, size: CGSize) -> some View {
        if let index {
            PageImageView(
                url: volume.pageURL(at: index),
                pageNumber: index + 1,
                fitMode: prefs.fitMode
            )
            .frame(
                width: appliedLayout == .duo ? size.width / 2 : size.width,
                height: size.height
            )
        } else {
            Color.black
                .frame(
                    width: appliedLayout == .duo ? size.width / 2 : size.width,
                    height: size.height
                )
        }
    }

    private var chromeOverlay: some View {
        GeometryReader { geo in
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
                        Text("\(currentPageIndex + 1) / \(volume.pageCount) · \(appliedLayout == .duo ? "Duo" : "単ページ")")
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
                .padding(.top, geo.safeAreaInsets.top + 4)
                .padding(.bottom, 12)
                .background(
                    LinearGradient(colors: [.black.opacity(0.85), .clear], startPoint: .top, endPoint: .bottom)
                )

                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() }
                    }

                let maxSpread = max(totalSpreads - 1, 0)
                Slider(
                    value: Binding(
                        get: { Double(min(max(spreadIndex, 0), maxSpread)) },
                        set: { spreadIndex = Int($0.rounded()) }
                    ),
                    in: 0...Double(maxSpread),
                    step: 1
                )
                .padding(.horizontal, 20)
                .padding(.bottom, geo.safeAreaInsets.bottom + 12)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                )
            }
            .ignoresSafeArea()
        }
        // Chrome の中央以外は PageBrowser のスワイプを妨げないよう、オーバーレイ全体は通す。
        // 上下バーはデフォルトでヒットを受ける。
    }

    private func adoptSize(_ size: CGSize) {
        // 高さ0などの過渡フレームではレイアウトを切り替えない（Duo で固まる主因）。
        guard DuoLayout.isUsable(size) else { return }
        let next = DuoLayout.resolve(containerSize: size, preference: prefs.layoutMode)
        guard next != appliedLayout else { return }
        DispatchQueue.main.async {
            appliedLayout = next
            rematerializeFromProgress(layout: next)
        }
    }

    private func restoreProgress() {
        prefs = AppSettingsStore.load()
        rematerializeFromProgress(layout: appliedLayout)
        UIApplication.shared.isIdleTimerDisabled = prefs.keepScreenOn
        showChrome = false
    }

    private func rematerializeFromProgress(layout: PageLayoutMode) {
        let page = progress.pageIndex(for: volume.id)
        let spreads = SpreadIndex.totalSpreads(
            pageCount: volume.pageCount,
            coverAlone: prefs.coverAlone,
            layout: layout
        )
        let next = min(
            max(SpreadIndex.spreadIndex(forPage: page, coverAlone: prefs.coverAlone, layout: layout), 0),
            max(spreads - 1, 0)
        )
        if spreadIndex != next {
            spreadIndex = next
        }
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
