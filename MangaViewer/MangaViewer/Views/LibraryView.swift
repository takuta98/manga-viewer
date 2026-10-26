import SwiftUI
import UIKit

struct LibraryView: View {
    @ObservedObject var library: LibraryStore
    var onOpen: (MangaVolume, Bool) -> Void

    @ObservedObject private var activity = TransferActivityCenter.shared
    @ObservedObject private var progress = ProgressStore.shared
    @State private var showGetWorks = false
    @State private var showDownloads = false
    @State private var showSettings = false
    @State private var query = ""
    @State private var showNewSeries = false
    @State private var newSeriesName = ""
    @State private var renameTarget: MangaVolume?
    @State private var renameText = ""
    @State private var moveTarget: MangaVolume?
    @State private var volumePendingDelete: MangaVolume?
    @State private var folderPendingDelete: LibraryFolder?
    @State private var displayMode: LibraryDisplayMode = AppSettingsStore.loadLibraryDisplayMode()
    @State private var infoTarget: MangaVolume?

    private var inFolder: Bool { library.currentFolderId != nil }
    private var currentFolder: LibraryFolder? {
        library.folders.first { $0.id == library.currentFolderId }
    }
    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displayedVolumes: [MangaVolume] {
        let _ = progress.revision
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [MangaVolume]
        if q.isEmpty {
            base = library.volumes(in: library.currentFolderId)
        } else if inFolder {
            base = library.volumes(in: library.currentFolderId)
                .filter { $0.title.localizedStandardContains(q) }
        } else {
            base = library.sortedVolumes.filter { $0.title.localizedStandardContains(q) }
        }
        // シリーズ内／検索結果：続き → 未読 → 読了（％降順→しおり降順→タイトル）
        guard inFolder || !q.isEmpty else { return base }
        return base.sorted { a, b in
            let pa = progress.progressPercent(for: a, coverAlone: true, layout: .single)
            let pb = progress.progressPercent(for: b, coverAlone: true, layout: .single)
            let ra = shelfReadRank(pa)
            let rb = shelfReadRank(pb)
            if ra != rb { return ra < rb }
            if pa != pb { return pa > pb }
            let ma = progress.bookmarks(for: a.id).count
            let mb = progress.bookmarks(for: b.id).count
            if ma != mb { return ma > mb }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    private func shelfReadRank(_ pct: Int) -> Int {
        if pct > 0 && pct < 100 { return 0 }
        if pct == 0 { return 1 }
        return 2
    }

    private var displayedFolders: [LibraryFolder] {
        guard !inFolder else { return [] }
        let _ = progress.revision
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let list: [LibraryFolder]
        if q.isEmpty {
            list = library.sortedFolders
        } else {
            list = library.sortedFolders.filter { folder in
                folder.name.localizedStandardContains(q)
                    || library.volumes(in: folder.id).contains {
                        $0.title.localizedStandardContains(q)
                    }
            }
        }
        // 続きがあるシリーズを先に（同ランクは最大進み％→しおり件数→名前）
        return list.sorted { a, b in
            let aStats = folderReadingStats(a)
            let bStats = folderReadingStats(b)
            if aStats.rank != bStats.rank { return aStats.rank < bStats.rank }
            if aStats.maxPct != bStats.maxPct { return aStats.maxPct > bStats.maxPct }
            if aStats.marks != bStats.marks { return aStats.marks > bStats.marks }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    private func folderReadingStats(_ folder: LibraryFolder) -> (rank: Int, maxPct: Int, marks: Int) {
        let vols = library.volumes(in: folder.id)
        var maxPct = 0
        var hasReading = false
        var hasUnread = false
        var marks = 0
        for vol in vols {
            let pct = progress.progressPercent(for: vol, coverAlone: true, layout: .single)
            if pct > 0 && pct < 100 {
                hasReading = true
                maxPct = max(maxPct, pct)
            } else if pct == 0 {
                hasUnread = true
            } else {
                maxPct = max(maxPct, pct)
            }
            marks += progress.bookmarks(for: vol.id).count
        }
        let rank: Int
        if hasReading { rank = 0 }
        else if hasUnread { rank = 1 }
        else { rank = 2 }
        return (rank, maxPct, marks)
    }

    private var continueVolume: MangaVolume? {
        guard !inFolder, !isSearching else { return nil }
        let _ = progress.revision
        // 読書中のうち進捗がいちばん高い巻（同％はしおり件数→タイトル）
        return library.sortedVolumes
            .map { vol -> (MangaVolume, Int, Int) in
                (
                    vol,
                    progress.progressPercent(for: vol, coverAlone: true, layout: .single),
                    progress.bookmarks(for: vol.id).count
                )
            }
            .filter { $0.1 > 0 && $0.1 < 100 }
            .max(by: { a, b in
                if a.1 != b.1 { return a.1 < b.1 }
                if a.2 != b.2 { return a.2 < b.2 }
                return a.0.title.localizedStandardCompare(b.0.title) == .orderedAscending
            })?
            .0
    }

    private var isEmpty: Bool {
        displayedFolders.isEmpty && displayedVolumes.isEmpty && continueVolume == nil
    }

    private var readyDownloadCount: Int {
        activity.jobs.filter {
            $0.isFinished && !$0.isFailed && !$0.isCancelled && $0.volumeId != nil
                && library.volumes.contains { vol in vol.id == $0.volumeId }
        }.count
    }

    private var singleReadyPercent: Int? {
        let _ = progress.revision
        guard activity.activeCount == 0, readyDownloadCount == 1,
              let job = activity.jobs.first(where: { job in
                  guard job.isFinished, !job.isFailed, !job.isCancelled,
                        let vid = job.volumeId else { return false }
                  return library.volumes.contains { $0.id == vid }
              }),
              let vid = job.volumeId,
              let vol = library.volumes.first(where: { $0.id == vid }) else { return nil }
        return progress.progressPercent(for: vol, coverAlone: true, layout: .single)
    }

    private var singleReadyResume: Bool {
        guard let pct = singleReadyPercent else { return false }
        return pct > 0 && pct < 100
    }

    private var singleReadyMarks: Int {
        let _ = progress.revision
        guard activity.activeCount == 0, readyDownloadCount == 1,
              let job = activity.jobs.first(where: { job in
                  guard job.isFinished, !job.isFailed, !job.isCancelled,
                        let vid = job.volumeId else { return false }
                  return library.volumes.contains { $0.id == vid }
              }),
              let vid = job.volumeId else { return 0 }
        return progress.bookmarks(for: vid).count
    }

    var body: some View {
        Group {
            if isEmpty {
                emptyState
            } else if displayMode == .grid {
                gridContent
            } else {
                listContent
            }
        }
        .searchable(text: $query, prompt: AppCopy.librarySearchPrompt)
        .onSubmit(of: .search) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .navigationTitle(currentFolder?.name ?? AppCopy.libraryTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) {
            DownloadStatusChip { showDownloads = true }
                .environmentObject(library)
        }
        .environmentObject(library)
        .sheet(isPresented: $showGetWorks) {
            ImportHubView(library: library)
                .environmentObject(library)
        }
        .sheet(isPresented: $showDownloads) {
            TransferStatusView()
                .environmentObject(library)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView { mode in displayMode = mode }
                .environmentObject(library)
        }
        .sheet(item: $infoTarget) { vol in
            VolumeInfoView(library: library, volume: vol) { autoResume in
                onOpen(vol, autoResume)
            }
        }
        .sheet(item: $renameTarget) { volume in
            NavigationStack {
                Form { TextField(AppCopy.titleField, text: $renameText) }
                    .navigationTitle(AppCopy.rename)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(AppCopy.cancel) { renameTarget = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(AppCopy.save) {
                                library.rename(volume, title: renameText)
                                renameTarget = nil
                            }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $moveTarget) { volume in
            moveSheet(volume)
        }
        .alert(AppCopy.newSeries, isPresented: $showNewSeries) {
            TextField(AppCopy.seriesName, text: $newSeriesName)
            Button(AppCopy.cancel, role: .cancel) {}
            Button(AppCopy.create) {
                let n = newSeriesName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty { _ = library.createFolder(name: n) }
            }
        }
        .alert(
            AppCopy.deleteSeriesTitle,
            isPresented: Binding(
                get: { folderPendingDelete != nil },
                set: { if !$0 { folderPendingDelete = nil } }
            ),
            presenting: folderPendingDelete
        ) { folder in
            Button(AppCopy.cancel, role: .cancel) { folderPendingDelete = nil }
            Button(AppCopy.delete, role: .destructive) {
                library.deleteFolder(folder)
                folderPendingDelete = nil
            }
        } message: { folder in
            Text(AppCopy.deleteSeriesMessage(folder.name))
        }
        .alert(
            AppCopy.deleteVolumeTitle,
            isPresented: Binding(
                get: { volumePendingDelete != nil },
                set: { if !$0 { volumePendingDelete = nil } }
            ),
            presenting: volumePendingDelete
        ) { volume in
            Button(AppCopy.cancel, role: .cancel) { volumePendingDelete = nil }
            Button(AppCopy.delete, role: .destructive) {
                library.delete(volume)
                volumePendingDelete = nil
            }
        } message: { volume in
            Text(AppCopy.deleteVolumeMessage(volume.title))
        }
        .onAppear { TransferActivityCenter.requestNotificationPermissionOnce() }
        .onChange(of: library.currentFolderId) { _, _ in query = "" }
        .onChange(of: activity.pendingOpenVolumeId) { _, id in
            guard id != nil else { return }
            showGetWorks = false
            showDownloads = false
            showSettings = false
            infoTarget = nil
        }
        .safeAreaInset(edge: .top) {
            if let err = library.catalogLoadError {
                HStack(alignment: .top, spacing: 8) {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        library.catalogLoadError = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                    }
                    .accessibilityLabel(AppCopy.close)
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.85))
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if isSearching {
            ContentUnavailableView {
                Label(AppCopy.librarySearchEmptyTitle, systemImage: "magnifyingglass")
            } description: {
                Text(AppCopy.librarySearchEmptyBody)
            } actions: {
                Button(AppCopy.clearSearch) { query = "" }
                    .buttonStyle(.bordered)
            }
        } else if inFolder {
            ContentUnavailableView {
                Label(AppCopy.seriesEmptyTitle, systemImage: "rectangle.stack")
            } description: {
                Text(AppCopy.seriesEmptyBody)
            } actions: {
                Button { showGetWorks = true } label: {
                    Label(AppCopy.seriesEmptyGetWorks, systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    library.currentFolderId = nil
                } label: {
                    Label(AppCopy.backToAllWorks, systemImage: "books.vertical")
                }
                .buttonStyle(.bordered)
            }
        } else {
            ContentUnavailableView {
                Label(AppCopy.libraryEmptyTitle, systemImage: "books.vertical")
            } description: {
                if readyDownloadCount > 0 {
                    Text(
                        {
                            if readyDownloadCount == 1 && singleReadyResume {
                                var parts = [
                                    "\(AppCopy.readyToRead)（1）",
                                    "\(AppCopy.continueReading) \(singleReadyPercent ?? 0)%",
                                ]
                                if singleReadyMarks > 0 {
                                    parts.append("\(AppCopy.bookmark) \(singleReadyMarks)")
                                }
                                return parts.joined(separator: " · ")
                            }
                            if readyDownloadCount == 1 && singleReadyMarks > 0 {
                                return "\(AppCopy.readyToRead)（1）· \(AppCopy.bookmark) \(singleReadyMarks) · \(AppCopy.tapToReadHint)"
                            }
                            return "\(AppCopy.readyToRead)（\(readyDownloadCount)）· \(AppCopy.tapToReadHint)"
                        }()
                    )
                } else if activity.activeCount > 0 {
                    Text(AppCopy.downloadActiveCount(activity.activeCount))
                } else {
                    Text(AppCopy.libraryEmptyBody)
                }
            } actions: {
                if readyDownloadCount > 0, activity.activeCount == 0 {
                    Button {
                        if readyDownloadCount == 1,
                           let job = activity.jobs.first(where: { job in
                               guard job.isFinished, !job.isFailed, !job.isCancelled,
                                     let vid = job.volumeId else { return false }
                               return library.volumes.contains { $0.id == vid }
                           }),
                           let vid = job.volumeId {
                            activity.toast = nil
                            activity.pendingOpenVolumeId = vid
                            UIImpactFeedbackGenerator(
                                style: singleReadyResume ? .medium : .light
                            ).impactOccurred()
                        } else {
                            showDownloads = true
                        }
                    } label: {
                        Label(
                            singleReadyResume
                                ? (singleReadyMarks > 0
                                    ? "\(AppCopy.continueReading) \(singleReadyPercent ?? 0)% · \(AppCopy.bookmark) \(singleReadyMarks)"
                                    : (singleReadyPercent.map { "\(AppCopy.continueReading) \($0)%" }
                                        ?? AppCopy.continueReading))
                                : (singleReadyMarks > 0
                                    ? "\(AppCopy.readNow) · \(AppCopy.bookmark) \(singleReadyMarks)"
                                    : AppCopy.readNow),
                            systemImage: singleReadyResume ? "play.fill" : "book"
                        )
                        .monospacedDigit()
                    }
                    .buttonStyle(.borderedProminent)
                }
                if activity.activeCount > 0 {
                    Button { showDownloads = true } label: {
                        Label(AppCopy.downloads, systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.bordered)
                }
                if readyDownloadCount > 0 || activity.activeCount > 0 {
                    Button { showGetWorks = true } label: {
                        Label(AppCopy.libraryEmptyCTA, systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(AppCopy.getWorks)
                    .accessibilityHint(AppCopy.libraryEmptyBody)
                } else {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showGetWorks = true
                    } label: {
                        Label(AppCopy.libraryEmptyCTA, systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel(AppCopy.getWorks)
                    .accessibilityHint(AppCopy.libraryEmptyBody)
                }
            }
        }
    }

    private var gridContent: some View {
        let _ = progress.revision
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if let continueVolume {
                    let pct = progress.progressPercent(
                        for: continueVolume, coverAlone: true, layout: .single
                    )
                    let marks = progress.bookmarks(for: continueVolume.id).count
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            marks > 0
                                ? "\(AppCopy.continueReading) · \(pct)% · \(AppCopy.bookmark) \(marks)"
                                : "\(AppCopy.continueReading) · \(pct)%"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .accessibilityLabel(AppCopy.continueReading)
                        .accessibilityValue(
                            marks > 0
                                ? "\(pct)%、\(AppCopy.bookmark) \(marks)"
                                : "\(pct)%"
                        )
                        continueCard(continueVolume)
                    }
                    .padding(.horizontal, 16)
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 118), spacing: 14)],
                    spacing: 18
                ) {
                    ForEach(displayedFolders) { folder in
                        seriesCell(folder)
                    }
                    ForEach(displayedVolumes) { volume in
                        volumeCell(volume)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 12)
        }
    }

    private var listContent: some View {
        let _ = progress.revision
        return List {
            if let continueVolume {
                let pct = progress.progressPercent(
                    for: continueVolume, coverAlone: true, layout: .single
                )
                let marks = progress.bookmarks(for: continueVolume.id).count
                Section {
                    continueCard(continueVolume)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        .listRowBackground(Color.clear)
                } header: {
                    Text(
                        marks > 0
                            ? "\(AppCopy.continueReading) · \(pct)% · \(AppCopy.bookmark) \(marks)"
                            : "\(AppCopy.continueReading) · \(pct)%"
                    )
                    .monospacedDigit()
                    .accessibilityLabel(AppCopy.continueReading)
                    .accessibilityValue(
                        marks > 0
                            ? "\(pct)%、\(AppCopy.bookmark) \(marks)"
                            : "\(pct)%"
                    )
                }
            }
            ForEach(displayedFolders) { folder in
                let vols = library.volumes(in: folder.id)
                let readingVols = vols.filter {
                    let pct = progress.progressPercent(for: $0, coverAlone: true, layout: .single)
                    return pct > 0 && pct < 100
                }
                let reading = readingVols.count
                let done = vols.filter {
                    progress.progressPercent(for: $0, coverAlone: true, layout: .single) >= 100
                }.count
                let marks = vols.reduce(0) { $0 + progress.bookmarks(for: $1.id).count }
                let maxReadingPct = readingVols
                    .map { progress.progressPercent(for: $0, coverAlone: true, layout: .single) }
                    .max() ?? 0
                let coverURL = readingVols
                    .max(by: {
                        progress.progressPercent(for: $0, coverAlone: true, layout: .single)
                            < progress.progressPercent(for: $1, coverAlone: true, layout: .single)
                    })?.coverURL()
                    ?? vols.first(where: {
                        progress.progressPercent(for: $0, coverAlone: true, layout: .single) == 0
                    })?.coverURL()
                    ?? vols.first?.coverURL()
                Button {
                    UIImpactFeedbackGenerator(style: reading > 0 ? .medium : .light)
                        .impactOccurred()
                    library.currentFolderId = folder.id
                } label: {
                    HStack(spacing: 12) {
                        ZStack(alignment: .bottomLeading) {
                            FolderThumbView(coverURL: coverURL)
                                .frame(width: 48)
                            if reading > 0 || done > 0 || marks > 0 {
                                HStack(spacing: 2) {
                                    if reading > 0, maxReadingPct > 0 {
                                        CoverProgressBadge(percent: maxReadingPct, compact: true)
                                    } else if reading > 0 || done > 0 {
                                        Text(
                                            reading > 0
                                                ? "\(AppCopy.continueReading) \(reading)"
                                                : "\(AppCopy.finishedReading) \(done)"
                                        )
                                        .font(.system(size: 8, weight: .semibold))
                                        .monospacedDigit()
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 1)
                                        .background {
                                            if reading > 0 {
                                                Capsule().fill(Color.accentColor.opacity(0.28))
                                            } else {
                                                Capsule().fill(Color.green.opacity(0.32))
                                            }
                                        }
                                    }
                                    if marks > 0 {
                                        CoverBookmarkBadge(count: marks, compact: true)
                                    }
                                }
                                .padding(2)
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(folder.name).font(.headline).lineLimit(1)
                            HStack(spacing: 6) {
                                Text("\(library.volumeCount(in: folder.id)) \(AppCopy.volumeCountSuffix)")
                                if reading > 0 {
                                    Text(
                                        maxReadingPct > 0
                                            ? (marks > 0
                                                ? "\(AppCopy.continueReading) \(maxReadingPct)% · \(AppCopy.bookmark) \(marks)"
                                                : "\(AppCopy.continueReading) \(maxReadingPct)%")
                                            : (marks > 0
                                                ? "\(AppCopy.continueReading) \(reading) · \(AppCopy.bookmark) \(marks)"
                                                : "\(AppCopy.continueReading) \(reading)")
                                    )
                                        .foregroundStyle(.tint)
                                        .monospacedDigit()
                                }
                                if done > 0 {
                                    Text("\(AppCopy.finishedReading) \(done)")
                                }
                                if marks > 0, reading == 0 {
                                    Label {
                                        Text("\(marks)")
                                            .monospacedDigit()
                                    } icon: {
                                        Image(systemName: "bookmark.fill")
                                            .foregroundStyle(.orange)
                                    }
                                    .labelStyle(.titleAndIcon)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .accessibilityLabel(folder.name)
                .accessibilityValue(
                    "\(library.volumeCount(in: folder.id)) \(AppCopy.volumeCountSuffix)"
                        + (reading > 0 && maxReadingPct > 0
                            ? "、\(AppCopy.continueReading) \(maxReadingPct)%"
                            : (reading > 0 ? "、\(AppCopy.continueReading) \(reading)" : ""))
                        + (done > 0 ? "、\(AppCopy.finishedReading) \(done)" : "")
                        + (marks > 0 ? "、\(AppCopy.bookmark) \(marks)" : "")
                )
                .accessibilityHint(
                    {
                        if reading > 0 && maxReadingPct > 0 {
                            return marks > 0
                                ? "\(AppCopy.continueReading) \(maxReadingPct)% · \(AppCopy.bookmark) \(marks)"
                                : "\(AppCopy.continueReading) \(maxReadingPct)%"
                        }
                        if reading > 0 {
                            return marks > 0
                                ? "\(AppCopy.continueReading) \(reading) · \(AppCopy.bookmark) \(marks)"
                                : "\(AppCopy.continueReading) \(reading)"
                        }
                        return marks > 0
                            ? "\(AppCopy.openToRead) · \(AppCopy.bookmark) \(marks)"
                            : AppCopy.openToRead
                    }()
                )
                .swipeActions {
                    Button(role: .destructive) {
                        folderPendingDelete = folder
                    } label: {
                        Label(AppCopy.delete, systemImage: "trash")
                    }
                }
            }
            if !displayedVolumes.isEmpty {
                let readingN = displayedVolumes.filter {
                    let pct = progress.progressPercent(for: $0, coverAlone: true, layout: .single)
                    return pct > 0 && pct < 100
                }.count
                let marksN = displayedVolumes.reduce(0) {
                    $0 + progress.bookmarks(for: $1.id).count
                }
                let maxPct = displayedVolumes
                    .map { progress.progressPercent(for: $0, coverAlone: true, layout: .single) }
                    .filter { $0 > 0 && $0 < 100 }
                    .max() ?? 0
                Section {
                    ForEach(displayedVolumes) { volume in
                        let pct = progress.progressPercent(
                            for: volume,
                            coverAlone: true,
                            layout: .single
                        )
                        let resume = pct > 0 && pct < 100
                        let marks = progress.bookmarks(for: volume.id).count
                        Button {
                            UIImpactFeedbackGenerator(style: resume ? .medium : .light)
                                .impactOccurred()
                            onOpen(volume, resume)
                        } label: {
                            volumeListRow(volume)
                        }
                        .contextMenu { volumeMenu(volume) }
                        .accessibilityHint(
                            resume
                                ? (marks > 0
                                    ? "\(AppCopy.resumeReading) · \(AppCopy.bookmark) \(marks)"
                                    : AppCopy.resumeReading)
                                : (marks > 0
                                    ? "\(AppCopy.openToRead) · \(AppCopy.bookmark) \(marks)"
                                    : AppCopy.openToRead)
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                volumePendingDelete = volume
                            } label: {
                                Label(AppCopy.delete, systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                UIImpactFeedbackGenerator(style: resume ? .medium : .light)
                                    .impactOccurred()
                                onOpen(volume, resume || pct == 0)
                            } label: {
                                Label(
                                    resume
                                        ? (marks > 0
                                            ? "\(AppCopy.continueReading) \(pct)% · \(AppCopy.bookmark) \(marks)"
                                            : "\(AppCopy.continueReading) \(pct)%")
                                        : (marks > 0
                                            ? "\(AppCopy.openToRead) · \(AppCopy.bookmark) \(marks)"
                                            : AppCopy.openToRead),
                                    systemImage: resume ? "play.fill" : "book"
                                )
                            }
                            .tint(.accentColor)
                            if marks > 0 {
                                Button {
                                    infoTarget = volume
                                } label: {
                                    Label(
                                        "\(AppCopy.bookmarkList)（\(marks)）",
                                        systemImage: "bookmark.fill"
                                    )
                                }
                                .tint(.orange)
                            } else {
                                Button {
                                    infoTarget = volume
                                } label: {
                                    Label(AppCopy.info, systemImage: "info.circle")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                } header: {
                    if inFolder || isSearching {
                        Text(
                            {
                                var parts = ["\(displayedVolumes.count) \(AppCopy.volumeCountSuffix)"]
                                if readingN > 0 {
                                    parts.append(
                                        maxPct > 0
                                            ? "\(AppCopy.continueReading) \(maxPct)%"
                                            : "\(AppCopy.continueReading) \(readingN)"
                                    )
                                }
                                if marksN > 0 {
                                    parts.append("\(AppCopy.bookmark) \(marksN)")
                                }
                                return parts.joined(separator: " · ")
                            }()
                        )
                        .monospacedDigit()
                        .accessibilityLabel(AppCopy.libraryTitle)
                        .accessibilityValue(
                            {
                                var parts = ["\(displayedVolumes.count)"]
                                if readingN > 0 {
                                    parts.append(
                                        maxPct > 0
                                            ? "\(AppCopy.continueReading) \(maxPct)%"
                                            : "\(AppCopy.continueReading) \(readingN)"
                                    )
                                }
                                if marksN > 0 {
                                    parts.append("\(AppCopy.bookmark) \(marksN)")
                                }
                                return parts.joined(separator: "、")
                            }()
                        )
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func continueCard(_ volume: MangaVolume) -> some View {
        let _ = progress.revision
        let pct = progress.progressPercent(for: volume, coverAlone: true, layout: .single)
        let marks = progress.bookmarks(for: volume.id).count
        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onOpen(volume, true)
        } label: {
            HStack(spacing: 14) {
                ZStack(alignment: .bottomLeading) {
                    CoverThumbView(imageURL: volume.coverURL(), cornerRadius: 6)
                        .frame(width: 72)
                    HStack(spacing: 4) {
                        progressBadge(pct)
                        if marks > 0 { bookmarkCountBadge(marks) }
                    }
                    .padding(5)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(volume.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    ProgressView(value: Double(pct), total: 100)
                        .tint(.accentColor)
                    Text(
                        marks > 0
                            ? "\(pct)% · \(AppCopy.continueReading) · \(AppCopy.bookmark) \(marks)"
                            : "\(pct)% · \(AppCopy.continueReading)"
                    )
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.tint)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse, options: .repeating.speed(0.35), isActive: true)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(AppCopy.continueReading)、\(volume.title)")
        .accessibilityValue(
            "\(pct)%"
                + (marks > 0 ? "、\(AppCopy.bookmark) \(marks)" : "")
        )
        .accessibilityHint(
            marks > 0
                ? "\(AppCopy.resumeReading) · \(AppCopy.bookmark) \(marks)"
                : AppCopy.resumeReading
        )
        .accessibilityAddTraits(.isButton)
    }

    private func seriesCell(_ folder: LibraryFolder) -> some View {
        let _ = progress.revision
        let vols = library.volumes(in: folder.id)
        let readingVols = vols.filter {
            let pct = progress.progressPercent(for: $0, coverAlone: true, layout: .single)
            return pct > 0 && pct < 100
        }
        let reading = readingVols.count
        let done = vols.filter {
            progress.progressPercent(for: $0, coverAlone: true, layout: .single) >= 100
        }.count
        let marks = vols.reduce(0) { $0 + progress.bookmarks(for: $1.id).count }
        let maxReadingPct = readingVols
            .map { progress.progressPercent(for: $0, coverAlone: true, layout: .single) }
            .max() ?? 0
        // 続き中（進み％が高い巻）の表紙を優先。未読バッジは表紙に出さない
        let coverURL = readingVols
            .max(by: {
                progress.progressPercent(for: $0, coverAlone: true, layout: .single)
                    < progress.progressPercent(for: $1, coverAlone: true, layout: .single)
            })?.coverURL()
            ?? vols.first(where: {
                progress.progressPercent(for: $0, coverAlone: true, layout: .single) == 0
            })?.coverURL()
            ?? vols.first?.coverURL()
        return Button {
            UIImpactFeedbackGenerator(style: reading > 0 ? .medium : .light).impactOccurred()
            library.currentFolderId = folder.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomLeading) {
                    FolderThumbView(coverURL: coverURL)
                    if reading > 0 || done > 0 || marks > 0 {
                        HStack(spacing: 4) {
                            if reading > 0, maxReadingPct > 0 {
                                CoverProgressBadge(percent: maxReadingPct)
                            } else if reading > 0 {
                                Text("\(AppCopy.continueReading) \(reading)")
                                    .font(.caption2.weight(.semibold))
                                    .monospacedDigit()
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.accentColor.opacity(0.28), in: Capsule())
                                    .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                            }
                            if done > 0 {
                                Text("\(AppCopy.finishedReading) \(done)")
                                    .font(.caption2.weight(.semibold))
                                    .monospacedDigit()
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.green.opacity(0.32), in: Capsule())
                                    .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                            }
                            if marks > 0 {
                                bookmarkCountBadge(marks)
                            }
                        }
                        .padding(6)
                    }
                }
                Text(folder.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(
                    {
                        var parts = ["\(library.volumeCount(in: folder.id)) \(AppCopy.volumeCountSuffix)"]
                        if reading > 0, maxReadingPct > 0 {
                            parts.append("\(AppCopy.continueReading) \(maxReadingPct)%")
                        } else if reading > 0 {
                            parts.append("\(AppCopy.continueReading) \(reading)")
                        }
                        if marks > 0 {
                            parts.append("\(AppCopy.bookmark) \(marks)")
                        }
                        return parts.joined(separator: " · ")
                    }()
                )
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(folder.name)
        .accessibilityValue(
            "\(library.volumeCount(in: folder.id)) \(AppCopy.volumeCountSuffix)"
                + (reading > 0 && maxReadingPct > 0
                    ? "、\(AppCopy.continueReading) \(maxReadingPct)%"
                    : (reading > 0 ? "、\(AppCopy.continueReading) \(reading)" : ""))
                + (done > 0 ? "、\(AppCopy.finishedReading) \(done)" : "")
                + (marks > 0 ? "、\(AppCopy.bookmark) \(marks)" : "")
        )
        .accessibilityHint(
            {
                if reading > 0 && maxReadingPct > 0 {
                    return marks > 0
                        ? "\(AppCopy.continueReading) \(maxReadingPct)% · \(AppCopy.bookmark) \(marks)"
                        : "\(AppCopy.continueReading) \(maxReadingPct)%"
                }
                if reading > 0 {
                    return marks > 0
                        ? "\(AppCopy.continueReading) \(reading) · \(AppCopy.bookmark) \(marks)"
                        : "\(AppCopy.continueReading) \(reading)"
                }
                return marks > 0
                    ? "\(AppCopy.openToRead) · \(AppCopy.bookmark) \(marks)"
                    : AppCopy.openToRead
            }()
        )
        .contextMenu {
            Button(AppCopy.delete, role: .destructive) { folderPendingDelete = folder }
        }
    }

    private func volumeCell(_ volume: MangaVolume) -> some View {
        let _ = progress.revision
        let pct = progress.progressPercent(for: volume, coverAlone: true, layout: .single)
        let marks = progress.bookmarks(for: volume.id).count
        let resume = pct > 0 && pct < 100
        return Button {
            UIImpactFeedbackGenerator(style: resume ? .medium : .light).impactOccurred()
            onOpen(volume, resume)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomLeading) {
                    CoverThumbView(imageURL: volume.coverURL())
                    if pct > 0 || marks > 0 {
                        HStack(spacing: 4) {
                            progressBadge(pct)
                            if marks > 0 { bookmarkCountBadge(marks) }
                        }
                        .padding(6)
                    }
                }
                Text(volume.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if resume {
                    ProgressView(value: Double(pct), total: 100)
                        .tint(.accentColor)
                    Text(
                        marks > 0
                            ? "\(pct)% · \(AppCopy.continueReading) · \(AppCopy.bookmark) \(marks)"
                            : "\(pct)% · \(AppCopy.continueReading)"
                    )
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                } else if pct >= 100 {
                    Text(
                        marks > 0
                            ? "\(AppCopy.finishedReading) · \(AppCopy.bookmark) \(marks)"
                            : AppCopy.finishedReading
                    )
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                } else {
                    Text(
                        marks > 0
                            ? "\(AppCopy.openToRead) · \(AppCopy.bookmark) \(marks)"
                            : AppCopy.openToRead
                    )
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(volume.title)
        .accessibilityValue(
            pct >= 100
                ? AppCopy.finishedReading
                : (pct > 0
                    ? "\(pct)% · \(AppCopy.continueReading)"
                    : AppCopy.unread)
                + (marks > 0 ? "、\(AppCopy.bookmark) \(marks)" : "")
        )
        .accessibilityHint(
            resume
                ? (marks > 0
                    ? "\(AppCopy.resumeReading) · \(AppCopy.bookmark) \(marks)"
                    : AppCopy.resumeReading)
                : (marks > 0
                    ? "\(AppCopy.openToRead) · \(AppCopy.bookmark) \(marks)"
                    : AppCopy.openToRead)
        )
        .contextMenu { volumeMenu(volume) }
    }

    @ViewBuilder
    private func progressBadge(_ pct: Int, compact: Bool = false) -> some View {
        // 未読は表紙を汚さない。読書中／読了だけ出す
        if pct > 0 {
            CoverProgressBadge(percent: pct, compact: compact)
        }
    }

    private func bookmarkCountBadge(_ count: Int, compact: Bool = false) -> some View {
        CoverBookmarkBadge(count: count, compact: compact)
    }

    private func volumeListRow(_ volume: MangaVolume) -> some View {
        let _ = progress.revision
        let pct = progress.progressPercent(for: volume, coverAlone: true, layout: .single)
        let marks = progress.bookmarks(for: volume.id).count
        return HStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                CoverThumbView(imageURL: volume.coverURL(), cornerRadius: 4)
                    .frame(width: 48)
                if pct > 0 || marks > 0 {
                    HStack(spacing: 2) {
                        progressBadge(pct, compact: true)
                        if marks > 0 { bookmarkCountBadge(marks, compact: true) }
                    }
                    .padding(2)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(volume.title).font(.headline).lineLimit(2)
                HStack(spacing: 6) {
                    Text(
                        pct >= 100
                            ? AppCopy.finishedReading
                            : (pct > 0
                                ? "\(pct)% · \(volume.pageCount) \(AppCopy.pageCountSuffix)"
                                : "\(AppCopy.unread) · \(volume.pageCount) \(AppCopy.pageCountSuffix)")
                    )
                    .monospacedDigit()
                    if marks > 0 {
                        Label {
                            Text("\(marks)")
                                .monospacedDigit()
                        } icon: {
                            Image(systemName: "bookmark.fill")
                                .foregroundStyle(.orange)
                        }
                        .labelStyle(.titleAndIcon)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if pct > 0 && pct < 100 {
                    ProgressView(value: Double(pct), total: 100)
                        .tint(.accentColor)
                    Text(
                        marks > 0
                            ? "\(pct)% · \(AppCopy.continueReading) · \(AppCopy.bookmark) \(marks)"
                            : "\(pct)% · \(AppCopy.continueReading)"
                    )
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                } else if marks > 0 {
                    Text("\(AppCopy.bookmark) \(marks) · \(AppCopy.bookmarkListFooter)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(volume.title)
        .accessibilityValue(
            pct >= 100
                ? AppCopy.finishedReading
                : (pct > 0
                    ? "\(pct)% · \(AppCopy.continueReading)"
                    : AppCopy.unread)
                + (marks > 0 ? "、\(AppCopy.bookmark) \(marks)" : "")
        )
        .accessibilityHint(
            pct > 0 && pct < 100
                ? (marks > 0
                    ? "\(AppCopy.resumeReading) · \(AppCopy.bookmark) \(marks)"
                    : AppCopy.resumeReading)
                : (marks > 0
                    ? "\(AppCopy.openToRead) · \(AppCopy.bookmark) \(marks)"
                    : AppCopy.openToRead)
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if inFolder {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    library.currentFolderId = nil
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label(AppCopy.backToLibrary, systemImage: "chevron.left")
                }
                .accessibilityLabel(AppCopy.backToLibrary)
                .accessibilityValue(
                    {
                        guard let folder = currentFolder else { return AppCopy.libraryTitle }
                        let stats = folderReadingStats(folder)
                        var parts = [folder.name, AppCopy.libraryTitle]
                        if stats.rank == 0, stats.maxPct > 0 {
                            parts.append("\(AppCopy.continueReading) \(stats.maxPct)%")
                        }
                        if stats.marks > 0 {
                            parts.append("\(AppCopy.bookmark) \(stats.marks)")
                        }
                        return parts.joined(separator: "、")
                    }()
                )
                .accessibilityHint(AppCopy.libraryTitle)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                if activity.activeCount == 0,
                   readyDownloadCount == 1,
                   let job = activity.jobs.first(where: { job in
                       guard job.isFinished, !job.isFailed, !job.isCancelled,
                             let vid = job.volumeId else { return false }
                       return library.volumes.contains { $0.id == vid }
                   }),
                   let vid = job.volumeId {
                    activity.toast = nil
                    activity.pendingOpenVolumeId = vid
                    UIImpactFeedbackGenerator(
                        style: singleReadyResume ? .medium : .light
                    ).impactOccurred()
                } else {
                    showDownloads = true
                }
            } label: {
                let resume = singleReadyResume
                ZStack(alignment: .topTrailing) {
                    Image(
                        systemName: activity.activeCount > 0
                            ? "arrow.down.circle.fill"
                            : (readyDownloadCount == 0
                                ? "arrow.down.circle"
                                : (resume ? "play.circle.fill" : "book.closed.fill"))
                    )
                    if activity.activeCount > 0 {
                        Text("\(activity.activeCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(.red, in: Circle())
                            .offset(x: 6, y: -4)
                    } else if readyDownloadCount > 0 {
                        Text("\(readyDownloadCount)")
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(.tint, in: Circle())
                            .offset(x: 6, y: -4)
                    }
                }
            }
            .accessibilityLabel(
                readyDownloadCount == 1 && activity.activeCount == 0
                    ? (singleReadyResume ? AppCopy.continueReading : AppCopy.readNow)
                    : AppCopy.downloads
            )
            .accessibilityValue(
                activity.activeCount > 0
                    ? AppCopy.downloadActiveCount(activity.activeCount)
                    : (readyDownloadCount > 0
                        ? {
                            if readyDownloadCount == 1 && singleReadyResume {
                                var parts = ["\(AppCopy.readyToRead) · \(singleReadyPercent ?? 0)%"]
                                if singleReadyMarks > 0 {
                                    parts.append("\(AppCopy.bookmark) \(singleReadyMarks)")
                                }
                                return parts.joined(separator: " · ")
                            }
                            if readyDownloadCount == 1 && singleReadyMarks > 0 {
                                return "\(AppCopy.readyToRead) · \(AppCopy.bookmark) \(singleReadyMarks)"
                            }
                            return "\(AppCopy.readyToRead) \(readyDownloadCount)"
                        }()
                        : AppCopy.downloadEmptyTitle)
            )
            .accessibilityHint(
                readyDownloadCount == 1 && activity.activeCount == 0
                    ? (singleReadyResume
                        ? (singleReadyMarks > 0
                            ? "\(AppCopy.resumeReading) · \(AppCopy.bookmark) \(singleReadyMarks)"
                            : AppCopy.resumeReading)
                        : (singleReadyMarks > 0
                            ? "\(AppCopy.openToRead) · \(AppCopy.bookmark) \(singleReadyMarks)"
                            : AppCopy.openToRead))
                    : AppCopy.tapToReadHint
            )
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showGetWorks = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel(AppCopy.getWorks)
            .accessibilityHint(AppCopy.libraryEmptyBody)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    displayMode = displayMode.toggled
                    AppSettingsStore.saveLibraryDisplayMode(displayMode)
                } label: {
                    Label(AppCopy.displayMode, systemImage: displayMode.toggled.systemImage)
                }
                Menu {
                    ForEach(LibrarySort.allCases) { sort in
                        Button {
                            library.sort = sort
                        } label: {
                            HStack {
                                Text(sort.label)
                                if library.sort == sort {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label(AppCopy.sort, systemImage: "arrow.up.arrow.down")
                }
                if !inFolder {
                    Button { showNewSeries = true } label: {
                        Label(AppCopy.newSeries, systemImage: "rectangle.stack.badge.plus")
                    }
                }
                Button { showDownloads = true } label: {
                    Label(
                        activity.activeCount > 0
                            ? "\(AppCopy.downloads) (\(activity.activeCount))"
                            : (readyDownloadCount > 0
                                ? (readyDownloadCount == 1 && singleReadyResume
                                    ? (singleReadyMarks > 0
                                        ? "\(AppCopy.continueReading) \(singleReadyPercent ?? 0)% · \(AppCopy.bookmark) \(singleReadyMarks)"
                                        : "\(AppCopy.continueReading) \(singleReadyPercent ?? 0)%")
                                    : (readyDownloadCount == 1 && singleReadyMarks > 0
                                        ? "\(AppCopy.readNow) · \(AppCopy.bookmark) \(singleReadyMarks)"
                                        : "\(AppCopy.readyToRead) (\(readyDownloadCount))"))
                                : AppCopy.downloads),
                        systemImage: activity.activeCount > 0
                            ? "arrow.down.circle.fill"
                            : (readyDownloadCount > 0
                                ? (singleReadyResume ? "play.fill" : "book")
                                : "arrow.down.circle")
                    )
                }
                Button { showSettings = true } label: {
                    Label(AppCopy.settings, systemImage: "gearshape")
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "ellipsis.circle")
                    if activity.activeCount > 0 {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                            .offset(x: 2, y: -2)
                    }
                }
            }
            .accessibilityLabel(AppCopy.more)
            .accessibilityValue(
                {
                    var parts: [String] = []
                    if activity.activeCount > 0 {
                        parts.append("\(AppCopy.downloadActive) \(activity.activeCount)")
                    }
                    if readyDownloadCount > 0 {
                        parts.append("\(AppCopy.readyToRead) \(readyDownloadCount)")
                    }
                    if readyDownloadCount == 1, singleReadyResume,
                       let pct = singleReadyPercent {
                        parts.append("\(AppCopy.continueReading) \(pct)%")
                    }
                    if readyDownloadCount == 1, singleReadyMarks > 0 {
                        parts.append("\(AppCopy.bookmark) \(singleReadyMarks)")
                    }
                    return parts.joined(separator: "、")
                }()
            )
            .accessibilityHint(AppCopy.downloads)
        }
    }

    @ViewBuilder
    private func volumeMenu(_ volume: MangaVolume) -> some View {
        let pct = progress.progressPercent(for: volume, coverAlone: true, layout: .single)
        let marks = progress.bookmarks(for: volume.id).count
        if pct > 0 && pct < 100 {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onOpen(volume, true)
            } label: {
                Label(
                    marks > 0
                        ? "\(AppCopy.continueReading) \(pct)% · \(AppCopy.bookmark) \(marks)"
                        : "\(AppCopy.continueReading) \(pct)%",
                    systemImage: "play.fill"
                )
            }
            Button {
                progress.clearProgress(for: volume.id)
                progress.notifyLibrary()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onOpen(volume, false)
            } label: {
                Label(
                    marks > 0
                        ? "\(AppCopy.startOver) · \(AppCopy.bookmark) \(marks)"
                        : AppCopy.startOver,
                    systemImage: "backward.end"
                )
            }
        } else if pct >= 100 {
            Button {
                progress.clearProgress(for: volume.id)
                progress.notifyLibrary()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onOpen(volume, false)
            } label: {
                Label(
                    marks > 0
                        ? "\(AppCopy.startOver) · \(AppCopy.bookmark) \(marks)"
                        : AppCopy.startOver,
                    systemImage: "backward.end"
                )
            }
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onOpen(volume, true)
            } label: {
                Label(
                    marks > 0
                        ? "\(AppCopy.openToRead) · \(AppCopy.bookmark) \(marks)"
                        : AppCopy.openToRead,
                    systemImage: "book"
                )
            }
        } else {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onOpen(volume, false)
            } label: {
                Label(
                    marks > 0
                        ? "\(AppCopy.openToRead) · \(AppCopy.bookmark) \(marks)"
                        : AppCopy.openToRead,
                    systemImage: "book"
                )
            }
        }
        if marks > 0 {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                infoTarget = volume
            } label: {
                Label("\(AppCopy.bookmarkList)（\(marks)）", systemImage: "bookmark.fill")
            }
        }
        Button(AppCopy.info) { infoTarget = volume }
        Button(AppCopy.rename) {
            renameTarget = volume
            renameText = volume.title
        }
        Button(AppCopy.moveToSeries) { moveTarget = volume }
        Button(AppCopy.delete, role: .destructive) { volumePendingDelete = volume }
    }

    private func moveSheet(_ volume: MangaVolume) -> some View {
        NavigationStack {
            List {
                Button(AppCopy.uncategorized) {
                    library.move(volume, to: nil)
                    moveTarget = nil
                }
                ForEach(library.sortedFolders) { folder in
                    Button(folder.name) {
                        library.move(volume, to: folder.id)
                        moveTarget = nil
                    }
                }
            }
            .navigationTitle(AppCopy.moveToSeries)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.cancel) { moveTarget = nil }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
