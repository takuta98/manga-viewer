import SwiftUI

struct ReaderView: View {
    @ObservedObject var library: LibraryStore
    let volume: MangaVolume
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var prefs = AppSettingsStore.loadPrefs()
    @State private var spreadIndex = 0
    @State private var showChrome = true
    @State private var showThumbnails = false
    @State private var showContinueBanner = false
    @State private var containerSize: CGSize = .zero
    private let progress = ProgressStore.shared

    private var effectiveLayout: PageLayoutMode {
        DisplayLayoutResolver.resolve(containerSize: containerSize, preference: prefs.layoutMode)
    }

    private var totalSpreads: Int {
        SpreadIndex.totalSpreads(pageCount: volume.pageCount, coverAlone: prefs.coverAlone, layout: effectiveLayout)
    }

    private var currentPageIndex: Int {
        SpreadIndex.pageIndices(spreadIndex: spreadIndex, pageCount: volume.pageCount, coverAlone: prefs.coverAlone, layout: effectiveLayout).0 ?? 0
    }

    private var effectiveDirection: ReadingDirection { volume.direction }

    var body: some View {
        GeometryReader { geo in
            let _ = { containerSize = geo.size }()
            ZStack {
                Color.black.ignoresSafeArea()
                pageContent
                    .opacity(prefs.brightness)
                if showChrome { chromeOverlay(geo) }
                if showContinueBanner { continueBanner(geo) }
            }
            .onTapGesture { withAnimation { showChrome.toggle() } }
        }
        .statusBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            let saved = progress.spreadIndex(for: volume.id)
            spreadIndex = min(saved, max(totalSpreads - 1, 0))
            UIApplication.shared.isIdleTimerDisabled = prefs.keepScreenOn
            if saved > 0 {
                showContinueBanner = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    withAnimation(.easeOut(duration: 0.45)) { showContinueBanner = false }
                }
            }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: spreadIndex) { _, v in progress.setSpreadIndex(v, for: volume.id) }
        .sheet(isPresented: $showThumbnails) {
            ThumbnailGridView(volume: volume) { page in
                spreadIndex = SpreadIndex.spreadIndex(forPage: page, coverAlone: prefs.coverAlone, layout: effectiveLayout)
                showThumbnails = false
            }
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        if effectiveLayout == .webtoon {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<volume.pageCount, id: \.self) { i in
                        PagePaneView(url: volume.pageURL(at: i), pageNumber: i + 1, fitMode: prefs.fitMode)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(2/3, contentMode: .fit)
                    }
                }
            }
        } else if effectiveLayout == .spread {
            let pages = SpreadIndex.pageIndices(spreadIndex: spreadIndex, pageCount: volume.pageCount, coverAlone: prefs.coverAlone, layout: .spread)
            HStack(spacing: 0) {
                pagePane(pages.0)
                pagePane(pages.1)
            }
            .gesture(DragGesture(minimumDistance: 40).onEnded { value in
                let next = (value.translation.width < 0) == (effectiveDirection == .ltr)
                if next { spreadIndex = min(spreadIndex + 1, max(totalSpreads - 1, 0)) }
                else { spreadIndex = max(spreadIndex - 1, 0) }
            })
        } else {
            PageTurnHost(
                pageCount: volume.pageCount,
                index: Binding(
                    get: { currentPageIndex },
                    set: { spreadIndex = SpreadIndex.spreadIndex(forPage: $0, coverAlone: prefs.coverAlone, layout: .single) }
                ),
                style: prefs.turnStyle,
                rtl: effectiveDirection == .rtl,
                reduceMotion: reduceMotion
            ) { i in
                AnyView(PagePaneView(url: volume.pageURL(at: i), pageNumber: i + 1, fitMode: prefs.fitMode))
            }
        }
    }

    @ViewBuilder
    private func pagePane(_ index: Int?) -> some View {
        if let index {
            PagePaneView(url: volume.pageURL(at: index), pageNumber: index + 1, fitMode: prefs.fitMode)
        } else {
            Color.black
        }
    }

    private func chromeOverlay(_ geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }
                VStack(spacing: 2) {
                    Text(volume.title).font(.footnote.weight(.semibold)).lineLimit(1)
                    Text("\(currentPageIndex + 1) / \(volume.pageCount)").font(.caption.monospaced())
                }
                Spacer()
                Button { showThumbnails = true } label: { Image(systemName: "square.grid.2x2").frame(width: 36, height: 36) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.top, geo.safeAreaInsets.top)
            .padding(.bottom, 12)
            .background(LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom))
            Spacer()
            Slider(value: Binding(get: { Double(spreadIndex) }, set: { spreadIndex = Int($0.rounded()) }),
                   in: 0...Double(max(totalSpreads - 1, 0)), step: 1)
                .padding(.horizontal, 20)
                .padding(.bottom, geo.safeAreaInsets.bottom + 12)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
        }
        .ignoresSafeArea()
    }

    private func continueBanner(_ geo: GeometryProxy) -> some View {
        VStack {
            Text("続きから")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.black.opacity(0.82), in: Capsule())
                .padding(.top, geo.safeAreaInsets.top + 12)
            Spacer()
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
