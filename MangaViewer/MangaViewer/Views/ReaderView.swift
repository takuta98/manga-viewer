import SwiftUI
import UIKit

struct ReaderView: View {
    @ObservedObject var library: LibraryStore
    let volume: MangaVolume
    var autoResume: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var prefs = AppSettingsStore.loadPrefs()
    @State private var direction: ReadingDirection
    @State private var spreadIndex = 0
    @State private var showChrome = true
    @State private var showThumbnails = false
    @State private var showReaderSettings = false
    @State private var showResumeChoice = false
    @State private var resumeTarget = 0
    @State private var suppressPersist = false
    @State private var bookmarkTick = 0
    @State private var showBookmarks = false
    @State private var confirmClearBookmarks = false
    @State private var webtoonJumpID = UUID()
    @State private var containerSize: CGSize = .zero
    @ObservedObject private var progress = ProgressStore.shared

    init(library: LibraryStore, volume: MangaVolume, autoResume: Bool = false) {
        self.library = library
        self.volume = volume
        self.autoResume = autoResume
        _direction = State(initialValue: volume.direction)
    }

    private var effectiveLayout: PageLayoutMode {
        DisplayLayoutResolver.resolve(containerSize: containerSize, preference: prefs.layoutMode)
    }

    private var totalSpreads: Int {
        SpreadIndex.totalSpreads(
            pageCount: volume.pageCount,
            coverAlone: prefs.coverAlone,
            layout: effectiveLayout
        )
    }

    private var currentPageIndex: Int {
        SpreadIndex.pageIndices(
            spreadIndex: spreadIndex,
            pageCount: volume.pageCount,
            coverAlone: prefs.coverAlone,
            layout: effectiveLayout
        ).0 ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let _ = { containerSize = geo.size }()
            ZStack {
                Color.black.ignoresSafeArea()
                pageContent
                    .opacity(prefs.brightness)
                edgeTapLayers(geo)
                if showChrome { chromeOverlay(geo) }
                if showResumeChoice { resumeChoice(geo) }
            }
        }
        .statusBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: onAppearReader)
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            progress.notifyLibrary()
        }
        .onChange(of: spreadIndex) { _, v in
            guard !suppressPersist, !showResumeChoice else { return }
            progress.setSpreadIndex(v, for: volume.id)
        }
        .onChange(of: direction) { _, v in library.updateDirection(volume, direction: v) }
        .onChange(of: prefs) { _, v in AppSettingsStore.savePrefs(v) }
        .onChange(of: prefs.layoutMode) { _, _ in
            spreadIndex = min(spreadIndex, max(totalSpreads - 1, 0))
        }
        .onChange(of: prefs.coverAlone) { _, _ in
            spreadIndex = min(spreadIndex, max(totalSpreads - 1, 0))
        }
        .sheet(isPresented: $showThumbnails) {
            ThumbnailGridView(
                volume: volume,
                currentPage: currentPageIndex,
                bookmarked: Set(progress.bookmarks(for: volume.id))
            ) { page in
                let toBookmark = progress.bookmarks(for: volume.id).contains(page)
                    && page != currentPageIndex
                jumpToPage(page)
                showThumbnails = false
                UIImpactFeedbackGenerator(style: toBookmark ? .medium : .light).impactOccurred()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .sheet(isPresented: $showBookmarks) {
            bookmarkListSheet
        }
        .sheet(isPresented: $showReaderSettings) {
            readerSettingsSheet
        }
    }

    private func jumpToPage(_ page: Int) {
        spreadIndex = SpreadIndex.spreadIndex(
            forPage: page,
            coverAlone: prefs.coverAlone,
            layout: effectiveLayout
        )
        progress.setSpreadIndex(spreadIndex, for: volume.id)
        progress.notifyLibrary()
        // webtoon は preference 追従と衝突しないよう、明示ジャンプ時だけ scrollTo する
        webtoonJumpID = UUID()
    }

    private func onAppearReader() {
        let saved = progress.spreadIndex(for: volume.id)
        UIApplication.shared.isIdleTimerDisabled = prefs.keepScreenOn
        suppressPersist = true
        if saved > 0 {
            resumeTarget = min(saved, max(totalSpreads - 1, 0))
            spreadIndex = resumeTarget
            if autoResume {
                showResumeChoice = false
                suppressPersist = false
            } else {
                showResumeChoice = true
            }
        } else {
            spreadIndex = 0
            suppressPersist = false
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        if volume.pageCount <= 0 {
            ContentUnavailableView(
                AppCopy.noPagesTitle,
                systemImage: "doc.questionmark",
                description: Text(AppCopy.noPagesBody)
            )
            .foregroundStyle(.white)
        } else if effectiveLayout == .webtoon {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<volume.pageCount, id: \.self) { i in
                            PagePaneView(
                                url: volume.pageURL(at: i),
                                pageNumber: i + 1,
                                fitMode: .fitWidth,
                                intrinsicHeight: true
                            )
                            .frame(maxWidth: .infinity)
                            .id(i)
                            .background(
                                GeometryReader { g in
                                    Color.clear.preference(
                                        key: WebtoonVisibleKey.self,
                                        value: [i: abs(g.frame(in: .named("webtoon")).midY - g.size.height / 2)]
                                    )
                                }
                            )
                        }
                    }
                }
                .coordinateSpace(name: "webtoon")
                .onPreferenceChange(WebtoonVisibleKey.self) { map in
                    guard !showResumeChoice, let best = map.min(by: { $0.value < $1.value })?.key else { return }
                    if best != spreadIndex { spreadIndex = best }
                }
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() }
                }
                .onAppear {
                    proxy.scrollTo(spreadIndex, anchor: .top)
                }
                .onChange(of: webtoonJumpID) { _, _ in
                    proxy.scrollTo(spreadIndex, anchor: .top)
                }
            }
        } else if effectiveLayout == .spread {
            let pages = SpreadIndex.pageIndices(
                spreadIndex: spreadIndex,
                pageCount: volume.pageCount,
                coverAlone: prefs.coverAlone,
                layout: .spread
            )
            DuoFrameView {
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
        } else {
            PageTurnHost(
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
                onTap: {
                    withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() }
                }
            ) { i in
                AnyView(
                    PagePaneView(
                        url: volume.pageURL(at: i),
                        pageNumber: i + 1,
                        fitMode: prefs.fitMode
                    )
                )
            }
            .id("\(prefs.turnStyle)-\(direction.rawValue)")
        }
    }

    @ViewBuilder
    private func pagePane(_ index: Int?) -> some View {
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

    private func edgeTapLayers(_ geo: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { turn(forward: direction == .rtl) }
                .frame(width: geo.size.width * 0.28)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() }
                }
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { turn(forward: direction != .rtl) }
                .frame(width: geo.size.width * 0.28)
        }
        .allowsHitTesting(effectiveLayout == .spread)
    }

    private func turn(forward: Bool) {
        guard effectiveLayout != .webtoon else { return }
        if forward {
            spreadIndex = min(spreadIndex + 1, max(totalSpreads - 1, 0))
        } else {
            spreadIndex = max(spreadIndex - 1, 0)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func chromeOverlay(_ geo: GeometryProxy) -> some View {
        let _ = progress.revision
        let marks = progress.bookmarks(for: volume.id)
        let pageBookmarked = progress.isBookmarked(pageIndex: currentPageIndex, for: volume.id)
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down").frame(width: 36, height: 36)
                }
                .accessibilityLabel(AppCopy.backToLibrary)
                .accessibilityValue(
                    {
                        let pagePct = Int(
                            (Double(currentPageIndex + 1) / Double(max(volume.pageCount, 1)) * 100)
                                .rounded()
                        )
                        var parts = [
                            volume.title,
                            "\(currentPageIndex + 1) / \(volume.pageCount) · \(pagePct)%",
                        ]
                        if !marks.isEmpty {
                            parts.append("\(AppCopy.bookmark) \(marks.count)")
                        }
                        return parts.joined(separator: "、")
                    }()
                )
                .accessibilityHint(AppCopy.libraryTitle)
                VStack(spacing: 2) {
                    let pagePct = Int(
                        (Double(currentPageIndex + 1) / Double(max(volume.pageCount, 1)) * 100)
                            .rounded()
                    )
                    Text(volume.title).font(.footnote.weight(.semibold)).lineLimit(1)
                    Text("\(currentPageIndex + 1) / \(volume.pageCount) · \(pagePct)%")
                        .font(.caption)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(AppCopy.currentPageLabel)
                .accessibilityValue(
                    {
                        let pagePct = Int(
                            (Double(currentPageIndex + 1) / Double(max(volume.pageCount, 1)) * 100)
                                .rounded()
                        )
                        return "\(currentPageIndex + 1) / \(volume.pageCount) · \(pagePct)%"
                    }()
                )
                Spacer(minLength: 0)
                Button {
                    progress.toggleBookmark(pageIndex: currentPageIndex, for: volume.id)
                    bookmarkTick += 1
                    progress.notifyLibrary()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: pageBookmarked ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(pageBookmarked ? .orange : .white)
                        .symbolEffect(.bounce, value: bookmarkTick)
                        .frame(width: 36, height: 36)
                        .id(bookmarkTick)
                }
                .accessibilityLabel(pageBookmarked ? AppCopy.bookmarkRemove : AppCopy.bookmarkAdd)
                .accessibilityValue({
                    let pagePct = Int(
                        (Double(currentPageIndex + 1) / Double(max(volume.pageCount, 1)) * 100)
                            .rounded()
                    )
                    return "\(currentPageIndex + 1) / \(volume.pageCount) · \(pagePct)%"
                }())
                .contextMenu {
                    Button(
                        marks.isEmpty
                            ? AppCopy.bookmarkList
                            : "\(AppCopy.bookmarkList)（\(marks.count)）"
                    ) { showBookmarks = true }
                    if pageBookmarked {
                        let pagePct = Int(
                            (Double(currentPageIndex + 1) / Double(max(volume.pageCount, 1)) * 100)
                                .rounded()
                        )
                        Button(
                            "\(AppCopy.bookmarkRemove) · \(currentPageIndex + 1) · \(pagePct)%",
                            role: .destructive
                        ) {
                            progress.removeBookmark(pageIndex: currentPageIndex, for: volume.id)
                            bookmarkTick += 1
                            progress.notifyLibrary()
                        }
                    }
                }
                Button {
                    showBookmarks = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: marks.isEmpty ? "bookmark.square" : "bookmark.square.fill")
                            .frame(width: 36, height: 36)
                        if !marks.isEmpty {
                            Text("\(marks.count)")
                                .font(.caption2.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(3)
                                .background(.orange, in: Circle())
                                .offset(x: 4, y: -2)
                        }
                    }
                }
                .accessibilityLabel(AppCopy.bookmarkList)
                .accessibilityValue(
                    {
                        if marks.isEmpty { return AppCopy.bookmarkEmpty }
                        let pagePct = Int(
                            (Double(currentPageIndex + 1) / Double(max(volume.pageCount, 1)) * 100)
                                .rounded()
                        )
                        return "\(AppCopy.bookmark) \(marks.count)、\(AppCopy.hereNow) \(pagePct)%"
                    }()
                )
                .accessibilityHint(
                    marks.isEmpty
                        ? AppCopy.bookmarkEmptyBody
                        : AppCopy.bookmarkListFooter
                )
                Button { showThumbnails = true } label: {
                    Image(systemName: "square.grid.2x2").frame(width: 36, height: 36)
                }
                .accessibilityLabel(AppCopy.thumbnails)
                .accessibilityValue(
                    marks.isEmpty
                        ? "\(currentPageIndex + 1) / \(volume.pageCount)"
                        : "\(AppCopy.bookmark) \(marks.count)"
                )
                .accessibilityHint(
                    marks.isEmpty ? AppCopy.thumbnails : AppCopy.bookmarkListFooter
                )
                .contextMenu {
                    Button(AppCopy.bookmarkList) { showBookmarks = true }
                    if !marks.isEmpty {
                        Button("\(AppCopy.bookmarkList)（\(marks.count)）") { showBookmarks = true }
                    }
                }
                Button { showReaderSettings = true } label: {
                    Image(systemName: "textformat.size").frame(width: 36, height: 36)
                }
                .accessibilityLabel(AppCopy.readingSettings)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.top, geo.safeAreaInsets.top)
            .padding(.bottom, 12)
            .background(
                LinearGradient(colors: [.black.opacity(0.85), .clear], startPoint: .top, endPoint: .bottom)
            )
            Spacer()
            VStack(spacing: 8) {
                if effectiveLayout == .webtoon {
                    let pagePct = Int(
                        (Double(currentPageIndex + 1) / Double(max(volume.pageCount, 1)) * 100)
                            .rounded()
                    )
                    ProgressView(
                        value: Double(currentPageIndex + 1),
                        total: Double(max(volume.pageCount, 1))
                    )
                    .tint(.white)
                    .padding(.horizontal, 20)
                    .accessibilityLabel(AppCopy.currentPageLabel)
                    .accessibilityValue("\(currentPageIndex + 1) / \(volume.pageCount) · \(pagePct)%")
                } else {
                    let pagePct = Int(
                        (Double(currentPageIndex + 1) / Double(max(volume.pageCount, 1)) * 100)
                            .rounded()
                    )
                    Slider(
                        value: Binding(
                            get: { Double(spreadIndex) },
                            set: { spreadIndex = Int($0.rounded()) }
                        ),
                        in: 0...Double(max(totalSpreads - 1, 0)),
                        step: 1
                    )
                    .padding(.horizontal, 20)
                    .accessibilityLabel(AppCopy.jumpToPage)
                    .accessibilityValue("\(currentPageIndex + 1) / \(volume.pageCount) · \(pagePct)%")
                }
            }
            .padding(.bottom, geo.safeAreaInsets.bottom + 12)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            )
        }
        .ignoresSafeArea()
    }

    private func resumeChoice(_ geo: GeometryProxy) -> some View {
        let page = SpreadIndex.pageIndices(
            spreadIndex: resumeTarget,
            pageCount: volume.pageCount,
            coverAlone: prefs.coverAlone,
            layout: effectiveLayout
        ).0.map { $0 + 1 } ?? 1
        return ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(volume.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(AppCopy.resumePrompt(page: page, total: volume.pageCount))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                let resumePct = Int(
                    (Double(page) / Double(max(volume.pageCount, 1)) * 100).rounded()
                )
                let marksN = progress.bookmarks(for: volume.id).count
                Text(
                    marksN > 0
                        ? "\(resumePct)% · \(AppCopy.continueReading) · \(AppCopy.bookmark) \(marksN)"
                        : "\(resumePct)% · \(AppCopy.continueReading)"
                )
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
                ProgressView(value: Double(page), total: Double(max(volume.pageCount, 1)))
                    .tint(.accentColor)
                    .frame(maxWidth: 180)
                if marksN > 0 {
                    Label {
                        Text("\(AppCopy.bookmark) \(marksN) · \(AppCopy.bookmarkListFooter)")
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(.orange)
                    }
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .labelStyle(.titleAndIcon)
                }
                HStack(spacing: 12) {
                    Button(AppCopy.startOver) {
                        showResumeChoice = false
                        suppressPersist = false
                        spreadIndex = 0
                        progress.clearProgress(for: volume.id)
                        progress.notifyLibrary()
                        webtoonJumpID = UUID()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    .buttonStyle(.bordered)
                    Button {
                        showResumeChoice = false
                        suppressPersist = false
                        spreadIndex = min(resumeTarget, max(totalSpreads - 1, 0))
                        progress.setSpreadIndex(spreadIndex, for: volume.id)
                        progress.notifyLibrary()
                        webtoonJumpID = UUID()
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Text(
                            marksN > 0
                                ? "\(AppCopy.resumeReading) \(resumePct)% · \(AppCopy.bookmark) \(marksN)"
                                : "\(AppCopy.resumeReading) \(resumePct)%"
                        )
                        .monospacedDigit()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel(AppCopy.resumeReading)
                    .accessibilityValue(
                        marksN > 0
                            ? "\(resumePct)%、\(AppCopy.bookmark) \(marksN)"
                            : "\(resumePct)%"
                    )
                    .accessibilityHint(
                        marksN > 0
                            ? "\(AppCopy.continueReading) · \(AppCopy.bookmark) \(marksN)"
                            : AppCopy.continueReading
                    )
                }
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 28)
        }
    }

    private var bookmarkListSheet: some View {
        let _ = progress.revision
        let marks = progress.bookmarks(for: volume.id).sorted()
        return NavigationStack {
            Group {
                if marks.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text(AppCopy.bookmarkEmpty)
                        } icon: {
                            Image(systemName: "bookmark")
                                .foregroundStyle(.orange)
                        }
                    } description: {
                        Text(AppCopy.bookmarkEmptyBody)
                        let pagePct = Int(
                            (Double(currentPageIndex + 1) / Double(max(volume.pageCount, 1)) * 100)
                                .rounded()
                        )
                        Text("\(AppCopy.hereNow) · \(currentPageIndex + 1) / \(volume.pageCount) · \(pagePct)%")
                            .font(.footnote.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        ProgressView(
                            value: Double(currentPageIndex + 1),
                            total: Double(max(volume.pageCount, 1))
                        )
                        .tint(.accentColor)
                        .frame(maxWidth: 180)
                        .padding(.top, 4)
                        Text(AppCopy.bookmarkListFooter)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    } actions: {
                        let pagePct = Int(
                            (Double(currentPageIndex + 1) / Double(max(volume.pageCount, 1)) * 100)
                                .rounded()
                        )
                        Button {
                            progress.toggleBookmark(pageIndex: currentPageIndex, for: volume.id)
                            bookmarkTick += 1
                            progress.notifyLibrary()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Label(
                                "\(AppCopy.bookmarkAdd) · \(currentPageIndex + 1) · \(pagePct)%",
                                systemImage: "bookmark"
                            )
                            .monospacedDigit()
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("\(currentPageIndex + 1) / \(volume.pageCount) · \(pagePct)%")
                        Button {
                            showBookmarks = false
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Label(
                                "\(AppCopy.hereNow) · \(currentPageIndex + 1) · \(pagePct)%",
                                systemImage: "book"
                            )
                            .monospacedDigit()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(AppCopy.hereNow)
                        .accessibilityValue("\(currentPageIndex + 1) / \(volume.pageCount) · \(pagePct)%")
                        .accessibilityHint(AppCopy.currentPageLabel)
                        Button(AppCopy.thumbnails) { showBookmarks = false; showThumbnails = true }
                            .buttonStyle(.bordered)
                    }
                } else {
                    let hereMarks = marks.filter { $0 == currentPageIndex }
                    // いまここから近いしおりを先に（ジャンプしやすく）
                    let otherMarks = marks
                        .filter { $0 != currentPageIndex }
                        .sorted { abs($0 - currentPageIndex) < abs($1 - currentPageIndex) }
                    ScrollViewReader { proxy in
                        List {
                            if !hereMarks.isEmpty {
                                Section {
                                    ForEach(hereMarks, id: \.self) { page in
                                        bookmarkRow(page, here: true)
                                    }
                                    .onDelete { offsets in
                                        for page in offsets.map({ hereMarks[$0] }) {
                                            progress.removeBookmark(pageIndex: page, for: volume.id)
                                        }
                                        bookmarkTick += 1
                                        progress.notifyLibrary()
                                    }
                                } header: {
                                    let pagePct = Int(
                                        (Double(currentPageIndex + 1) / Double(max(volume.pageCount, 1)) * 100)
                                            .rounded()
                                    )
                                    Text(
                                        otherMarks.isEmpty
                                            ? "\(AppCopy.bookmarkList)（\(hereMarks.count)）· \(pagePct)%"
                                            : "\(AppCopy.bookmarkHereSection) · \(AppCopy.hereNow) · \(pagePct)%"
                                    )
                                    .monospacedDigit()
                                    .accessibilityLabel(
                                        otherMarks.isEmpty
                                            ? AppCopy.bookmarkList
                                            : AppCopy.bookmarkHereSection
                                    )
                                    .accessibilityValue(
                                        "\(AppCopy.hereNow)、\(pagePct)%"
                                    )
                                } footer: {
                                    let pagePct = Int(
                                        (Double(currentPageIndex + 1) / Double(max(volume.pageCount, 1)) * 100)
                                            .rounded()
                                    )
                                    if otherMarks.isEmpty {
                                        Text("\(AppCopy.bookmarkListFooter) · \(AppCopy.hereNow) · \(pagePct)%")
                                    } else {
                                        Text("\(AppCopy.currentPageLabel) · \(pagePct)%")
                                    }
                                }
                            }
                            if !otherMarks.isEmpty {
                                Section {
                                    ForEach(otherMarks, id: \.self) { page in
                                        bookmarkRow(page, here: false)
                                    }
                                    .onDelete { offsets in
                                        for page in offsets.map({ otherMarks[$0] }) {
                                            progress.removeBookmark(pageIndex: page, for: volume.id)
                                        }
                                        bookmarkTick += 1
                                        progress.notifyLibrary()
                                    }
                                } header: {
                                    if let nearest = otherMarks.first {
                                        let pagePct = Int(
                                            (Double(nearest + 1) / Double(max(volume.pageCount, 1)) * 100)
                                                .rounded()
                                        )
                                        Text(
                                            hereMarks.isEmpty
                                                ? "\(AppCopy.bookmark)（\(otherMarks.count)）· \(pagePct)%"
                                                : "\(AppCopy.bookmarkOtherSection)（\(otherMarks.count)）· \(pagePct)%"
                                        )
                                        .monospacedDigit()
                                        .accessibilityLabel(
                                            hereMarks.isEmpty
                                                ? AppCopy.bookmarkList
                                                : AppCopy.bookmarkOtherSection
                                        )
                                        .accessibilityValue(
                                            "\(otherMarks.count)、\(pagePct)%"
                                        )
                                    } else {
                                        Text(
                                            hereMarks.isEmpty
                                                ? "\(AppCopy.bookmark)（\(otherMarks.count)）"
                                                : "\(AppCopy.bookmarkOtherSection)（\(otherMarks.count)）"
                                        )
                                    }
                                } footer: {
                                    if let nearest = otherMarks.first {
                                        let pagePct = Int(
                                            (Double(nearest + 1) / Double(max(volume.pageCount, 1)) * 100)
                                                .rounded()
                                        )
                                        Text(
                                            "\(bookmarkSubtitle(page: nearest, here: false)) · \(pagePct)% · \(AppCopy.jumpToPage)"
                                        )
                                    } else {
                                        Text("\(AppCopy.bookmarkListFooter) · \(AppCopy.jumpToPage)")
                                    }
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                        .onAppear {
                            if marks.contains(currentPageIndex) {
                                proxy.scrollTo(currentPageIndex, anchor: .center)
                            } else if let nearest = otherMarks.first {
                                proxy.scrollTo(nearest, anchor: .center)
                            }
                        }
                    }
                }
            }
            .navigationTitle(
                marks.isEmpty
                    ? AppCopy.bookmarkList
                    : "\(AppCopy.bookmarkList)（\(marks.count)）"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.close) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showBookmarks = false
                    }
                    .accessibilityLabel(AppCopy.close)
                    .accessibilityValue(
                        {
                            let pagePct = Int(
                                (Double(currentPageIndex + 1) / Double(max(volume.pageCount, 1)) * 100)
                                    .rounded()
                            )
                            var parts = [
                                "\(AppCopy.hereNow) \(currentPageIndex + 1) / \(volume.pageCount) · \(pagePct)%",
                            ]
                            if !marks.isEmpty {
                                parts.append("\(AppCopy.bookmark) \(marks.count)")
                            }
                            return parts.joined(separator: "、")
                        }()
                    )
                    .accessibilityHint(AppCopy.currentPageLabel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showBookmarks = false
                        showThumbnails = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                    .accessibilityLabel(AppCopy.thumbnails)
                    .accessibilityValue(
                        marks.isEmpty
                            ? AppCopy.hereNow
                            : "\(AppCopy.bookmark) \(marks.count)"
                    )
                    .accessibilityHint(
                        marks.isEmpty
                            ? AppCopy.thumbnails
                            : "\(AppCopy.bookmark) \(marks.count) · \(AppCopy.bookmarkListFooter)"
                    )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        progress.toggleBookmark(pageIndex: currentPageIndex, for: volume.id)
                        bookmarkTick += 1
                        progress.notifyLibrary()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Label(
                            marks.contains(currentPageIndex)
                                ? AppCopy.bookmarkRemove
                                : AppCopy.bookmarkAdd,
                            systemImage: marks.contains(currentPageIndex)
                                ? "bookmark.fill"
                                : "bookmark"
                        )
                        .labelStyle(.iconOnly)
                        .foregroundStyle(marks.contains(currentPageIndex) ? .orange : .primary)
                    }
                    .accessibilityLabel(
                        marks.contains(currentPageIndex)
                            ? AppCopy.bookmarkRemove
                            : AppCopy.bookmarkAdd
                    )
                    .accessibilityHint(
                        {
                            let pagePct = Int(
                                (Double(currentPageIndex + 1) / Double(max(volume.pageCount, 1)) * 100)
                                    .rounded()
                            )
                            return "\(currentPageIndex + 1) / \(volume.pageCount) · \(pagePct)%"
                        }()
                    )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !marks.isEmpty {
                        Menu {
                            Button(AppCopy.bookmarkClearAll, role: .destructive) {
                                confirmClearBookmarks = true
                            }
                        } label: {
                            Label {
                                Text("\(marks.count)")
                                    .monospacedDigit()
                            } icon: {
                                Image(systemName: "bookmark.fill")
                                    .foregroundStyle(.orange)
                            }
                            .font(.caption.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                        }
                        .accessibilityLabel(AppCopy.bookmarkList)
                        .accessibilityValue("\(AppCopy.bookmark) \(marks.count)")
                        .accessibilityHint(AppCopy.bookmarkClearAll)
                    }
                }
            }
            .confirmationDialog(
                AppCopy.bookmarkClearAll,
                isPresented: $confirmClearBookmarks,
                titleVisibility: .visible
            ) {
                Button(
                    "\(AppCopy.bookmarkClearAll)（\(marks.count)）",
                    role: .destructive
                ) {
                    progress.clearBookmarks(for: volume.id)
                    bookmarkTick += 1
                    progress.notifyLibrary()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                Button(AppCopy.cancel, role: .cancel) {}
            } message: {
                Text("\(AppCopy.bookmarkClearAllMessage)\n\(AppCopy.bookmark) \(marks.count)")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    @ViewBuilder
    private func bookmarkRow(_ page: Int, here: Bool) -> some View {
        Button {
            jumpToPage(page)
            showBookmarks = false
            // いまここ以外のしおりへ＝続きを読む相当
            UIImpactFeedbackGenerator(style: here ? .light : .medium).impactOccurred()
        } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    CoverThumbView(
                        imageURL: volume.pageURL(at: page),
                        cornerRadius: 4
                    )
                    .frame(width: 44)
                    .overlay {
                        if here {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(.tint, lineWidth: 2)
                        }
                    }
                    if here {
                        Text(AppCopy.hereNow)
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.tint, in: Capsule())
                            .foregroundStyle(.white)
                            .offset(x: 6, y: -6)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(page + 1) / \(volume.pageCount) \(AppCopy.pageCountSuffix)")
                        .font(.headline)
                        .monospacedDigit()
                    Text(bookmarkSubtitle(page: page, here: here))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(here ? .tint : .secondary)
                    let pagePct = Int(
                        (Double(page + 1) / Double(max(volume.pageCount, 1)) * 100)
                            .rounded()
                    )
                    Text(here ? "\(AppCopy.hereNow) · \(pagePct)%" : "\(pagePct)%")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(here ? .tint : .tertiary)
                        .accessibilityHidden(true)
                    ProgressView(
                        value: Double(page + 1),
                        total: Double(max(volume.pageCount, 1))
                    )
                    .tint(here ? .accentColor : .secondary)
                }
                Spacer(minLength: 8)
                let pagePctTrailing = Int(
                    (Double(page + 1) / Double(max(volume.pageCount, 1)) * 100)
                        .rounded()
                )
                if here {
                    Label {
                        Text("\(pagePctTrailing)%")
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(.orange)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .labelStyle(.titleAndIcon)
                } else {
                    Label {
                        Text("\(AppCopy.jumpToPage) · \(pagePctTrailing)%")
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(.orange)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .labelStyle(.titleAndIcon)
                }
            }
        }
        .listRowBackground(here ? Color.accentColor.opacity(0.08) : nil)
        .id(page)
        .accessibilityLabel("\(AppCopy.bookmark) \(page + 1) / \(volume.pageCount)")
        .accessibilityValue({
            let pagePct = Int(
                (Double(page + 1) / Double(max(volume.pageCount, 1)) * 100).rounded()
            )
            return here
                ? "\(AppCopy.hereNow)、\(pagePct)%"
                : "\(bookmarkSubtitle(page: page, here: false))、\(pagePct)%"
        }())
        .accessibilityHint(
            {
                let pagePct = Int(
                    (Double(page + 1) / Double(max(volume.pageCount, 1)) * 100).rounded()
                )
                return here
                    ? "\(AppCopy.currentPageLabel) · \(pagePct)%"
                    : "\(AppCopy.jumpToPage) · \(pagePct)%"
            }()
        )
        .accessibilityAddTraits(.isButton)
        .swipeActions {
            Button(AppCopy.bookmarkRemove, role: .destructive) {
                progress.removeBookmark(pageIndex: page, for: volume.id)
                bookmarkTick += 1
                progress.notifyLibrary()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            if !here {
                Button(AppCopy.jumpToPage) {
                    jumpToPage(page)
                    showBookmarks = false
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                .tint(.accentColor)
            }
        }
    }

    private func bookmarkSubtitle(page: Int, here: Bool) -> String {
        if here { return AppCopy.currentPageLabel }
        let delta = page - currentPageIndex
        if delta > 0 { return AppCopy.bookmarkPagesAhead(delta) }
        if delta < 0 { return AppCopy.bookmarkPagesBehind(-delta) }
        return AppCopy.jumpToPage
    }

    private var readerSettingsSheet: some View {
        NavigationStack {
            Form {
                Section(AppCopy.readingDirection) {
                    Picker(AppCopy.readingDirection, selection: $direction) {
                        ForEach(ReadingDirection.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
                Section(AppCopy.pageLayout) {
                    Picker(AppCopy.pageLayout, selection: $prefs.layoutMode) {
                        ForEach(PageLayoutMode.allCases) { Text($0.label).tag($0) }
                    }
                    Text(DisplayLayoutResolver.explainsToUser)
                        .font(.footnote).foregroundStyle(.secondary)
                    Toggle(AppCopy.coverAlone, isOn: $prefs.coverAlone)
                    Picker(AppCopy.pageTurn, selection: $prefs.turnStyle) {
                        ForEach(PageTurnStyle.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section(AppCopy.fit) {
                    Picker(AppCopy.fit, selection: $prefs.fitMode) {
                        ForEach(PageFitMode.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section(AppCopy.brightness) {
                    Slider(value: $prefs.brightness, in: 0.35...1.0)
                }
                Section(AppCopy.settingsDisplay) {
                    Toggle(AppCopy.keepScreenOn, isOn: $prefs.keepScreenOn)
                        .onChange(of: prefs.keepScreenOn) { _, v in
                            UIApplication.shared.isIdleTimerDisabled = v
                        }
                }
            }
            .navigationTitle(AppCopy.readingSettings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.close) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showReaderSettings = false
                    }
                    .accessibilityLabel(AppCopy.close)
                    .accessibilityValue(
                        {
                            let pagePct = Int(
                                (Double(currentPageIndex + 1) / Double(max(volume.pageCount, 1)) * 100)
                                    .rounded()
                            )
                            return "\(AppCopy.hereNow) \(currentPageIndex + 1) / \(volume.pageCount) · \(pagePct)%"
                        }()
                    )
                    .accessibilityHint(AppCopy.readingSettings)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppCopy.doneReadingSettings) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showReaderSettings = false
                    }
                    .accessibilityLabel(AppCopy.doneReadingSettings)
                    .accessibilityValue(prefs.layoutMode.label)
                    .accessibilityHint(AppCopy.currentPageLabel)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct WebtoonVisibleKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
