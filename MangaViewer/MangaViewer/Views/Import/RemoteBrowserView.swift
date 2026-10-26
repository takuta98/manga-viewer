import SwiftUI
import UIKit

struct RemoteBrowserView: View {
    @ObservedObject var library: LibraryStore
    let source: RemoteSource
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var activity = TransferActivityCenter.shared
    @ObservedObject private var progressStore = ProgressStore.shared
    @State private var pathStack: [String]
    @State private var entries: [RemoteEntry] = []
    @State private var loading = false
    @State private var listError: String?
    @State private var errorText: String?
    @State private var query = ""
    @State private var showTransfers = false
    @State private var justImported: MangaVolume?
    @State private var lastImportedVolumeId: UUID?

    init(library: LibraryStore, source: RemoteSource) {
        self.library = library
        self.source = source
        if let last = source.lastBrowsePath, !last.isEmpty {
            _pathStack = State(initialValue: ["", last])
        } else {
            _pathStack = State(initialValue: [""])
        }
    }

    private var currentPath: String { pathStack.last ?? "" }
    private var folderSourceKey: String { "folder:\(currentPath)" }
    private var folderBusy: Bool { activity.isActive(sourceKey: folderSourceKey) }
    private var readyDownloadCount: Int {
        activity.jobs.filter {
            $0.isFinished && !$0.isFailed && !$0.isCancelled && $0.volumeId != nil
                && library.volumes.contains { vol in vol.id == $0.volumeId }
        }.count
    }

    private var singleReadyPercent: Int? {
        let _ = progressStore.revision
        guard activity.activeCount == 0, readyDownloadCount == 1,
              let job = activity.jobs.first(where: { job in
                  guard job.isFinished, !job.isFailed, !job.isCancelled,
                        let vid = job.volumeId else { return false }
                  return library.volumes.contains { $0.id == vid }
              }),
              let vid = job.volumeId,
              let vol = library.volumes.first(where: { $0.id == vid }) else { return nil }
        return progressStore.progressPercent(for: vol, coverAlone: true, layout: .single)
    }

    private var singleReadyResume: Bool {
        guard let pct = singleReadyPercent else { return false }
        return pct > 0 && pct < 100
    }

    private var singleReadyMarks: Int {
        let _ = progressStore.revision
        guard activity.activeCount == 0, readyDownloadCount == 1,
              let job = activity.jobs.first(where: { job in
                  guard job.isFinished, !job.isFailed, !job.isCancelled,
                        let vid = job.volumeId else { return false }
                  return library.volumes.contains { $0.id == vid }
              }),
              let vid = job.volumeId else { return 0 }
        return progressStore.bookmarks(for: vid).count
    }

    private var visible: [RemoteEntry] {
        let matched = RemoteEntryFilter.matching(entries, query: query)
        // 作品候補を先に：フォルダと対応ファイル。非対応は末尾。
        let dirs = matched.filter(\.isDirectory)
        let comics = matched.filter { !$0.isDirectory && ComicFileProbe.isSupportedForImport($0.name) }
        let other = matched.filter { !$0.isDirectory && !ComicFileProbe.isSupportedForImport($0.name) }
        return dirs + comics + other
    }

    private func cleanedTitle(for entry: RemoteEntry) -> String {
        UserFacingText.title(fromFileName: entry.name)
    }

    private func alreadyOnShelf(_ entry: RemoteEntry) -> Bool {
        let title = cleanedTitle(for: entry)
        return library.detectDuplicate(title: title) != nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if let listError {
                    ContentUnavailableView(
                        AppCopy.browseFailed,
                        systemImage: "wifi.exclamationmark",
                        description: Text(listError)
                    )
                    .overlay(alignment: .bottom) {
                        Button(AppCopy.retry) { Task { await reload() } }
                            .buttonStyle(.borderedProminent)
                            .padding()
                    }
                } else if loading {
                    VStack(spacing: 12) {
                        ProgressView(AppCopy.loading)
                        if !currentPath.isEmpty {
                            Text((currentPath as NSString).lastPathComponent)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if visible.isEmpty {
                    ContentUnavailableView {
                        Label(
                            query.isEmpty ? AppCopy.emptyFolder : AppCopy.browseSearchEmpty,
                            systemImage: query.isEmpty ? "folder" : "magnifyingglass"
                        )
                    } description: {
                        if !query.isEmpty {
                            Text(AppCopy.browseSearchPrompt)
                        } else if !currentPath.isEmpty {
                            Text(AppCopy.emptyFolderHint)
                        } else if readyDownloadCount > 0 {
                            Text(
                                {
                                    if singleReadyResume {
                                        var parts = [
                                            AppCopy.readyToRead,
                                            "\(AppCopy.continueReading) \(singleReadyPercent ?? 0)%",
                                        ]
                                        if singleReadyMarks > 0 {
                                            parts.append("\(AppCopy.bookmark) \(singleReadyMarks)")
                                        }
                                        return parts.joined(separator: " · ")
                                    }
                                    if singleReadyMarks > 0 {
                                        return "\(AppCopy.readyToRead) · \(AppCopy.bookmark) \(singleReadyMarks)"
                                    }
                                    return "\(AppCopy.readyToRead) · \(AppCopy.readNow)"
                                }()
                            )
                        } else {
                            Text(AppCopy.getWorksStayHint)
                        }
                    } actions: {
                        if !query.isEmpty {
                            Button(AppCopy.clearSearch) { query = "" }
                                .buttonStyle(.bordered)
                        } else if readyDownloadCount > 0, activity.activeCount == 0 {
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
                                    showTransfers = true
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
                        } else if !currentPath.isEmpty, !folderBusy {
                            Button(AppCopy.downloadThisFolder) { startFolderImport() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    List {
                        let dirs = visible
                            .filter(\.isDirectory)
                            .sorted {
                                $0.name.localizedStandardCompare($1.name) == .orderedAscending
                            }
                        let comics = visible.filter { !$0.isDirectory && ComicFileProbe.isSupportedForImport($0.name) }
                        let comicsOrdered = RemoteEntryFilter.worksOrdered(comics, onShelf: alreadyOnShelf)
                        let other = visible
                            .filter { !$0.isDirectory && !ComicFileProbe.isSupportedForImport($0.name) }
                            .sorted {
                                $0.name.localizedStandardCompare($1.name) == .orderedAscending
                            }
                        let newWorks = comicsOrdered.filter { !alreadyOnShelf($0) }
                        let shelfWorks = RemoteEntryFilter.shelfReadingOrdered(
                            comicsOrdered.filter(alreadyOnShelf),
                            rank: shelfReadRank,
                            percent: shelfReadPercent,
                            marks: { entry in
                                guard let existing = library.detectDuplicate(
                                    title: cleanedTitle(for: entry)
                                ) else { return 0 }
                                return progressStore.bookmarks(for: existing.id).count
                            }
                        )
                        let readingOnShelf = shelfWorks.filter { shelfReadRank($0) == 0 }.count
                        let shelfMarksN = shelfWorks.reduce(0) { sum, entry in
                            guard let existing = library.detectDuplicate(
                                title: cleanedTitle(for: entry)
                            ) else { return sum }
                            return sum + progressStore.bookmarks(for: existing.id).count
                        }
                        let _ = progressStore.revision
                        // 作品選び優先：未入手 → 本棚（続き→未読→読了） → フォルダ → その他
                        if !comicsOrdered.isEmpty {
                            Section {
                                Label {
                                    Text(
                                        AppCopy.remoteWorksSummary(
                                            new: newWorks.count,
                                            onShelf: shelfWorks.count,
                                            reading: readingOnShelf,
                                            marks: shelfMarksN
                                        )
                                    )
                                    .font(.subheadline.weight(.medium))
                                    .monospacedDigit()
                                } icon: {
                                    Image(systemName: "books.vertical")
                                        .foregroundStyle(.tint)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(AppCopy.remoteSectionWorks)
                                .accessibilityValue(
                                    AppCopy.remoteWorksSummary(
                                        new: newWorks.count,
                                        onShelf: shelfWorks.count,
                                        reading: readingOnShelf,
                                        marks: shelfMarksN
                                    )
                                )
                            } footer: {
                                Text(
                                    {
                                        if !newWorks.isEmpty { return AppCopy.getWorksStayHint }
                                        if readingOnShelf > 0 {
                                            return shelfMarksN > 0
                                                ? "\(AppCopy.onShelfReadHint) · \(AppCopy.continueReading) · \(AppCopy.bookmark) \(shelfMarksN)"
                                                : "\(AppCopy.onShelfReadHint) · \(AppCopy.continueReading)"
                                        }
                                        if shelfMarksN > 0 {
                                            return "\(AppCopy.onShelfReadHint) · \(AppCopy.bookmark) \(shelfMarksN)"
                                        }
                                        return AppCopy.onShelfReadHint
                                    }()
                                )
                            }
                        }
                        if !newWorks.isEmpty {
                            Section {
                                ForEach(newWorks) { remoteRow($0) }
                            } header: {
                                let busyN = newWorks.filter { activity.isActive(sourceKey: $0.path) }.count
                                let pending = newWorks.count - busyN
                                Text(
                                    {
                                        var parts = ["\(AppCopy.remoteSectionNewWorks)（\(newWorks.count)）"]
                                        if busyN > 0 {
                                            parts.append("\(AppCopy.downloadActive) \(busyN)")
                                        }
                                        if pending > 0 && busyN > 0 {
                                            parts.append("\(AppCopy.getThisWork) \(pending)")
                                        }
                                        return parts.joined(separator: " · ")
                                    }()
                                )
                                .monospacedDigit()
                                .accessibilityLabel(AppCopy.remoteSectionNewWorks)
                                .accessibilityValue(
                                    {
                                        var parts = ["\(newWorks.count)"]
                                        if busyN > 0 {
                                            parts.append("\(AppCopy.downloadActive) \(busyN)")
                                        }
                                        if pending > 0 {
                                            parts.append("\(AppCopy.getThisWork) \(pending)")
                                        }
                                        return parts.joined(separator: "、")
                                    }()
                                )
                                .accessibilityHint(AppCopy.getWorksStayHint)
                            } footer: {
                                let pending = newWorks.filter { !activity.isActive(sourceKey: $0.path) }.count
                                let busyN = newWorks.count - pending
                                Button {
                                    startNewWorksImport(newWorks)
                                } label: {
                                    Label(
                                        pending == newWorks.count
                                            ? AppCopy.downloadNewWorksCount(newWorks.count)
                                            : (pending > 0
                                                ? AppCopy.downloadNewWorksCount(pending)
                                                : AppCopy.downloadingFolder),
                                        systemImage: pending > 0 ? "arrow.down.circle" : "arrow.down.circle.fill"
                                    )
                                    .font(.footnote.weight(.semibold))
                                }
                                .disabled(pending == 0)
                                .accessibilityLabel(
                                    pending > 0
                                        ? AppCopy.downloadNewWorksCount(pending)
                                        : AppCopy.downloadingFolder
                                )
                                .accessibilityValue(
                                    busyN > 0
                                        ? "\(AppCopy.downloadActive) \(busyN)"
                                        : "\(AppCopy.getThisWork) \(pending)"
                                )
                                .accessibilityHint(
                                    busyN > 0
                                        ? "\(AppCopy.downloadActive) \(busyN) · \(AppCopy.getWorksStayHint)"
                                        : AppCopy.getWorksStayHint
                                )
                            }
                        }
                        if !shelfWorks.isEmpty {
                            Section {
                                ForEach(shelfWorks) { remoteRow($0) }
                            } header: {
                                Text(
                                    {
                                        var parts = ["\(AppCopy.remoteSectionOnShelf)（\(shelfWorks.count)）"]
                                        if readingOnShelf > 0 {
                                            parts.append("\(AppCopy.continueReading) \(readingOnShelf)")
                                        }
                                        if shelfMarksN > 0 {
                                            parts.append("\(AppCopy.bookmark) \(shelfMarksN)")
                                        }
                                        return parts.joined(separator: " · ")
                                    }()
                                )
                                .monospacedDigit()
                                .accessibilityLabel(AppCopy.remoteSectionOnShelf)
                                .accessibilityValue(
                                    {
                                        var parts = ["\(shelfWorks.count)"]
                                        if readingOnShelf > 0 {
                                            parts.append("\(AppCopy.continueReading) \(readingOnShelf)")
                                        }
                                        if shelfMarksN > 0 {
                                            parts.append("\(AppCopy.bookmark) \(shelfMarksN)")
                                        }
                                        return parts.joined(separator: "、")
                                    }()
                                )
                            } footer: {
                                if let pick = shelfWorks.first,
                                   let existing = library.detectDuplicate(title: cleanedTitle(for: pick)) {
                                    let pct = progressStore.progressPercent(
                                        for: existing,
                                        coverAlone: true,
                                        layout: .single
                                    )
                                    let resume = pct > 0 && pct < 100
                                    let marks = progressStore.bookmarks(for: existing.id).count
                                    Button {
                                        activity.toast = nil
                                        activity.pendingOpenVolumeId = existing.id
                                        UIImpactFeedbackGenerator(style: resume ? .medium : .light)
                                            .impactOccurred()
                                        dismiss()
                                    } label: {
                                        Label(
                                            resume
                                                ? (marks > 0
                                                    ? "\(AppCopy.continueReading) \(pct)% · \(AppCopy.bookmark) \(marks)"
                                                    : "\(AppCopy.continueReading) \(pct)%")
                                                : (marks > 0
                                                    ? "\(AppCopy.readNow) · \(AppCopy.bookmark) \(marks)"
                                                    : AppCopy.readNow),
                                            systemImage: resume ? "play.fill" : "book"
                                        )
                                        .font(.footnote.weight(.semibold))
                                        .monospacedDigit()
                                    }
                                    .accessibilityLabel(
                                        resume ? AppCopy.continueReading : AppCopy.readNow
                                    )
                                    .accessibilityValue(
                                        {
                                            var parts = [existing.title]
                                            if resume { parts.append("\(pct)%") }
                                            if marks > 0 { parts.append("\(AppCopy.bookmark) \(marks)") }
                                            return parts.joined(separator: "、")
                                        }()
                                    )
                                    .accessibilityHint(
                                        resume
                                            ? (marks > 0
                                                ? "\(AppCopy.resumeReading) · \(AppCopy.bookmark) \(marks)"
                                                : AppCopy.resumeReading)
                                            : (marks > 0
                                                ? "\(AppCopy.onShelfReadHint) · \(AppCopy.bookmark) \(marks)"
                                                : AppCopy.onShelfReadHint)
                                    )
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                } else {
                                    Text(AppCopy.onShelfReadHint)
                                }
                            }
                        }
                        if !dirs.isEmpty {
                            Section {
                                ForEach(dirs) { remoteRow($0) }
                            } header: {
                                Text("\(AppCopy.remoteSectionFolders)（\(dirs.count)）")
                                    .monospacedDigit()
                                    .accessibilityLabel(AppCopy.remoteSectionFolders)
                                    .accessibilityValue("\(dirs.count)")
                                    .accessibilityHint(AppCopy.openFolder)
                            } footer: {
                                if comicsOrdered.isEmpty {
                                    Text(AppCopy.emptyFolderHint)
                                } else {
                                    Text("\(AppCopy.openFolder) · \(AppCopy.remoteSectionWorks)")
                                }
                            }
                        }
                        if !other.isEmpty {
                            Section {
                                ForEach(other) { remoteRow($0) }
                            } header: {
                                Text("\(AppCopy.remoteSectionOther)（\(other.count)）")
                                    .monospacedDigit()
                                    .accessibilityLabel(AppCopy.remoteSectionOther)
                                    .accessibilityValue("\(other.count)")
                                    .accessibilityHint(AppCopy.unsupportedFile)
                            } footer: {
                                Text(AppCopy.unsupportedFile)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await reload() }
                }
            }
            .navigationTitle(
                currentPath.isEmpty
                    ? source.name
                    : (currentPath as NSString).lastPathComponent
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleMenu {
                ForEach(Array(pathStack.enumerated()), id: \.offset) { idx, path in
                    let label = path.isEmpty ? source.name : (path as NSString).lastPathComponent
                    Button {
                        pathStack = Array(pathStack.prefix(idx + 1))
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        if idx == pathStack.count - 1 {
                            Label(label, systemImage: "checkmark")
                        } else {
                            Text(label)
                        }
                    }
                    .accessibilityLabel(label)
                    .accessibilityValue(
                        idx == pathStack.count - 1
                            ? AppCopy.hereNow
                            : "\(idx + 1) / \(pathStack.count)"
                    )
                    .accessibilityHint(AppCopy.openFolder)
                }
            }
            .searchable(text: $query, prompt: AppCopy.browseSearchPrompt)
            .onSubmit(of: .search) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            .toolbar { toolbarContent }
            .overlay(alignment: .top) { ActivityOverlayView() }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    if let volume = justImported {
                        // 入手完了後もこの画面のまま → 読む CTA
                        let _ = progressStore.revision
                        let pct = progressStore.progressPercent(
                            for: volume,
                            coverAlone: true,
                            layout: .single
                        )
                        let marks = progressStore.bookmarks(for: volume.id).count
                        let resume = pct > 0 && pct < 100
                        HStack(spacing: 10) {
                            ZStack(alignment: .bottomLeading) {
                                CoverThumbView(imageURL: volume.coverURL(), cornerRadius: 4)
                                    .frame(width: 48)
                                if pct > 0 || marks > 0 {
                                    HStack(spacing: 2) {
                                        if pct > 0 {
                                            CoverProgressBadge(percent: pct, compact: true)
                                        }
                                        if marks > 0 {
                                            CoverBookmarkBadge(count: marks, compact: true)
                                        }
                                    }
                                    .padding(2)
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(AppCopy.downloadFinished)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(volume.title)
                                    .font(.footnote.weight(.semibold))
                                    .lineLimit(1)
                                if resume {
                                    ProgressView(value: Double(pct), total: 100)
                                        .tint(.accentColor)
                                }
                                Text(
                                    resume
                                        ? (marks > 0
                                            ? "\(pct)% · \(AppCopy.continueReading) · \(AppCopy.bookmark) \(marks)"
                                            : "\(pct)% · \(AppCopy.continueReading)")
                                        : (marks > 0
                                            ? "\(volume.pageCount) \(AppCopy.pageCountSuffix) · \(AppCopy.bookmark) \(marks)"
                                            : "\(volume.pageCount) \(AppCopy.pageCountSuffix) · \(AppCopy.openToRead)")
                                )
                                .font(.caption2.weight(resume ? .semibold : .regular))
                                .monospacedDigit()
                                .foregroundStyle(resume ? .tint : .tertiary)
                            }
                            Spacer(minLength: 0)
                            Button {
                                justImported = nil
                                activity.toast = nil
                                activity.pendingOpenVolumeId = volume.id
                                UIImpactFeedbackGenerator(style: resume ? .medium : .light).impactOccurred()
                                dismiss()
                            } label: {
                                Label(
                                    resume
                                        ? (marks > 0
                                            ? "\(AppCopy.continueReading) \(pct)% · \(AppCopy.bookmark) \(marks)"
                                            : "\(AppCopy.continueReading) \(pct)%")
                                        : (marks > 0
                                            ? "\(AppCopy.readNow) · \(AppCopy.bookmark) \(marks)"
                                            : AppCopy.readNow),
                                    systemImage: resume ? "play.fill" : "book"
                                )
                                .monospacedDigit()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .accessibilityLabel(resume ? AppCopy.continueReading : AppCopy.readNow)
                            .accessibilityValue(
                                {
                                    var parts = [volume.title]
                                    if resume { parts.append("\(pct)%") }
                                    if marks > 0 { parts.append("\(AppCopy.bookmark) \(marks)") }
                                    return parts.joined(separator: "、")
                                }()
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
                            Button {
                                justImported = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption.weight(.semibold))
                                    .frame(width: 28, height: 28)
                            }
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(AppCopy.close)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("\(AppCopy.downloadFinished)、\(volume.title)")
                        .accessibilityValue(
                            {
                                var parts: [String] = []
                                if resume { parts.append("\(pct)%") }
                                else { parts.append("\(volume.pageCount) \(AppCopy.pageCountSuffix)") }
                                if marks > 0 { parts.append("\(AppCopy.bookmark) \(marks)") }
                                return parts.joined(separator: "、")
                            }()
                        )
                        .accessibilityHint(
                            resume
                                ? (marks > 0
                                    ? "\(AppCopy.resumeReading) · \(AppCopy.bookmark) \(marks)"
                                    : AppCopy.resumeReading)
                                : (marks > 0
                                    ? "\(AppCopy.readNow) · \(AppCopy.bookmark) \(marks)"
                                    : AppCopy.readNow)
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    DownloadStatusChip { showTransfers = true }
                        .environmentObject(library)
                }
            }
            .environmentObject(library)
            .sheet(isPresented: $showTransfers) {
                TransferStatusView()
                    .environmentObject(library)
            }
            .onChange(of: activity.pendingOpenVolumeId) { _, id in
                guard id != nil else { return }
                showTransfers = false
                justImported = nil
                dismiss()
            }
            .task(id: currentPath) {
                query = ""
                await reload()
            }
            .onChange(of: currentPath) { _, newPath in
                justImported = nil
                persistBrowsePath(newPath)
            }
            .alert(
                AppCopy.errorTitle,
                isPresented: Binding(
                    get: { errorText != nil },
                    set: { if !$0 { errorText = nil } }
                )
            ) {
                Button(AppCopy.ok, role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if pathStack.count > 1 {
                Button(AppCopy.back) {
                    _ = pathStack.popLast()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                .accessibilityLabel(AppCopy.back)
                .accessibilityValue(
                    (currentPath as NSString).lastPathComponent
                )
                .accessibilityHint(AppCopy.openFolder)
            } else {
                Button(AppCopy.close) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                }
                .accessibilityLabel(AppCopy.close)
                .accessibilityValue(
                    {
                        var parts = [source.name]
                        if readyDownloadCount > 0 {
                            parts.append("\(AppCopy.readyToRead) \(readyDownloadCount)")
                        }
                        if singleReadyResume, let pct = singleReadyPercent {
                            parts.append("\(AppCopy.continueReading) \(pct)%")
                        }
                        if singleReadyMarks > 0 {
                            parts.append("\(AppCopy.bookmark) \(singleReadyMarks)")
                        }
                        return parts.joined(separator: "、")
                    }()
                )
                .accessibilityHint(AppCopy.libraryTitle)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
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
                    showTransfers = true
                }
            } label: {
                let _ = progressStore.revision
                if activity.activeCount > 0 {
                    Text(AppCopy.downloadActiveCount(activity.activeCount))
                        .font(.caption.weight(.semibold))
                } else if readyDownloadCount > 0 {
                    let resume = singleReadyResume
                    let marks = singleReadyMarks
                    Label(
                        readyDownloadCount == 1
                            ? (resume
                                ? (marks > 0
                                    ? "\(AppCopy.continueReading) \(singleReadyPercent ?? 0)% · \(AppCopy.bookmark) \(marks)"
                                    : (singleReadyPercent.map { "\(AppCopy.continueReading) \($0)%" }
                                        ?? AppCopy.continueReading))
                                : (marks > 0
                                    ? "\(AppCopy.readNow) · \(AppCopy.bookmark) \(marks)"
                                    : AppCopy.readNow))
                            : "\(readyDownloadCount)",
                        systemImage: readyDownloadCount == 1
                            ? (resume ? "play.fill" : "book")
                            : "books.vertical"
                    )
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .labelStyle(.titleAndIcon)
                } else {
                    Image(systemName: "arrow.down.circle")
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
            if !currentPath.isEmpty {
                Button(folderBusy ? AppCopy.downloadingFolder : AppCopy.downloadThisFolder) {
                    startFolderImport()
                }
                .disabled(folderBusy)
                .accessibilityHint(
                    folderBusy
                        ? AppCopy.downloadActive
                        : AppCopy.getWorksStayHint
                )
            }
        }
    }

    private func sizeLabel(_ size: Int64?) -> String? {
        guard let size, size > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// 本棚側の作品：続き → 未読 → 読了
    private func shelfReadRank(_ entry: RemoteEntry) -> Int {
        let pct = shelfReadPercent(entry)
        if pct > 0 && pct < 100 { return 0 }
        if pct == 0 { return 1 }
        return 2
    }

    private func shelfReadPercent(_ entry: RemoteEntry) -> Int {
        guard let existing = library.detectDuplicate(title: cleanedTitle(for: entry)) else { return 0 }
        return progressStore.progressPercent(for: existing, coverAlone: true, layout: .single)
    }

    @ViewBuilder
    private func remoteRow(_ entry: RemoteEntry) -> some View {
        let busy = activity.isActive(sourceKey: entry.path)
        if entry.isDirectory {
            Button {
                pathStack.append(entry.path)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.orange)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(.body.weight(.medium))
                        Text(AppCopy.openFolder)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
            }
            .accessibilityHint(AppCopy.openFolder)
        } else {
            let supported = ComicFileProbe.isSupportedForImport(entry.name)
            let onShelf = alreadyOnShelf(entry)
            let existing = onShelf ? library.detectDuplicate(title: cleanedTitle(for: entry)) : nil
            Button {
                if let existing {
                    activity.toast = nil
                    activity.pendingOpenVolumeId = existing.id
                    let pct = progressStore.progressPercent(
                        for: existing,
                        coverAlone: true,
                        layout: .single
                    )
                    let resume = pct > 0 && pct < 100
                    UIImpactFeedbackGenerator(style: resume ? .medium : .light).impactOccurred()
                    dismiss()
                } else if supported {
                    startFileImport(entry)
                }
            } label: {
                HStack(spacing: 12) {
                    if let existing {
                        let _ = progressStore.revision
                        let pct = progressStore.progressPercent(
                            for: existing,
                            coverAlone: true,
                            layout: .single
                        )
                        let marks = progressStore.bookmarks(for: existing.id).count
                        ZStack(alignment: .bottomLeading) {
                            CoverThumbView(imageURL: existing.coverURL(), cornerRadius: 4)
                                .frame(width: 44)
                            if pct > 0 || marks > 0 {
                                HStack(spacing: 2) {
                                    if pct > 0 {
                                        CoverProgressBadge(percent: pct, compact: true)
                                    }
                                    if marks > 0 {
                                        CoverBookmarkBadge(count: marks, compact: true)
                                    }
                                }
                                .padding(2)
                            }
                        }
                    } else {
                        Image(systemName: supported ? "book.closed.fill" : "doc")
                            .foregroundStyle(supported ? Color.accentColor : .secondary)
                            .frame(width: 44)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cleanedTitle(for: entry))
                            .font(.body.weight(.medium))
                            .foregroundStyle(supported || onShelf ? .primary : .secondary)
                        HStack(spacing: 6) {
                            if entry.name != cleanedTitle(for: entry) {
                                Text(entry.name)
                                    .lineLimit(1)
                            }
                            if let size = sizeLabel(entry.size) {
                                Text(size)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 8)
                    if busy {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(AppCopy.queued)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else if onShelf {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(AppCopy.onShelf)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let existing {
                                let _ = progressStore.revision
                                let pct = progressStore.progressPercent(
                                    for: existing,
                                    coverAlone: true,
                                    layout: .single
                                )
                                let marks = progressStore.bookmarks(for: existing.id).count
                                let resume = pct > 0 && pct < 100
                                Label(
                                    resume
                                        ? (marks > 0
                                            ? "\(AppCopy.continueReading) \(pct)% · \(AppCopy.bookmark) \(marks)"
                                            : "\(AppCopy.continueReading) \(pct)%")
                                        : (marks > 0
                                            ? "\(AppCopy.openToRead) · \(AppCopy.bookmark) \(marks)"
                                            : (pct >= 100
                                                ? AppCopy.finishedReading
                                                : AppCopy.openToRead)),
                                    systemImage: resume
                                        ? "play.fill"
                                        : (pct >= 100 && marks == 0 ? "checkmark.circle" : "book")
                                )
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.tint)
                                .labelStyle(.titleAndIcon)
                                if resume {
                                    ProgressView(value: Double(pct), total: 100)
                                        .tint(.accentColor)
                                        .frame(width: 72)
                                    if marks > 0 {
                                        Label {
                                            Text("\(marks)")
                                                .monospacedDigit()
                                        } icon: {
                                            Image(systemName: "bookmark.fill")
                                                .foregroundStyle(.orange)
                                        }
                                        .font(.caption2)
                                        .labelStyle(.titleAndIcon)
                                        .foregroundStyle(.secondary)
                                    }
                                } else if marks > 0 {
                                    Label {
                                        Text(
                                            pct >= 100
                                                ? "\(AppCopy.finishedReading) · \(marks)"
                                                : "\(marks)"
                                        )
                                            .monospacedDigit()
                                    } icon: {
                                        Image(systemName: "bookmark.fill")
                                            .foregroundStyle(.orange)
                                    }
                                    .font(.caption2)
                                    .labelStyle(.titleAndIcon)
                                    .foregroundStyle(.secondary)
                                }
                            } else {
                                Label(AppCopy.openToRead, systemImage: "book")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tint)
                                    .labelStyle(.titleAndIcon)
                            }
                        }
                    } else if supported {
                        Label(AppCopy.getThisWork, systemImage: "arrow.down.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                            .labelStyle(.titleAndIcon)
                    } else {
                        Text(AppCopy.unsupportedFile)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .disabled(busy || (!supported && !onShelf))
            .accessibilityLabel(cleanedTitle(for: entry))
            .accessibilityValue(
                {
                    guard let existing else { return onShelf ? AppCopy.onShelf : "" }
                    let pct = progressStore.progressPercent(
                        for: existing,
                        coverAlone: true,
                        layout: .single
                    )
                    let marks = progressStore.bookmarks(for: existing.id).count
                    let base = pct >= 100
                        ? AppCopy.finishedReading
                        : (pct > 0
                            ? "\(pct)% · \(AppCopy.continueReading)"
                            : AppCopy.unread)
                    return marks > 0 ? "\(base)、\(AppCopy.bookmark) \(marks)" : base
                }()
            )
            .accessibilityHint(
                {
                    if busy { return AppCopy.queued }
                    if let existing {
                        let pct = progressStore.progressPercent(
                            for: existing,
                            coverAlone: true,
                            layout: .single
                        )
                        let marks = progressStore.bookmarks(for: existing.id).count
                        if pct > 0 && pct < 100 {
                            return marks > 0
                                ? "\(AppCopy.resumeReading) · \(AppCopy.bookmark) \(marks)"
                                : AppCopy.resumeReading
                        }
                        if pct >= 100 {
                            return marks > 0
                                ? "\(AppCopy.openToRead) · \(AppCopy.bookmark) \(marks)"
                                : AppCopy.finishedReading
                        }
                        return marks > 0
                            ? "\(AppCopy.openToRead) · \(AppCopy.bookmark) \(marks)"
                            : AppCopy.openToRead
                    }
                    return supported ? AppCopy.getThisWork : AppCopy.unsupportedFile
                }()
            )
            .swipeActions(edge: .trailing, allowsFullSwipe: supported && !onShelf && !busy) {
                if supported, !onShelf, !busy {
                    Button(AppCopy.getThisWork) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        startFileImport(entry)
                    }
                        .tint(.accentColor)
                } else if let existing {
                    let pct = progressStore.progressPercent(
                        for: existing,
                        coverAlone: true,
                        layout: .single
                    )
                    let resume = pct > 0 && pct < 100
                    let marks = progressStore.bookmarks(for: existing.id).count
                    Button(
                        resume
                            ? (marks > 0
                                ? "\(AppCopy.continueReading) \(pct)% · \(AppCopy.bookmark) \(marks)"
                                : "\(AppCopy.continueReading) \(pct)%")
                            : (marks > 0
                                ? "\(AppCopy.openToRead) · \(AppCopy.bookmark) \(marks)"
                                : (pct >= 100 ? AppCopy.finishedReading : AppCopy.openToRead))
                    ) {
                        activity.toast = nil
                        activity.pendingOpenVolumeId = existing.id
                        UIImpactFeedbackGenerator(style: resume ? .medium : .light).impactOccurred()
                        dismiss()
                    }
                    .tint(resume ? .accentColor : .orange)
                }
            }
            .contextMenu {
                if let existing {
                    let pct = progressStore.progressPercent(
                        for: existing,
                        coverAlone: true,
                        layout: .single
                    )
                    let resume = pct > 0 && pct < 100
                    let marks = progressStore.bookmarks(for: existing.id).count
                    Button {
                        activity.toast = nil
                        activity.pendingOpenVolumeId = existing.id
                        UIImpactFeedbackGenerator(style: resume ? .medium : .light).impactOccurred()
                        dismiss()
                    } label: {
                        Label(
                            resume
                                ? (marks > 0
                                    ? "\(AppCopy.continueReading) \(pct)% · \(AppCopy.bookmark) \(marks)"
                                    : "\(AppCopy.continueReading) \(pct)%")
                                : (marks > 0
                                    ? "\(AppCopy.readNow) · \(AppCopy.bookmark) \(marks)"
                                    : AppCopy.readNow),
                            systemImage: resume ? "play.fill" : "book"
                        )
                    }
                    if marks > 0 {
                        Text("\(AppCopy.bookmark) \(marks) · \(AppCopy.bookmarkListFooter)")
                    }
                } else if supported, !busy {
                    Button(AppCopy.getThisWork) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        startFileImport(entry)
                    }
                }
            }
        }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        do {
            entries = try await RemoteGateway.list(source: source, path: currentPath)
            listError = nil
            markLastSuccess()
        } catch {
            listError = error.localizedDescription
            entries = []
        }
    }

    private func markLastSuccess() {
        guard var updated = RemoteSourceStore.shared.sources.first(where: { $0.id == source.id }) else { return }
        updated.lastSuccessAt = Date()
        RemoteSourceStore.shared.update(updated)
    }

    private func persistBrowsePath(_ path: String) {
        guard var updated = RemoteSourceStore.shared.sources.first(where: { $0.id == source.id }) else { return }
        guard updated.lastBrowsePath != path else { return }
        updated.lastBrowsePath = path
        RemoteSourceStore.shared.update(updated)
    }

    private func startNewWorksImport(_ entries: [RemoteEntry]) {
        let targets = entries.filter { !activity.isActive(sourceKey: $0.path) }
        guard !targets.isEmpty else { return }
        for (idx, entry) in targets.enumerated() {
            startFileImport(entry, announce: idx == 0)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func startFileImport(_ entry: RemoteEntry, announce: Bool = true) {
        guard !activity.isActive(sourceKey: entry.path) else { return }
        let displayTitle = cleanedTitle(for: entry)
        let job = activity.begin(
            title: displayTitle,
            status: AppCopy.downloadingItem,
            sourceKey: entry.path,
            announce: announce
        )
        let task = Task { @MainActor in
            do {
                if activity.isCancelled(job) { throw CancellationError() }
                let tmp = try ImportStaging.fileURL(named: entry.name)
                defer { ImportStaging.removeSession(containing: tmp) }
                try await RemoteGateway.download(source: source, entry: entry, to: tmp)
                if activity.isCancelled(job) { throw CancellationError() }
                activity.update(job, status: AppCopy.unpacking)
                if let existing = library.detectDuplicate(title: displayTitle) {
                    activity.succeed(job, message: AppCopy.alreadyHave, volumeId: existing.id)
                    justImported = existing
                    scheduleClearJustImported(existing.id)
                    return
                }
                let volume = try library.importURL(
                    tmp,
                    folderId: library.currentFolderId,
                    titleOverride: displayTitle
                )
                activity.succeed(job, volumeId: volume.id)
                justImported = volume
                scheduleClearJustImported(volume.id)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch is CancellationError {
                activity.finishCancelled(job)
            } catch {
                activity.fail(job, message: error.localizedDescription)
            }
        }
        activity.attachTask(job, task)
    }

    private func startFolderImport() {
        guard !folderBusy else { return }
        let rawFolder = currentPath.isEmpty ? source.name : (currentPath as NSString).lastPathComponent
        let title = UserFacingText.title(fromFileName: rawFolder)
        let path = currentPath
        let job = activity.begin(
            title: title,
            status: AppCopy.collecting,
            sourceKey: folderSourceKey
        )
        let task = Task { @MainActor in
            do {
                lastImportedVolumeId = nil
                let units = try await RemoteGateway.collectImportUnits(source: source, folderPath: path)
                if activity.isCancelled(job) { throw CancellationError() }
                guard !units.isEmpty else {
                    activity.succeed(job, message: AppCopy.emptyFolder, volumeId: nil)
                    return
                }
                let folder = library.folderForImport(named: title)
                var i = 0
                var importedNew = false
                for unit in units {
                    i += 1
                    if activity.isCancelled(job) { throw CancellationError() }
                    activity.update(
                        job,
                        status: "\(AppCopy.downloading) \(i)/\(units.count)…",
                        fraction: Double(i - 1) / Double(max(units.count, 1))
                    )
                    switch unit {
                    case .archive(let entry):
                        let t = UserFacingText.title(fromFileName: entry.name)
                        if let existing = library.detectDuplicate(title: t) {
                            lastImportedVolumeId = existing.id
                            continue
                        }
                        let tmp = try ImportStaging.fileURL(named: entry.name)
                        defer { ImportStaging.removeSession(containing: tmp) }
                        try await RemoteGateway.download(source: source, entry: entry, to: tmp)
                        let volume = try library.importURL(tmp, folderId: folder.id, titleOverride: t)
                        lastImportedVolumeId = volume.id
                        importedNew = true
                    case .imageFolder(_, let folderTitle, let files):
                        let t = UserFacingText.title(fromFileName: folderTitle)
                        if let existing = library.detectDuplicate(title: t) {
                            lastImportedVolumeId = existing.id
                            continue
                        }
                        let dir = try ImportStaging.fileURL(named: folderTitle).deletingLastPathComponent()
                            .appendingPathComponent(folderTitle, isDirectory: true)
                        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                        for f in files {
                            if activity.isCancelled(job) { throw CancellationError() }
                            let dest = dir.appendingPathComponent(f.name)
                            try await RemoteGateway.download(source: source, entry: f, to: dest)
                        }
                        let volume = try library.importURL(
                            dir,
                            folderId: folder.id,
                            titleOverride: t
                        )
                        lastImportedVolumeId = volume.id
                        importedNew = true
                        try? FileManager.default.removeItem(at: dir)
                    }
                }
                activity.update(job, status: AppCopy.unpacking, fraction: 1)
                activity.succeed(
                    job,
                    message: importedNew ? nil : AppCopy.alreadyHave,
                    volumeId: lastImportedVolumeId
                )
                if let vid = lastImportedVolumeId,
                   let volume = library.volumes.first(where: { $0.id == vid }) {
                    justImported = volume
                    scheduleClearJustImported(vid)
                }
            } catch is CancellationError {
                activity.finishCancelled(job)
            } catch {
                activity.fail(job, message: error.localizedDescription)
            }
        }
        activity.attachTask(job, task)
    }

    private func scheduleClearJustImported(_ id: UUID) {
        Task { @MainActor in
            // 続き／しおりがある作品は読むCTAを少し長く残す
            let linger: Bool = {
                guard let volume = justImported, volume.id == id else { return false }
                let pct = progressStore.progressPercent(
                    for: volume,
                    coverAlone: true,
                    layout: .single
                )
                if pct > 0 && pct < 100 { return true }
                return !progressStore.bookmarks(for: volume.id).isEmpty
            }()
            try? await Task.sleep(nanoseconds: linger ? 12_000_000_000 : 8_000_000_000)
            if justImported?.id == id { justImported = nil }
        }
    }
}
