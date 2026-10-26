import SwiftUI
import UIKit

struct ContentView: View {
    @ObservedObject var library: LibraryStore
    @State private var reading: MangaVolume?
    @State private var readingAutoResume = false
    @ObservedObject private var activity = TransferActivityCenter.shared

    var body: some View {
        NavigationStack {
            LibraryView(library: library) { volume, autoResume in
                readingAutoResume = autoResume
                reading = volume
            }
        }
        .overlay(alignment: .top) { ActivityOverlayView() }
        .fullScreenCover(item: $reading) { volume in
            ReaderView(
                library: library,
                volume: library.volumes.first(where: { $0.id == volume.id }) ?? volume,
                autoResume: readingAutoResume
            )
        }
        .onOpenURL { url in
            openExternal(url)
        }
        .onChange(of: activity.pendingOpenVolumeId) { _, id in
            guard let id, let volume = library.volumes.first(where: { $0.id == id }) else { return }
            activity.pendingOpenVolumeId = nil
            activity.toast = nil
            let pct = ProgressStore.shared.progressPercent(
                for: volume, coverAlone: true, layout: .single
            )
            // 続きがあるときだけ autoResume（未読・読了は表紙から）
            readingAutoResume = pct > 0 && pct < 100
            // haptic は Transfer／Remote／チップ側。ここでは二重に鳴らさない
            // 読書中に Transfer／リモートから別作品（または同作品）を開く
            if reading != nil {
                reading = nil
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    reading = volume
                }
            } else {
                reading = volume
            }
        }
    }

    private func openExternal(_ url: URL) {
        TransferActivityCenter.requestNotificationPermissionOnce()
        let displayTitle = UserFacingText.title(fromFileName: url.lastPathComponent)
        let job = activity.begin(title: displayTitle)
        let task = Task { @MainActor in
            do {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let staged = try ImportStaging.fileURL(named: url.lastPathComponent)
                defer { ImportStaging.removeSession(containing: staged) }
                try? FileManager.default.removeItem(at: staged)
                try FileManager.default.copyItem(at: url, to: staged)
                if let existing = library.detectDuplicate(title: displayTitle) {
                    activity.succeed(job, message: AppCopy.alreadyHave, volumeId: existing.id)
                    let pct = ProgressStore.shared.progressPercent(
                        for: existing, coverAlone: true, layout: .single
                    )
                    let resume = pct > 0 && pct < 100
                    readingAutoResume = resume
                    UIImpactFeedbackGenerator(style: resume ? .medium : .light).impactOccurred()
                    reading = existing
                    return
                }
                let volume = try library.importURL(
                    staged,
                    folderId: library.currentFolderId,
                    titleOverride: displayTitle
                )
                activity.succeed(job, volumeId: volume.id)
                readingAutoResume = false
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                reading = volume
            } catch {
                activity.fail(job, message: error.localizedDescription)
            }
        }
        activity.attachTask(job, task)
    }
}
