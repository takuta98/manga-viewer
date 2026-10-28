import SwiftUI
import UIKit

/// 読書画面。普段はページだけを表示し、タップで操作を呼び出す。
/// 「閉じる」が一番大きく画面中央の少し上、その下に小さな設定。
struct ReaderView: View {
    @ObservedObject var library: LibraryStore
    let volume: MangaVolume

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var prefs = AppSettingsStore.load()
    @State private var direction: ReadingDirection
    /// 見開きペアずらし: このページの直後に空白を1枚挿す。巻ごとに保存。
    @State private var pairBreak: Int?
    @State private var spreadIndex = 0
    @State private var showChrome = false
    @State private var showSettings = false
    /// 折りたたみ途中の 0 サイズでは更新しない。前回の有効レイアウトを維持する。
    @State private var appliedLayout: PageLayoutMode = .single
    /// ページ中身の再生成用。めくりアニメを殺さないよう必要なときだけ増やす。
    @State private var pageRevision = 0

    private let progress = ReadingProgress.shared

    init(library: LibraryStore, volume: MangaVolume) {
        self.library = library
        self.volume = volume
        _direction = State(initialValue: volume.direction)
        _pairBreak = State(initialValue: volume.pairBreakAfter)
    }

    private var totalSpreads: Int {
        SpreadIndex.totalSpreads(
            pageCount: volume.pageCount,
            coverAlone: prefs.coverAlone,
            layout: appliedLayout,
            pairBreakAfter: pairBreak
        )
    }

    /// Duo の見開き curl は綴じ目で1枚ずつめくるので片ページ単位で渡す。
    private var turnsSinglePages: Bool {
        prefs.turnStyle == .curl && !reduceMotion && appliedLayout == .duo
    }

    private var pageSlots: [Int?] {
        SpreadIndex.slots(
            pageCount: volume.pageCount,
            coverAlone: prefs.coverAlone,
            pairBreakAfter: pairBreak
        )
    }

    /// Duo curl はスロット（片ページ）単位、それ以外は見開き単位でインデックスが動く。
    private var indexSpaceMax: Int {
        if turnsSinglePages {
            return max(pageSlots.count - 1, 0)
        }
        return max(totalSpreads - 1, 0)
    }

    private var currentPageIndex: Int {
        if turnsSinglePages {
            let i = min(max(spreadIndex, 0), pageSlots.count - 1)
            guard pageSlots.indices.contains(i) else { return 0 }
            return pageSlots[i] ?? 0
        }
        return SpreadIndex.pageIndices(
            spreadIndex: spreadIndex,
            pageCount: volume.pageCount,
            coverAlone: prefs.coverAlone,
            layout: appliedLayout,
            pairBreakAfter: pairBreak
        ).0 ?? 0
    }

    var body: some View {
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
                        return AnyView(slotPage(index < slots.count ? index : nil))
                    }
                    return AnyView(spreadPage(index))
                }
                // ページャー自身がセーフエリアに収まり画面より小さく敷かれるのを防ぐ
                .ignoresSafeArea()
                .id("turn-\(prefs.turnStyle.rawValue)-dir-\(direction.rawValue)-spread-\(turnsSinglePages)")
                .opacity(prefs.brightness)
            }

            if showChrome {
                controls
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
        .onChange(of: pairBreak) { _, value in
            library.setPairBreak(volume, after: value)
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

    // MARK: - ページ

    private func spreadPage(_ index: Int) -> some View {
        let pages = SpreadIndex.pageIndices(
            spreadIndex: index,
            pageCount: volume.pageCount,
            coverAlone: prefs.coverAlone,
            layout: appliedLayout,
            pairBreakAfter: pairBreak
        )
        return DuoFrameView {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    if appliedLayout == .duo {
                        // 左ペインは綴じ目（右辺）へ、右ペインは綴じ目（左辺）へ寄せる
                        if direction == .rtl {
                            pagePane(pages.1, size: geo.size, spineEdge: .trailing)
                            pagePane(pages.0, size: geo.size, spineEdge: .leading)
                        } else {
                            pagePane(pages.0, size: geo.size, spineEdge: .trailing)
                            pagePane(pages.1, size: geo.size, spineEdge: .leading)
                        }
                    } else {
                        pagePane(pages.0, size: geo.size)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    /// Duo curl の片ページ。UIPageViewController が画面半分に敷く。
    /// slot は並び順の片ページ番号。左半分に出る slot は右辺を綴じ目に寄せる。
    private func slotPage(_ slot: Int?) -> some View {
        DuoFrameView {
            GeometryReader { geo in
                if let slot {
                    // 左開き: 偶数が左。右開き: 奇数が左（左右を入れ替えて渡すため）
                    let onLeft = (slot % 2 == 1) == (direction == .rtl)
                    let edge: HorizontalEdge = onLeft ? .trailing : .leading
                    pagePane(
                        slot < pageSlots.count ? pageSlots[slot] : nil,
                        width: geo.size.width,
                        height: geo.size.height,
                        spineEdge: edge
                    )
                } else {
                    pagePane(nil, width: geo.size.width, height: geo.size.height)
                }
            }
        }
    }

    private func pagePane(_ index: Int?, size: CGSize, spineEdge: HorizontalEdge? = nil) -> some View {
        pagePane(
            index,
            width: appliedLayout == .duo ? size.width / 2 : size.width,
            height: size.height,
            spineEdge: spineEdge
        )
    }

    @ViewBuilder
    private func pagePane(_ index: Int?, width: CGFloat, height: CGFloat, spineEdge: HorizontalEdge? = nil) -> some View {
        if let index {
            PageImageView(
                url: volume.pageURL(at: index),
                pageNumber: index + 1,
                fitMode: prefs.fitMode,
                spineEdge: spineEdge
            )
            .frame(width: width, height: height)
        } else {
            Color.black
                .frame(width: width, height: height)
        }
    }

    // MARK: - タップで出る操作

    private var controls: some View {
        GeometryReader { geo in
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 22) {
                Button { dismiss() } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "xmark")
                            .font(.title.weight(.bold))
                        Text("閉じる")
                            .font(.title3.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 168, height: 132)
                    .background(
                        .black.opacity(0.8),
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
                }
                .accessibilityLabel("本を閉じる")

                Button { showSettings = true } label: {
                    Label("設定", systemImage: "gearshape")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.6), in: Capsule())
                }
                .accessibilityLabel("読書設定")

                // 見開きペアずらし: 見ているページの直後に空白を挿す/移す/消す
                VStack(spacing: 6) {
                    Button {
                        pairBreak = (pairBreak == currentPageIndex) ? nil : currentPageIndex
                    } label: {
                        Text(
                            pairBreak == nil
                                ? "このページの後に空白を入れる"
                                : (pairBreak == currentPageIndex
                                    ? "この空白を消す"
                                    : "このページの後に空白を移す")
                        )
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(.black.opacity(0.6), in: Capsule())
                    }
                    .accessibilityLabel("見開きのペアをずらす")
                    if let k = pairBreak, k != currentPageIndex {
                        HStack(spacing: 10) {
                            Text("空白は \(k + 1) ページの後")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                            Button("消す") { pairBreak = nil }
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.6), in: Capsule())
                    }
                }
            }
            // カメラ位置が左なのでボタンは右側に出す
            .position(x: geo.size.width - 110, y: geo.size.height * 0.38)

            VStack(spacing: 2) {
                Text(volume.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                if prefs.showPageNumber {
                    Text("\(currentPageIndex + 1) / \(volume.pageCount)")
                        .font(.caption.monospacedDigit())
                }
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.top, geo.safeAreaInsets.top + 6)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.85), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Slider(
                    value: Binding(
                        get: { Double(min(max(spreadIndex, 0), indexSpaceMax)) },
                        set: { spreadIndex = Int($0.rounded()) }
                    ),
                    in: 0...Double(indexSpaceMax),
                    step: 1
                )
                // 右開きは右→左へ進むので、スライダーも右から左にする
                .scaleEffect(x: direction == .rtl ? -1 : 1, y: 1)
                .padding(.horizontal, 24)
                .padding(.bottom, geo.safeAreaInsets.bottom + 14)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - 状態

    private func adoptSize(_ size: CGSize) {
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
            layout: layout,
            pairBreakAfter: pairBreak
        )
        let next = min(
            max(SpreadIndex.spreadIndex(forPage: page, coverAlone: prefs.coverAlone, layout: layout, pairBreakAfter: pairBreak), 0),
            max(spreads - 1, 0)
        )
        if spreadIndex != next {
            spreadIndex = next
        }
    }

    // MARK: - 設定

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
                    Toggle("ページ番号を表示", isOn: $prefs.showPageNumber)
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
