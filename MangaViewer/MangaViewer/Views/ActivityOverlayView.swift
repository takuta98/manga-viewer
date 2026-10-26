import SwiftUI
import UIKit

struct ActivityOverlayView: View {
    @ObservedObject private var activity = TransferActivityCenter.shared

    var body: some View {
        VStack {
            if let toast = activity.toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(toast)
            }
            Spacer(minLength: 0)
        }
        .animation(.snappy, value: activity.toast)
        .allowsHitTesting(false)
    }
}

struct DownloadStatusChip: View {
    @ObservedObject private var activity = TransferActivityCenter.shared
    @ObservedObject private var progressStore = ProgressStore.shared
    @EnvironmentObject private var library: LibraryStore
    var onTap: () -> Void

    private var readyJobs: [TransferActivityCenter.Job] {
        let _ = progressStore.revision
        let jobs = activity.jobs.filter { job in
            guard job.isFinished, !job.isFailed, !job.isCancelled, let vid = job.volumeId else { return false }
            return library.volumes.contains { $0.id == vid }
        }
        // 続き → 未読 → 読了（同ランクは進み％降順→しおり件数降順→タイトル／TransferStatus と同じ）
        return jobs.sorted { a, b in
            let ra = readyRank(a)
            let rb = readyRank(b)
            if ra != rb { return ra < rb }
            let pa = readyPercent(a)
            let pb = readyPercent(b)
            if pa != pb { return pa > pb }
            let ma = readyMarks(a)
            let mb = readyMarks(b)
            if ma != mb { return ma > mb }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    private var readyCount: Int { readyJobs.count }

    private func readyRank(_ job: TransferActivityCenter.Job) -> Int {
        let pct = readyPercent(job)
        if pct > 0 && pct < 100 { return 0 }
        if pct == 0 { return 1 }
        return 2
    }

    private func readyPercent(_ job: TransferActivityCenter.Job) -> Int {
        guard let vid = job.volumeId,
              let volume = library.volumes.first(where: { $0.id == vid }) else { return 0 }
        return progressStore.progressPercent(for: volume, coverAlone: true, layout: .single)
    }

    private func readyMarks(_ job: TransferActivityCenter.Job) -> Int {
        guard let vid = job.volumeId else { return 0 }
        return progressStore.bookmarks(for: vid).count
    }

    private func resumeLabel(for job: TransferActivityCenter.Job) -> String {
        readyRank(job) == 0 ? AppCopy.continueReading : AppCopy.readNow
    }

    var body: some View {
        if let job = activity.activeJobs.first {
            activeChip(job)
        } else if let ready = readyJobs.first {
            readyChip(ready)
        }
    }

    private func activeChip(_ job: TransferActivityCenter.Job) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(AppCopy.downloadActiveCount(activity.activeCount))
                            .font(.footnote.weight(.semibold))
                        Spacer(minLength: 0)
                        if readyCount > 0 {
                            let resumeN = readyJobs.filter { readyRank($0) == 0 }.count
                            let marksN = readyJobs.reduce(0) { sum, j in
                                guard let vid = j.volumeId else { return sum }
                                return sum + progressStore.bookmarks(for: vid).count
                            }
                            Text(
                                {
                                    var parts = ["\(AppCopy.readyToRead) \(readyCount)"]
                                    if resumeN > 0 {
                                        parts.append("\(AppCopy.continueReading) \(resumeN)")
                                    }
                                    if marksN > 0 {
                                        parts.append("\(AppCopy.bookmark) \(marksN)")
                                    }
                                    return parts.joined(separator: " · ")
                                }()
                            )
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.tint)
                        } else {
                            Text(AppCopy.downloads)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tint)
                        }
                    }
                    Text(job.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(job.status)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    if let f = job.fraction {
                        ProgressView(value: f)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppCopy.downloadActiveCount(activity.activeCount))
            .accessibilityValue(
                {
                    var parts = [job.title, job.status]
                    if let f = job.fraction {
                        parts.append("\(Int((f * 100).rounded()))%")
                    }
                    return parts.joined(separator: "、")
                }()
            )
            .accessibilityHint(
                {
                    var parts = [job.title, AppCopy.downloads]
                    if readyCount > 0 {
                        parts.insert("\(AppCopy.readyToRead) \(readyCount)", at: 1)
                        let resumeN = readyJobs.filter { readyRank($0) == 0 }.count
                        if resumeN > 0 {
                            parts.insert("\(AppCopy.continueReading) \(resumeN)", at: 2)
                        }
                        let marksN = readyJobs.reduce(0) { sum, j in
                            guard let vid = j.volumeId else { return sum }
                            return sum + progressStore.bookmarks(for: vid).count
                        }
                        if marksN > 0 {
                            parts.append("\(AppCopy.bookmark) \(marksN)")
                        }
                    }
                    return parts.joined(separator: "。")
                }()
            )

            HStack {
                Spacer(minLength: 0)
                Button(AppCopy.cancelDownload) {
                    activity.cancel(job.id)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                .font(.caption.weight(.semibold))
                .accessibilityLabel(AppCopy.cancelDownload)
                .accessibilityValue(job.title)
                .accessibilityHint(
                    {
                        if let f = job.fraction {
                            return "\(Int((f * 100).rounded()))% · \(AppCopy.downloadActive)"
                        }
                        return AppCopy.downloadActive
                    }()
                )
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func readyChip(_ job: TransferActivityCenter.Job) -> some View {
        let resume = readyCount == 1 && readyRank(job) == 0
        let volume = job.volumeId.flatMap { vid in
            library.volumes.first(where: { $0.id == vid })
        }
        let pct: Int = {
            guard let volume else { return 0 }
            return progressStore.progressPercent(for: volume, coverAlone: true, layout: .single)
        }()
        let marks = volume.map { progressStore.bookmarks(for: $0.id).count } ?? 0
        let cta: String = {
            if readyCount != 1 { return AppCopy.downloads }
            if resume {
                return marks > 0
                    ? "\(AppCopy.continueReading) \(pct)% · \(AppCopy.bookmark) \(marks)"
                    : (pct > 0 ? "\(AppCopy.continueReading) \(pct)%" : AppCopy.continueReading)
            }
            if marks > 0 { return "\(AppCopy.readNow) · \(AppCopy.bookmark) \(marks)" }
            return AppCopy.readNow
        }()
        let header: String = {
            if resume {
                return marks > 0
                    ? "\(AppCopy.readyToRead)（\(readyCount)）· \(AppCopy.continueReading) · \(AppCopy.bookmark) \(marks)"
                    : "\(AppCopy.readyToRead)（\(readyCount)）· \(AppCopy.continueReading)"
            }
            if readyRank(job) == 0 && readyCount > 1 {
                let marksN = readyJobs.reduce(0) { sum, j in
                    guard let vid = j.volumeId else { return sum }
                    return sum + progressStore.bookmarks(for: vid).count
                }
                return marksN > 0
                    ? "\(AppCopy.readyToRead)（\(readyCount)）· \(AppCopy.continueReading) · \(AppCopy.bookmark) \(marksN)"
                    : "\(AppCopy.readyToRead)（\(readyCount)）· \(AppCopy.continueReading)"
            }
            if marks > 0 && readyCount == 1 {
                return "\(AppCopy.readyToRead)（\(readyCount)）· \(AppCopy.bookmark) \(marks)"
            }
            return "\(AppCopy.readyToRead)（\(readyCount)）"
        }()
        return HStack(spacing: 8) {
            Button {
                if readyCount == 1, let vid = job.volumeId {
                    activity.toast = nil
                    activity.pendingOpenVolumeId = vid
                    UIImpactFeedbackGenerator(style: resume ? .medium : .light).impactOccurred()
                } else {
                    onTap()
                }
            } label: {
                HStack(spacing: 10) {
                    if let volume {
                        ZStack(alignment: .bottomLeading) {
                            CoverThumbView(imageURL: volume.coverURL(), cornerRadius: 4)
                                .frame(width: 36)
                            if pct > 0 || marks > 0 {
                                HStack(spacing: 2) {
                                    if pct > 0 {
                                        CoverProgressBadge(percent: pct, compact: true)
                                    }
                                    if marks > 0 {
                                        CoverBookmarkBadge(count: marks, compact: true)
                                    }
                                }
                                .padding(1)
                            }
                        }
                    } else {
                        Image(systemName: resume ? "play.circle.fill" : "book.closed.fill")
                            .foregroundStyle(.tint)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(header)
                            .font(.footnote.weight(.semibold))
                        Text(job.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if resume, pct > 0 {
                            ProgressView(value: Double(pct), total: 100)
                                .tint(.accentColor)
                        }
                        if marks > 0 {
                            Label {
                                Text(
                                    readyCount == 1
                                        ? "\(AppCopy.bookmark) \(marks)"
                                        : "\(AppCopy.bookmark) \(marks) · \(AppCopy.readyToRead) \(readyCount)"
                                )
                                .monospacedDigit()
                            } icon: {
                                Image(systemName: "bookmark.fill")
                                    .foregroundStyle(.orange)
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(cta)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                        .monospacedDigit()
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(header)
            .accessibilityValue(
                {
                    var parts = [job.title]
                    if resume { parts.append("\(pct)%") }
                    if marks > 0 { parts.append("\(AppCopy.bookmark) \(marks)") }
                    return parts.joined(separator: "、")
                }()
            )
            .accessibilityHint(readyCount == 1 ? cta : AppCopy.tapToReadHint)

            if readyCount == 1, let vid = job.volumeId {
                Button {
                    activity.toast = nil
                    activity.pendingOpenVolumeId = vid
                    UIImpactFeedbackGenerator(style: resume ? .medium : .light).impactOccurred()
                } label: {
                    Label(cta, systemImage: resume ? "play.fill" : "book")
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(resume ? AppCopy.continueReading : AppCopy.readNow)
                .accessibilityValue(
                    {
                        var parts = [job.title]
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
            } else {
                Button(action: onTap) {
                    Image(systemName: "list.bullet")
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel(AppCopy.downloads)
                .accessibilityValue(
                    {
                        var parts = ["\(AppCopy.readyToRead) \(readyCount)"]
                        let resumeN = readyJobs.filter { readyRank($0) == 0 }.count
                        if resumeN > 0 {
                            parts.append("\(AppCopy.continueReading) \(resumeN)")
                        }
                        let marksN = readyJobs.reduce(0) { sum, j in
                            guard let vid = j.volumeId else { return sum }
                            return sum + progressStore.bookmarks(for: vid).count
                        }
                        if marksN > 0 {
                            parts.append("\(AppCopy.bookmark) \(marksN)")
                        }
                        return parts.joined(separator: " · ")
                    }()
                )
                .accessibilityHint(AppCopy.tapToReadHint)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
