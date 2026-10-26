import SwiftUI
import UIKit

struct VolumeInfoView: View {
    @ObservedObject var library: LibraryStore
    let volume: MangaVolume
    /// autoResume: true なら続きから／しおり位置へ直接
    var onRead: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var direction: ReadingDirection
    @State private var title: String

    init(library: LibraryStore, volume: MangaVolume, onRead: @escaping (Bool) -> Void) {
        self.library = library
        self.volume = volume
        self.onRead = onRead
        _direction = State(initialValue: volume.direction)
        _title = State(initialValue: volume.title)
    }

    @ObservedObject private var progressStore = ProgressStore.shared

    private var progress: Int {
        let _ = progressStore.revision
        return progressStore.progressPercent(for: volume, coverAlone: true, layout: .single)
    }

    private var bookmarks: [Int] {
        let _ = progressStore.revision
        return progressStore.bookmarks(for: volume.id).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        ZStack(alignment: .bottomLeading) {
                            CoverThumbView(imageURL: volume.coverURL(), cornerRadius: 6)
                                .frame(width: 72)
                            if progress > 0 || !bookmarks.isEmpty {
                                HStack(spacing: 4) {
                                    if progress > 0 {
                                        CoverProgressBadge(percent: progress)
                                    }
                                    if !bookmarks.isEmpty {
                                        CoverBookmarkBadge(count: bookmarks.count)
                                    }
                                }
                                .padding(4)
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            TextField(AppCopy.titleField, text: $title)
                                .font(.headline)
                            Text("\(volume.pageCount) \(AppCopy.pageCountSuffix)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if progress > 0 && progress < 100 {
                                ProgressView(value: Double(progress), total: 100)
                                Text(
                                    bookmarks.isEmpty
                                        ? "\(progress)% · \(AppCopy.continueReading)"
                                        : "\(progress)% · \(AppCopy.continueReading) · \(AppCopy.bookmark) \(bookmarks.count)"
                                )
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            } else if progress >= 100 {
                                Text(
                                    bookmarks.isEmpty
                                        ? AppCopy.finishedReading
                                        : "\(AppCopy.finishedReading) · \(AppCopy.bookmark) \(bookmarks.count)"
                                )
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(
                                    bookmarks.isEmpty
                                        ? AppCopy.unread
                                        : "\(AppCopy.unread) · \(AppCopy.bookmark) \(bookmarks.count)"
                                )
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section(AppCopy.readingDirection) {
                    Picker(AppCopy.readingDirection, selection: $direction) {
                        ForEach(ReadingDirection.allCases) { Text($0.label).tag($0) }
                    }
                }
                if bookmarks.isEmpty {
                    Section {
                        Text(AppCopy.bookmarkEmptyBody)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if progress > 0 && progress < 100 {
                            Text("\(AppCopy.hereNow) · \(progress)% · \(AppCopy.continueReading)")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.tint)
                            ProgressView(value: Double(progress), total: 100)
                                .tint(.accentColor)
                        } else if progress >= 100 {
                            Text(AppCopy.finishedReading)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(AppCopy.unread) · \(AppCopy.openToRead)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    } header: {
                        Text(
                            progress > 0
                                ? "\(AppCopy.bookmarkList) · \(progress)%"
                                : AppCopy.bookmarkList
                        )
                        .monospacedDigit()
                        .accessibilityLabel(AppCopy.bookmarkList)
                        .accessibilityValue(progress > 0 ? "\(progress)%" : "")
                    } footer: {
                        Text(
                            progress > 0 && progress < 100
                                ? "\(AppCopy.bookmarkEmpty) · \(AppCopy.continueReading) \(progress)% · \(AppCopy.bookmarkListFooter)"
                                : "\(AppCopy.bookmarkEmpty) · \(AppCopy.bookmarkListFooter)"
                        )
                    }
                } else {
                    let spread = progressStore.spreadIndex(for: volume.id)
                    let current = SpreadIndex.pageIndices(
                        spreadIndex: spread,
                        pageCount: volume.pageCount,
                        coverAlone: true,
                        layout: .single
                    ).0 ?? 0
                    let hereMarks = bookmarks.filter { $0 == current }
                    let otherMarks = bookmarks
                        .filter { $0 != current }
                        .sorted { abs($0 - current) < abs($1 - current) }
                    if !hereMarks.isEmpty {
                        Section {
                            ForEach(hereMarks, id: \.self) { page in
                                bookmarkInfoRow(page: page, current: current, here: true)
                            }
                        } header: {
                            let pagePct = Int(
                                (Double(current + 1) / Double(max(volume.pageCount, 1)) * 100)
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
                            .accessibilityValue("\(AppCopy.hereNow)、\(pagePct)%")
                        } footer: {
                            let pagePct = Int(
                                (Double(current + 1) / Double(max(volume.pageCount, 1)) * 100)
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
                                bookmarkInfoRow(page: page, current: current, here: false)
                            }
                        } header: {
                            if let nearest = otherMarks.first {
                                let pagePct = Int(
                                    (Double(nearest + 1) / Double(max(volume.pageCount, 1)) * 100)
                                        .rounded()
                                )
                                Text(
                                    hereMarks.isEmpty
                                        ? "\(AppCopy.bookmarkList)（\(otherMarks.count)）· \(pagePct)%"
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
                                        ? "\(AppCopy.bookmarkList)（\(otherMarks.count)）"
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
                                    "\(bookmarkSubtitle(page: nearest, current: current, here: false)) · \(pagePct)% · \(AppCopy.jumpToPage)"
                                )
                            } else {
                                Text("\(AppCopy.bookmarkListFooter) · \(AppCopy.jumpToPage)")
                            }
                        }
                    }
                }
                Section {
                    if progress > 0 && progress < 100 {
                        Button {
                            applyEdits()
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            dismiss()
                            onRead(true)
                        } label: {
                            Label(
                                bookmarks.isEmpty
                                    ? "\(AppCopy.continueReading) \(progress)%"
                                    : "\(AppCopy.continueReading) \(progress)% · \(AppCopy.bookmark) \(bookmarks.count)",
                                systemImage: "play.fill"
                            )
                            .monospacedDigit()
                            .foregroundStyle(.tint)
                        }
                        .accessibilityLabel(AppCopy.continueReading)
                        .accessibilityValue(
                            bookmarks.isEmpty
                                ? "\(progress)%"
                                : "\(progress)%、\(AppCopy.bookmark) \(bookmarks.count)"
                        )
                        .accessibilityHint(
                            bookmarks.isEmpty
                                ? AppCopy.resumeReading
                                : "\(AppCopy.resumeReading) · \(AppCopy.bookmark) \(bookmarks.count)"
                        )
                        Button {
                            progressStore.clearProgress(for: volume.id)
                            progressStore.notifyLibrary()
                            applyEdits()
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            dismiss()
                            onRead(false)
                        } label: {
                            Label(AppCopy.startOver, systemImage: "backward.end")
                        }
                    } else {
                        Button {
                            if progress >= 100 {
                                progressStore.clearProgress(for: volume.id)
                                progressStore.notifyLibrary()
                            }
                            applyEdits()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            dismiss()
                            onRead(false)
                        } label: {
                            Label(
                                {
                                    if progress >= 100 {
                                        return bookmarks.isEmpty
                                            ? AppCopy.startOver
                                            : "\(AppCopy.startOver) · \(AppCopy.bookmark) \(bookmarks.count)"
                                    }
                                    return bookmarks.isEmpty
                                        ? AppCopy.openToRead
                                        : "\(AppCopy.openToRead) · \(AppCopy.bookmark) \(bookmarks.count)"
                                }(),
                                systemImage: progress >= 100 ? "backward.end" : "book"
                            )
                            .monospacedDigit()
                        }
                        .accessibilityLabel(
                            progress >= 100 ? AppCopy.startOver : AppCopy.openToRead
                        )
                        .accessibilityValue(
                            bookmarks.isEmpty
                                ? ""
                                : "\(AppCopy.bookmark) \(bookmarks.count)"
                        )
                        .accessibilityHint(
                            progress >= 100 ? AppCopy.startOver : AppCopy.openToRead
                        )
                    }
                    if !bookmarks.isEmpty {
                        Text("\(AppCopy.bookmark) \(bookmarks.count) · \(AppCopy.bookmarkListFooter)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .navigationTitle(
                {
                    if progress > 0 && progress < 100 {
                        return bookmarks.isEmpty
                            ? "\(AppCopy.info) · \(progress)%"
                            : "\(AppCopy.info) · \(progress)% · \(AppCopy.bookmark) \(bookmarks.count)"
                    }
                    if !bookmarks.isEmpty {
                        return "\(AppCopy.info) · \(AppCopy.bookmark) \(bookmarks.count)"
                    }
                    return AppCopy.info
                }()
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.close) { dismiss() }
                        .accessibilityLabel(AppCopy.close)
                        .accessibilityValue(
                            {
                                var parts = [volume.title]
                                if progress > 0 && progress < 100 {
                                    parts.append("\(AppCopy.continueReading) \(progress)%")
                                } else if progress >= 100 {
                                    parts.append(AppCopy.finishedReading)
                                }
                                if !bookmarks.isEmpty {
                                    parts.append("\(AppCopy.bookmark) \(bookmarks.count)")
                                }
                                return parts.joined(separator: "、")
                            }()
                        )
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppCopy.save) {
                        applyEdits()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    }
                    .accessibilityLabel(AppCopy.save)
                    .accessibilityValue(volume.title)
                    .accessibilityHint(
                        bookmarks.isEmpty
                            ? AppCopy.info
                            : "\(AppCopy.bookmark) \(bookmarks.count) · \(AppCopy.bookmarkListFooter)"
                    )
                }
            }
        }
    }

    private func applyEdits() {
        if title != volume.title {
            library.rename(volume, title: title)
        }
        if direction != volume.direction {
            library.updateDirection(volume, direction: direction)
        }
    }

    @ViewBuilder
    private func bookmarkInfoRow(page: Int, current: Int, here: Bool) -> some View {
        Button {
            openAtPage(page)
        } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    CoverThumbView(
                        imageURL: volume.pageURL(at: page),
                        cornerRadius: 4
                    )
                    .frame(width: 40)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(page + 1) / \(volume.pageCount) \(AppCopy.pageCountSuffix)")
                        .font(.headline)
                        .monospacedDigit()
                    Text(bookmarkSubtitle(page: page, current: current, here: here))
                        .font(.caption2)
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
                Spacer()
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
        .accessibilityLabel("\(AppCopy.bookmark) \(page + 1) / \(volume.pageCount)")
        .accessibilityValue({
            let pagePct = Int(
                (Double(page + 1) / Double(max(volume.pageCount, 1)) * 100).rounded()
            )
            return here
                ? "\(AppCopy.hereNow)、\(pagePct)%"
                : "\(bookmarkSubtitle(page: page, current: current, here: false))、\(pagePct)%"
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
                progressStore.removeBookmark(pageIndex: page, for: volume.id)
                progressStore.notifyLibrary()
            }
            if !here {
                Button(AppCopy.jumpToPage) {
                    openAtPage(page)
                }
                .tint(.accentColor)
            }
        }
    }

    private func openAtPage(_ page: Int) {
        let spread = SpreadIndex.spreadIndex(forPage: page, coverAlone: true, layout: .single)
        let current = SpreadIndex.pageIndices(
            spreadIndex: progressStore.spreadIndex(for: volume.id),
            pageCount: volume.pageCount,
            coverAlone: true,
            layout: .single
        ).0 ?? 0
        let here = page == current
        progressStore.setSpreadIndex(spread, for: volume.id)
        progressStore.notifyLibrary()
        applyEdits()
        // しおりへジャンプして読む＝続きを読む相当
        UIImpactFeedbackGenerator(style: here ? .light : .medium).impactOccurred()
        dismiss()
        onRead(true)
    }

    private func bookmarkSubtitle(page: Int, current: Int, here: Bool) -> String {
        if here { return AppCopy.currentPageLabel }
        let delta = page - current
        if delta > 0 { return AppCopy.bookmarkPagesAhead(delta) }
        if delta < 0 { return AppCopy.bookmarkPagesBehind(-delta) }
        return AppCopy.jumpToPage
    }
}
