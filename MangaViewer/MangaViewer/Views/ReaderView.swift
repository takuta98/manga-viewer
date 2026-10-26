import SwiftUI
import UIKit

struct ReaderView: View {
    @ObservedObject var library: LibraryStore
    let volume: MangaVolume

    @Environment(\.dismiss) private var dismiss
    @State private var spreadIndex: Int = 0
    @State private var prefs = AppSettingsStore.loadPrefs()
    @State private var chromeVisible = false
    @State private var showThumbnails = false
    @State private var showReaderSettings = false

    private let progress = ProgressStore.shared

    private var effectiveDirection: ReadingDirection {
        library.volumes.first(where: { $0.id == volume.id })?.direction ?? volume.direction
    }

    private var effectiveLayout: PageLayoutMode {
        prefs.layoutMode
    }

    private var totalSpreads: Int {
        SpreadIndex.spreadCount(
            pageCount: volume.pageCount,
            coverAlone: prefs.coverAlone,
            layout: effectiveLayout == .webtoon ? .single : effectiveLayout
        )
    }

    private var currentPageIndex: Int {
        SpreadIndex.closedPageIndex(
            for: spreadIndex,
            pageCount: volume.pageCount,
            direction: effectiveDirection,
            coverAlone: prefs.coverAlone,
            layout: effectiveLayout == .webtoon ? .single : effectiveLayout
        ) ?? 0
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                if prefs.layoutMode == .webtoon {
                    webtoonScroll
                } else {
                    pagingReader
                }
            }
            .ignoresSafeArea()

            // 明るさは透過ではなく黒オーバーレイ
            Color.black
                .opacity(1.0 - prefs.brightness)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if chromeVisible {
                chromeOverlay
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(!chromeVisible)
        .persistentSystemOverlays(chromeVisible ? .automatic : .hidden)
        .onAppear {
            prefs = AppSettingsStore.loadPrefs()
            spreadIndex = min(progress.spreadIndex(for: volume.id), max(totalSpreads - 1, 0))
            library.markOpened(volume)
            UIApplication.shared.isIdleTimerDisabled = prefs.keepScreenOn
            chromeVisible = false
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: spreadIndex) { _, newValue in
            progress.setSpreadIndex(newValue, for: volume.id)
            prefetchAround(newValue)
        }
        .onChange(of: prefs) { _, newValue in
            AppSettingsStore.savePrefs(newValue)
            spreadIndex = min(spreadIndex, max(totalSpreads - 1, 0))
            UIApplication.shared.isIdleTimerDisabled = newValue.keepScreenOn
        }
        .sheet(isPresented: $showThumbnails) {
            NavigationStack {
                ThumbnailGridView(volume: volume, currentPage: currentPageIndex) { page in
                    jumpToPage(page)
                    showThumbnails = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") { showThumbnails = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showReaderSettings) {
            readerSettingsSheet
        }
    }

    private var pagingReader: some View {
        PageTurnHost(
            pageCount: totalSpreads,
            index: $spreadIndex,
            isRTL: effectiveDirection == .rtl,
            style: prefs.turnStyle,
            onTapCenter: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    chromeVisible.toggle()
                }
            },
            makePage: { index in
                AnyView(spreadView(for: index))
            }
        )
        .id("\(prefs.turnStyle.rawValue)-\(effectiveDirection.rawValue)-\(effectiveLayout.rawValue)-\(prefs.coverAlone)")
    }

    private func spreadView(for index: Int) -> some View {
        let pages = SpreadIndex.pages(
            for: index,
            pageCount: volume.pageCount,
            direction: effectiveDirection,
            coverAlone: prefs.coverAlone,
            layout: effectiveLayout == .webtoon ? .single : effectiveLayout
        )
        return GeometryReader { geo in
            Group {
                if effectiveLayout == .spread {
                    HStack(spacing: 0) {
                        pagePane(index: pages.leftIndex)
                            .frame(width: geo.size.width / 2, height: geo.size.height)
                        pagePane(index: pages.rightIndex)
                            .frame(width: geo.size.width / 2, height: geo.size.height)
                    }
                } else {
                    pagePane(index: pages.leftIndex ?? pages.rightIndex)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .background(Color.black)
        }
        .ignoresSafeArea()
    }

    private var webtoonScroll: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<volume.pageCount, id: \.self) { index in
                    PagePaneView(
                        url: volume.pageURL(at: index),
                        pageNumber: index + 1,
                        fitMode: .fitWidth
                    )
                    .frame(maxWidth: .infinity)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .onAppear { spreadIndex = index }
                }
            }
        }
        .ignoresSafeArea()
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { chromeVisible.toggle() }
        }
    }

    @ViewBuilder
    private func pagePane(index: Int?) -> some View {
        if let index {
            PagePaneView(
                url: volume.pageURL(at: index),
                pageNumber: index + 1,
                fitMode: prefs.fitMode
            )
        } else {
            Color.black
        }
    }

    private var chromeOverlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                VStack(spacing: 2) {
                    Text(volume.title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    Text("\(currentPageIndex + 1) / \(volume.pageCount)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer(minLength: 0)
                Button {
                    progress.toggleBookmark(pageIndex: currentPageIndex, for: volume.id)
                } label: {
                    Image(systemName: progress.isBookmarked(pageIndex: currentPageIndex, for: volume.id)
                          ? "bookmark.fill" : "bookmark")
                        .frame(width: 36, height: 36)
                }
                Button { showThumbnails = true } label: {
                    Image(systemName: "square.grid.2x2")
                        .frame(width: 36, height: 36)
                }
                Button { showReaderSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 36, height: 36)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.top, 54)
            .padding(.bottom, 12)
            .background(
                LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom)
            )

            Spacer()

            VStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { Double(spreadIndex) },
                        set: { spreadIndex = Int($0.rounded()) }
                    ),
                    in: 0...Double(max(totalSpreads - 1, 0)),
                    step: 1
                )
                .environment(
                    \.layoutDirection,
                    effectiveDirection == .rtl ? .rightToLeft : .leftToRight
                )
                Text("\(prefs.turnStyle.label) · \(effectiveDirection.shortLabel)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 34)
            .padding(.top, 12)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            )
        }
        .ignoresSafeArea()
    }

    private var readerSettingsSheet: some View {
        NavigationStack {
            Form {
                Picker("この作品の方向", selection: Binding(
                    get: { effectiveDirection },
                    set: { library.updateDirection(volume, direction: $0) }
                )) {
                    ForEach(ReadingDirection.allCases) { dir in
                        Text(dir.label).tag(dir)
                    }
                }
                Picker("レイアウト", selection: $prefs.layoutMode) {
                    ForEach(PageLayoutMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Picker("ページ送り", selection: $prefs.turnStyle) {
                    ForEach(PageTurnStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                Picker("フィット", selection: $prefs.fitMode) {
                    ForEach(PageFitMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Toggle("表紙単独", isOn: $prefs.coverAlone)
                HStack {
                    Text("明るさ")
                    Slider(value: $prefs.brightness, in: 0.35...1.0)
                }
            }
            .navigationTitle("読書設定")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { showReaderSettings = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func prefetchAround(_ index: Int) {
        let layout = effectiveLayout == .webtoon ? PageLayoutMode.single : effectiveLayout
        var urls: [URL] = []
        for offset in -2...2 {
            let i = index + offset
            guard i >= 0, i < totalSpreads else { continue }
            let pages = SpreadIndex.pages(
                for: i,
                pageCount: volume.pageCount,
                direction: effectiveDirection,
                coverAlone: prefs.coverAlone,
                layout: layout
            )
            for idx in [pages.leftIndex, pages.rightIndex].compactMap({ $0 }) {
                if let url = volume.pageURL(at: idx) {
                    urls.append(url)
                }
            }
        }
        PageImageCache.shared.prefetch(urls: urls)
    }

    private func jumpToPage(_ page: Int) {
        let layout = effectiveLayout == .webtoon ? PageLayoutMode.single : effectiveLayout
        for i in 0..<totalSpreads {
            let pages = SpreadIndex.pages(
                for: i,
                pageCount: volume.pageCount,
                direction: effectiveDirection,
                coverAlone: prefs.coverAlone,
                layout: layout
            )
            if pages.leftIndex == page || pages.rightIndex == page {
                spreadIndex = i
                return
            }
        }
        spreadIndex = min(page, totalSpreads - 1)
    }
}
