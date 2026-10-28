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
    /// ページ中身の再生成用。めくりアニメを殺さないよう、必要なときだけ増やす。
    @State private var pageRevision = 0

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

    /// 見開きの curl は綴じ目で1枚ずつめくるので、片ページ単位で渡す。
    private var turnsSinglePages: Bool {
        prefs.turnStyle == .curl && !reduceMotion && appliedLayout == .duo
    }

    private var pageSlots: [Int?] {
        SpreadIndex.slots(pageCount: volume.pageCount, coverAlone: prefs.coverAlone)
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
                let slots = pageSlots
                PageBrowser(
                    pageCount: turnsSinglePages ? max(slots.count, 2) : max(totalSpreads, 1),
                    unitsPerScreen: turnsSinglePages ? 2 : 1,
                    index: $spreadIndex,
                    style: prefs.turnStyle,
                    rtl: direction == .rtl,
                    reduceMotion: reduceMotion,
                    pageRevision: pageRevision,
                    onToggleChrome: {
                        withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() }
                    }
                ) { index in
                    if turnsSinglePages {
                        return AnyView(slotPage(index < slots.count ? slots[index] : nil))
                    }
                    return AnyView(spreadPage(index))
                }
                // めくりスタイル／方向／綴じ目が変わったときだけ UIPageViewController を作り直す。
                .id("turn-\(prefs.turnStyle.rawValue)-dir-\(direction.rawValue)-spread-\(turnsSinglePages)")
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
            pageRevision += 1
            rematerializeFromProgress(layout: appliedLayout)
        }
        .onChange(of: prefs.coverAlone) { _, _ in
            pageRevision += 1
            rematerializeFromProgress(layout: appliedLayout)
        }
        .onChange(of: prefs.fitMode) { _, _ in
            pageRevision += 1
        }
        .onChange(of: appliedLayout) { _, _ in
            pageRevision += 1
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

    /// 見開き curl の片ページ。UIPageViewController が画面の半分に敷く。
    private func slotPage(_ index: Int?) -> some View {
        DuoFrameView {
            GeometryReader { geo in
                pagePane(index, width: geo.size.width, height: geo.size.height)
            }
        }
    }

    /// 将来の reservedRegions(.division) 用。SDK が無い環境では 0。
    private func hingeGutter(in geo: GeometryProxy) -> CGFloat {
        0
    }

    private func pagePane(_ index: Int?, size: CGSize) -> some View {
        pagePane(
            index,
            width: appliedLayout == .duo ? size.width / 2 : size.width,
            height: size.height
        )
    }

    @ViewBuilder
    private func pagePane(_ index: Int?, width: CGFloat, height: CGFloat) -> some View {
        if let index {
            PageImageView(
                url: volume.pageURL(at: index),
                pageNumber: index + 1,
                fitMode: prefs.fitMode
            )
            .frame(width: width, height: height)
        } else {
            Color.black
                .frame(width: width, height: height)
        }
    }

    private var chromeOverlay: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // 作品名は小さく上部に
                VStack(spacing: 2) {
                    Text(volume.title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    Text("\(currentPageIndex + 1) / \(volume.pageCount) · \(appliedLayout == .duo ? "Duo" : "単ページ")")
                        .font(.caption.monospacedDigit())
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.top, geo.safeAreaInsets.top + 4)
                .padding(.bottom, 12)
                .background(
                    LinearGradient(colors: [.black.opacity(0.85), .clear], startPoint: .top, endPoint: .bottom)
                )

                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)

                // ページ送りスライダーは下部に
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
            .overlay(alignment: .top) {
                // 画面中央より少し上: 大きな「本を閉じる」ボタン + 小さな設定ボタン
                VStack(spacing: 18) {
                    Button { dismiss() } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.title.weight(.bold))
                            Text("閉じる")
                                .font(.callout.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(width: 140, height: 96)
                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 48, style: .continuous))
                    }
                    .accessibilityLabel("本を閉じる")

                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.5), in: Circle())
                    }
                    .accessibilityLabel("読書設定")
                }
                .padding(.top, geo.size.height * 0.33)
            }
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
