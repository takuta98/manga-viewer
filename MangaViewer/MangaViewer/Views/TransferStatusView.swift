import SwiftUI
import UIKit

struct TransferStatusView: View {
    @ObservedObject private var activity = TransferActivityCenter.shared
    @ObservedObject private var progressStore = ProgressStore.shared
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    private var active: [TransferActivityCenter.Job] {
        activity.jobs.filter { !$0.isFinished }
    }

    private var readable: [TransferActivityCenter.Job] {
        let _ = progressStore.revision
        let jobs = activity.jobs.filter { job in
            guard job.isFinished, !job.isFailed, !job.isCancelled, let vid = job.volumeId else { return false }
            return library.volumes.contains { $0.id == vid }
        }
        // 続きを読む → 未読 → 読了の順（同ランクは進み％降順→しおり件数降順→タイトル）
        return jobs.sorted { a, b in
            let ra = readableRank(a)
            let rb = readableRank(b)
            if ra != rb { return ra < rb }
            let pa = readablePercent(a)
            let pb = readablePercent(b)
            if pa != pb { return pa > pb }
            let ma = readableMarks(a)
            let mb = readableMarks(b)
            if ma != mb { return ma > mb }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    private func readableRank(_ job: TransferActivityCenter.Job) -> Int {
        let pct = readablePercent(job)
        if pct > 0 && pct < 100 { return 0 }
        if pct == 0 { return 1 }
        return 2
    }

    private func readablePercent(_ job: TransferActivityCenter.Job) -> Int {
        guard let vid = job.volumeId,
              let volume = library.volumes.first(where: { $0.id == vid }) else { return 0 }
        return progressStore.progressPercent(for: volume, coverAlone: true, layout: .single)
    }

    private func readableMarks(_ job: TransferActivityCenter.Job) -> Int {
        guard let vid = job.volumeId else { return 0 }
        return progressStore.bookmarks(for: vid).count
    }

    private var readableBookmarkCount: Int {
        let _ = progressStore.revision
        return readable.reduce(0) { sum, job in
            guard let vid = job.volumeId else { return sum }
            return sum + progressStore.bookmarks(for: vid).count
        }
    }

    private var otherFinished: [TransferActivityCenter.Job] {
        activity.jobs.filter { job in
            guard job.isFinished else { return false }
            if job.isFailed || job.isCancelled { return true }
            guard let vid = job.volumeId else { return true }
            // 本棚から消えた完了ジョブは「完了」側へ
            return !library.volumes.contains { $0.id == vid }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if activity.jobs.isEmpty {
                    ContentUnavailableView {
                        Label(AppCopy.downloadEmptyTitle, systemImage: "arrow.down.circle")
                    } description: {
                        Text("\(AppCopy.downloadEmptyBody)\n\(AppCopy.getWorksStayHint)")
                    } actions: {
                        Button(AppCopy.getWorks) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel(AppCopy.getWorks)
                        .accessibilityHint(AppCopy.getWorksStayHint)
                        Button(AppCopy.close) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint(AppCopy.close)
                    }
                } else {
                    List {
                        if !active.isEmpty {
                            Section {
                                ForEach(active) { jobRow($0) }
                            } header: {
                                Text("\(AppCopy.downloadActive)（\(active.count)）")
                                    .monospacedDigit()
                                    .accessibilityLabel(AppCopy.downloadActive)
                                    .accessibilityValue("\(active.count)")
                                    .accessibilityHint(
                                        readable.isEmpty
                                            ? AppCopy.getWorksStayHint
                                            : "\(AppCopy.readyToRead) \(readable.count)"
                                    )
                            } footer: {
                                Text(
                                    {
                                        if readable.isEmpty { return AppCopy.getWorksStayHint }
                                        var parts = [
                                            AppCopy.getWorksStayHint,
                                            "\(AppCopy.readyToRead) \(readable.count)",
                                        ]
                                        let resumeN = readable.filter { readableRank($0) == 0 }.count
                                        if resumeN > 0 {
                                            parts.append("\(AppCopy.continueReading) \(resumeN)")
                                        }
                                        let marksN = readableBookmarkCount
                                        if marksN > 0 {
                                            parts.append("\(AppCopy.bookmark) \(marksN)")
                                        }
                                        return parts.joined(separator: " · ")
                                    }()
                                )
                            }
                        }
                        if !readable.isEmpty {
                            Section {
                                ForEach(readable) { jobRow($0) }
                            } header: {
                                let resumeN = readable.filter { readableRank($0) == 0 }.count
                                let marksN = readableBookmarkCount
                                Text(
                                    {
                                        var parts = ["\(AppCopy.readyToRead)（\(readable.count)）"]
                                        if resumeN > 0 {
                                            parts.append("\(AppCopy.continueReading) \(resumeN)")
                                        }
                                        if marksN > 0 {
                                            parts.append("\(AppCopy.bookmark) \(marksN)")
                                        }
                                        return parts.joined(separator: " · ")
                                    }()
                                )
                                .monospacedDigit()
                                .accessibilityLabel(AppCopy.readyToRead)
                                .accessibilityValue(
                                    {
                                        var parts = ["\(readable.count)"]
                                        if resumeN > 0 {
                                            parts.append("\(AppCopy.continueReading) \(resumeN)")
                                        }
                                        if marksN > 0 {
                                            parts.append("\(AppCopy.bookmark) \(marksN)")
                                        }
                                        return parts.joined(separator: "、")
                                    }()
                                )
                                .accessibilityHint(AppCopy.tapToReadHint)
                            } footer: {
                                if let pick = readable.first, let vid = pick.volumeId {
                                    let pct = readablePercent(pick)
                                    let resume = pct > 0 && pct < 100
                                    let marks = progressStore.bookmarks(for: vid).count
                                    Button {
                                        open(vid)
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
                                            var parts = [pick.title]
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
                                                ? "\(AppCopy.tapToReadHint) · \(AppCopy.bookmark) \(marks)"
                                                : AppCopy.tapToReadHint)
                                    )
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                } else {
                                    Text(AppCopy.tapToReadHint)
                                }
                            }
                        }
                        if !otherFinished.isEmpty {
                            Section {
                                ForEach(otherFinished) { jobRow($0) }
                            } header: {
                                let failedN = otherFinished.filter(\.isFailed).count
                                let cancelledN = otherFinished.filter(\.isCancelled).count
                                Text(
                                    {
                                        var parts = ["\(AppCopy.done)（\(otherFinished.count)）"]
                                        if failedN > 0 {
                                            parts.append("\(AppCopy.downloadFailed) \(failedN)")
                                        }
                                        if cancelledN > 0 {
                                            parts.append("\(AppCopy.cancelled) \(cancelledN)")
                                        }
                                        return parts.joined(separator: " · ")
                                    }()
                                )
                                .monospacedDigit()
                                .accessibilityLabel(AppCopy.done)
                                .accessibilityValue(
                                    {
                                        var parts = ["\(otherFinished.count)"]
                                        if failedN > 0 {
                                            parts.append("\(AppCopy.downloadFailed) \(failedN)")
                                        }
                                        if cancelledN > 0 {
                                            parts.append("\(AppCopy.cancelled) \(cancelledN)")
                                        }
                                        return parts.joined(separator: "、")
                                    }()
                                )
                            } footer: {
                                VStack(alignment: .leading, spacing: 6) {
                                    if readable.isEmpty && active.isEmpty {
                                        Text(AppCopy.getWorksStayHint)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Button(AppCopy.clearFinished) {
                                        activity.toast = nil
                                        activity.clearFinished()
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }
                                    .font(.footnote.weight(.semibold))
                                    .accessibilityLabel(AppCopy.clearFinished)
                                    .accessibilityValue("\(AppCopy.done) \(otherFinished.count)")
                                    .accessibilityHint(AppCopy.downloads)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(
                {
                    if !readable.isEmpty {
                        let resumeN = readable.filter { readableRank($0) == 0 }.count
                        if resumeN > 0 {
                            return "\(AppCopy.downloads) · \(AppCopy.continueReading) \(resumeN)"
                        }
                        return "\(AppCopy.downloads) · \(AppCopy.readyToRead) \(readable.count)"
                    }
                    if !active.isEmpty {
                        return "\(AppCopy.downloads) · \(AppCopy.downloadActive) \(active.count)"
                    }
                    return AppCopy.downloads
                }()
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.close) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    }
                    .accessibilityLabel(AppCopy.close)
                    .accessibilityValue(
                        {
                            var parts: [String] = []
                            if !active.isEmpty {
                                parts.append("\(AppCopy.downloadActive) \(active.count)")
                            }
                            if !readable.isEmpty {
                                parts.append("\(AppCopy.readyToRead) \(readable.count)")
                            }
                            if readableBookmarkCount > 0 {
                                parts.append("\(AppCopy.bookmark) \(readableBookmarkCount)")
                            }
                            return parts.isEmpty ? AppCopy.downloads : parts.joined(separator: "、")
                        }()
                    )
                    .accessibilityHint(AppCopy.libraryTitle)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let first = readable.first, let vid = first.volumeId {
                        let rank = readableRank(first)
                        let vol = library.volumes.first(where: { $0.id == vid })
                        let pct = vol.map {
                            progressStore.progressPercent(for: $0, coverAlone: true, layout: .single)
                        } ?? 0
                        let marks = progressStore.bookmarks(for: vid).count
                        let label = rank == 0
                            ? (pct > 0
                                ? (marks > 0
                                    ? "\(AppCopy.continueReading) \(pct)% · \(AppCopy.bookmark) \(marks)"
                                    : "\(AppCopy.continueReading) \(pct)%")
                                : AppCopy.continueReading)
                            : (readable.count == 1
                                ? (marks > 0
                                    ? "\(AppCopy.readNow) · \(AppCopy.bookmark) \(marks)"
                                    : AppCopy.readNow)
                                : "\(AppCopy.readNow) · \(readable.count)")
                        Button {
                            open(vid)
                        } label: {
                            Label(
                                label,
                                systemImage: rank == 0 ? "play.fill" : "book"
                            )
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .labelStyle(.titleAndIcon)
                        }
                        .accessibilityLabel(rank == 0 ? AppCopy.continueReading : AppCopy.readNow)
                        .accessibilityValue(
                            {
                                var parts: [String] = [first.title]
                                if rank == 0 { parts.append("\(pct)%") }
                                else { parts.append("\(readable.count)") }
                                if marks > 0 { parts.append("\(AppCopy.bookmark) \(marks)") }
                                return parts.joined(separator: "、")
                            }()
                        )
                        .accessibilityHint(
                            rank == 0
                                ? (marks > 0
                                    ? "\(AppCopy.resumeReading) · \(AppCopy.bookmark) \(marks)"
                                    : AppCopy.resumeReading)
                                : (marks > 0
                                    ? "\(AppCopy.tapToReadHint) · \(AppCopy.bookmark) \(marks)"
                                    : AppCopy.tapToReadHint)
                        )
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if !active.isEmpty {
                            Button(
                                "\(AppCopy.cancelAllDownloads)（\(active.count)）",
                                role: .destructive
                            ) {
                                activity.cancelAllActive()
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            }
                        }
                        if !readable.isEmpty || !otherFinished.isEmpty {
                            Button(
                                {
                                    var parts = [AppCopy.clearFinished]
                                    if !readable.isEmpty {
                                        parts.append("\(AppCopy.readyToRead) \(readable.count)")
                                    }
                                    if !otherFinished.isEmpty {
                                        parts.append("\(AppCopy.done) \(otherFinished.count)")
                                    }
                                    return parts.joined(separator: " · ")
                                }()
                            ) {
                                activity.toast = nil
                                activity.clearFinished()
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(AppCopy.more)
                    .accessibilityValue(
                        {
                            var parts: [String] = []
                            if !active.isEmpty {
                                parts.append("\(AppCopy.downloadActive) \(active.count)")
                            }
                            if !readable.isEmpty {
                                parts.append("\(AppCopy.readyToRead) \(readable.count)")
                            }
                            if readableBookmarkCount > 0 {
                                parts.append("\(AppCopy.bookmark) \(readableBookmarkCount)")
                            }
                            return parts.joined(separator: "、")
                        }()
                    )
                    .accessibilityHint(AppCopy.downloads)
                    .disabled(active.isEmpty && readable.isEmpty && otherFinished.isEmpty)
                }
            }
        }
    }

    private func jobRow(_ job: TransferActivityCenter.Job) -> some View {
        let _ = progressStore.revision
        let volume = job.volumeId.flatMap { vid in
            library.volumes.first(where: { $0.id == vid })
        }
        let cover = volume?.coverURL()
        let pct = volume.map {
            progressStore.progressPercent(for: $0, coverAlone: true, layout: .single)
        }
        return HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                if let cover {
                    CoverThumbView(imageURL: cover, cornerRadius: 4)
                        .frame(width: canOpen(job) ? 52 : 40)
                } else {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                        .aspectRatio(2 / 3, contentMode: .fit)
                        .frame(width: canOpen(job) ? 52 : 40)
                        .overlay {
                            Image(systemName: placeholderIcon(for: job))
                                .foregroundStyle(.secondary)
                        }
                }
                if canOpen(job) {
                    let marksOnCover = volume.map { progressStore.bookmarks(for: $0.id).count } ?? 0
                    if (pct ?? 0) > 0 || marksOnCover > 0 {
                        HStack(spacing: 2) {
                            if let pct, pct > 0 {
                                CoverProgressBadge(percent: pct, compact: true)
                            }
                            if marksOnCover > 0 {
                                CoverBookmarkBadge(count: marksOnCover, compact: true)
                            }
                        }
                        .padding(2)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(job.title)
                        .font(.headline)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if !job.isFinished {
                        Button(AppCopy.cancelDownload) {
                            activity.cancel(job.id)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        .font(.caption.weight(.semibold))
                        .accessibilityHint(job.title)
                    } else if canOpen(job), let vid = job.volumeId {
                        let resume = (pct ?? 0) > 0 && (pct ?? 0) < 100
                        let marksBtn = volume.map { progressStore.bookmarks(for: $0.id).count } ?? 0
                        Button {
                            open(vid)
                        } label: {
                            Label(
                                resume
                                    ? (marksBtn > 0
                                        ? "\(AppCopy.continueReading) \(pct ?? 0)% · \(AppCopy.bookmark) \(marksBtn)"
                                        : "\(AppCopy.continueReading) \(pct ?? 0)%")
                                    : (marksBtn > 0
                                        ? "\(AppCopy.readNow) · \(AppCopy.bookmark) \(marksBtn)"
                                        : AppCopy.readNow),
                                systemImage: resume ? "play.fill" : "book"
                            )
                            .monospacedDigit()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityLabel(resume ? AppCopy.continueReading : AppCopy.readNow)
                        .accessibilityHint(resume ? AppCopy.resumeReading : AppCopy.openToRead)
                        .accessibilityValue(
                            {
                                var parts = [job.title]
                                if resume { parts.append("\(pct ?? 0)%") }
                                if marksBtn > 0 { parts.append("\(AppCopy.bookmark) \(marksBtn)") }
                                return parts.joined(separator: "、")
                            }()
                        )
                    }
                }
                Text(job.status)
                    .font(.subheadline)
                    .foregroundStyle(job.isFailed ? .red : (job.isCancelled ? .orange : .secondary))
                if canOpen(job), let pct {
                    let marks = volume.map { progressStore.bookmarks(for: $0.id).count } ?? 0
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
                    } else {
                        Text(
                            marks > 0
                                ? "\(pct >= 100 ? AppCopy.finishedReading : AppCopy.unread) · \(AppCopy.bookmark) \(marks)"
                                : (pct >= 100 ? AppCopy.finishedReading : AppCopy.unread)
                        )
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    if marks > 0 {
                        Label {
                            Text("\(AppCopy.bookmark) \(marks) · \(AppCopy.bookmarkListFooter)")
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: "bookmark.fill")
                                .foregroundStyle(.orange)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                    }
                } else if let f = job.fraction {
                    ProgressView(value: f)
                        .tint(.accentColor)
                    Text("\(Int((f * 100).rounded()))%")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else if !job.isFinished {
                    ProgressView()
                }
                if canOpen(job) {
                    let marksHint = volume.map { progressStore.bookmarks(for: $0.id).count } ?? 0
                    let resumeHint = (pct ?? 0) > 0 && (pct ?? 0) < 100
                    Text(
                        {
                            var parts = [AppCopy.tapToReadHint]
                            if resumeHint { parts.insert(AppCopy.continueReading, at: 0) }
                            if marksHint > 0 { parts.append("\(AppCopy.bookmark) \(marksHint)") }
                            return parts.joined(separator: " · ")
                        }()
                    )
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel({
            var parts = [job.title]
            if canOpen(job) {
                parts.append(AppCopy.readyToRead)
                if let pct {
                    if pct > 0 && pct < 100 { parts.append("\(pct)%") }
                    else if pct >= 100 { parts.append(AppCopy.finishedReading) }
                    else { parts.append(AppCopy.unread) }
                }
                let marks = volume.map { progressStore.bookmarks(for: $0.id).count } ?? 0
                if marks > 0 { parts.append("\(AppCopy.bookmark) \(marks)") }
            }
            parts.append(job.status)
            return parts.joined(separator: "、")
        }())
        .accessibilityHint(
            {
                guard canOpen(job) else {
                    return job.isFinished ? "" : AppCopy.cancelDownload
                }
                let marks = volume.map { progressStore.bookmarks(for: $0.id).count } ?? 0
                let resume = (pct ?? 0) > 0 && (pct ?? 0) < 100
                if resume {
                    return marks > 0
                        ? "\(AppCopy.resumeReading) · \(AppCopy.bookmark) \(marks)"
                        : AppCopy.resumeReading
                }
                return marks > 0
                    ? "\(AppCopy.tapToReadHint) · \(AppCopy.bookmark) \(marks)"
                    : AppCopy.tapToReadHint
            }()
        )
        .accessibilityAddTraits(canOpen(job) ? .isButton : [])
        .onTapGesture {
            guard canOpen(job), let vid = job.volumeId else { return }
            open(vid)
        }
        .contextMenu {
            if canOpen(job), let vid = job.volumeId {
                let resume = (pct ?? 0) > 0 && (pct ?? 0) < 100
                let marksMenu = volume.map { progressStore.bookmarks(for: $0.id).count } ?? 0
                Button {
                    open(vid)
                } label: {
                    Label(
                        resume
                            ? (marksMenu > 0
                                ? "\(AppCopy.continueReading) \(pct ?? 0)% · \(AppCopy.bookmark) \(marksMenu)"
                                : "\(AppCopy.continueReading) \(pct ?? 0)%")
                            : (marksMenu > 0
                                ? "\(AppCopy.readNow) · \(AppCopy.bookmark) \(marksMenu)"
                                : AppCopy.readNow),
                        systemImage: resume ? "play.fill" : "book"
                    )
                }
            }
            if !job.isFinished {
                Button(AppCopy.cancelDownload, role: .destructive) {
                    activity.cancel(job.id)
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: canOpen(job)) {
            if canOpen(job), let vid = job.volumeId {
                let resume = (pct ?? 0) > 0 && (pct ?? 0) < 100
                let marksSwipe = volume.map { progressStore.bookmarks(for: $0.id).count } ?? 0
                Button { open(vid) } label: {
                    Label(
                        resume
                            ? (marksSwipe > 0
                                ? "\(AppCopy.continueReading) \(pct ?? 0)% · \(AppCopy.bookmark) \(marksSwipe)"
                                : "\(AppCopy.continueReading) \(pct ?? 0)%")
                            : (marksSwipe > 0
                                ? "\(AppCopy.readNow) · \(AppCopy.bookmark) \(marksSwipe)"
                                : AppCopy.readNow),
                        systemImage: resume ? "play.fill" : "book"
                    )
                }
                .tint(.accentColor)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: !job.isFinished) {
            if canOpen(job), let vid = job.volumeId {
                let resume = (pct ?? 0) > 0 && (pct ?? 0) < 100
                let marksSwipe = volume.map { progressStore.bookmarks(for: $0.id).count } ?? 0
                Button { open(vid) } label: {
                    Label(
                        resume
                            ? (marksSwipe > 0
                                ? "\(AppCopy.continueReading) \(pct ?? 0)% · \(AppCopy.bookmark) \(marksSwipe)"
                                : "\(AppCopy.continueReading) \(pct ?? 0)%")
                            : (marksSwipe > 0
                                ? "\(AppCopy.readNow) · \(AppCopy.bookmark) \(marksSwipe)"
                                : AppCopy.readNow),
                        systemImage: resume ? "play.fill" : "book"
                    )
                }
                .tint(.accentColor)
            }
            if !job.isFinished {
                Button {
                    activity.cancel(job.id)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label(AppCopy.cancelDownload, systemImage: "xmark")
                }
                .tint(.orange)
            }
        }
    }

    private func canOpen(_ job: TransferActivityCenter.Job) -> Bool {
        guard job.isFinished, !job.isFailed, !job.isCancelled, let vid = job.volumeId else { return false }
        return library.volumes.contains { $0.id == vid }
    }

    private func open(_ volumeId: UUID) {
        guard library.volumes.contains(where: { $0.id == volumeId }) else { return }
        progressStore.notifyLibrary()
        activity.toast = nil
        let pct = library.volumes.first(where: { $0.id == volumeId }).map {
            progressStore.progressPercent(for: $0, coverAlone: true, layout: .single)
        } ?? 0
        let resume = pct > 0 && pct < 100
        activity.pendingOpenVolumeId = volumeId
        UIImpactFeedbackGenerator(style: resume ? .medium : .light).impactOccurred()
        dismiss()
    }

    private func placeholderIcon(for job: TransferActivityCenter.Job) -> String {
        if job.isFailed { return "exclamationmark.triangle" }
        if job.isCancelled { return "xmark.circle" }
        if canOpen(job) { return "book.closed" }
        return "arrow.down.circle"
    }
}
