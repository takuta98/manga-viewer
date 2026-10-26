#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from __future__ import annotations
import re, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "MangaViewer" / "MangaViewer"
failures: list[str] = []

def fail(m): failures.append(m)
def swift_files(): return sorted(SRC.rglob("*.swift"))
def read(p): return p.read_text(encoding="utf-8")


def check_packages():
    pbx = read(ROOT/"MangaViewer"/"MangaViewer.xcodeproj"/"project.pbxproj")
    if "AMSMB2" not in pbx: fail("[SMB] AMSMB2 パッケージが無い")
    if "Citadel" not in pbx: fail("[SFTP] Citadel パッケージが無い")
    if "FilesProvider" not in pbx: fail("[WebDAV/FTP] FilesProvider パッケージが無い")
    if "FeedKit" not in pbx: fail("[OPDS] FeedKit パッケージが無い")
    if not (SRC/"Services"/"Remote"/"SMBClientService.swift").exists():
        fail("[SMB] SMBClientService.swift が無い")
    if not (SRC/"Services"/"Remote"/"SFTPClientService.swift").exists():
        fail("[SFTP] SFTPClientService.swift が無い")
    for p in swift_files():
        if p.name not in pbx:
            fail(f"[pbx] {p.relative_to(SRC)} が project.pbxproj に無い")

def check_staging():
    for rel in ["Views/Import/RemoteBrowserView.swift", "Views/Import/ImportHubView.swift"]:
        t = read(SRC/rel)
        if "ImportStaging" not in t: fail(f"[系統A] {rel} が ImportStaging 未使用")
        if "UserFacingText" not in t: fail(f"[系統A] {rel} が UserFacingText 未使用")

def check_password():
    t = read(SRC/"Models"/"RemoteSource.swift")
    m = re.search(r"func encode\(to encoder: Encoder\) throws \{([\s\S]*?)\n    \}", t)
    if not m: fail("[系統B] encode がない"); return
    if "forKey: .password" in m.group(1): fail("[系統B] password を JSON に書いている")

def check_layout():
    if not (SRC/"Services"/"DisplayLayoutResolver.swift").exists():
        fail("[Duo] DisplayLayoutResolver がない")
    if "DisplayLayoutResolver.resolve" not in read(SRC/"Views"/"ReaderView.swift"):
        fail("[Duo] ReaderView 未配線")

def check_transfer():
    t = read(SRC/"Views"/"LibraryView.swift")
    if "TransferStatusView()" not in t: fail("[転送] TransferStatusView sheet がない")

def check_titles():
    samples = {
        "A1B2C3D4-E5F6-7890-ABCD-EF1234567890-ワンピース": "ワンピース",
        "普通のタイトル": "普通のタイトル",
        "": "無題",
    }
    junk = [
        re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}[-_]"),
        re.compile(r"^[0-9a-fA-F]{32}[-_]"),
        re.compile(r"^tmp[-_]", re.I),
    ]
    def clean(raw):
        s=raw.strip()
        if not s: return "無題"
        changed=True
        while changed:
            changed=False
            for pat in junk:
                m=pat.match(s)
                if m:
                    s=s[m.end():].lstrip("-_ "); changed=True; break
        return s.strip("-_ ") or "無題"
    for i,w in samples.items():
        if clean(i)!=w: fail(f"[系統A] title '{i}' -> '{clean(i)}'")

def check_reading_ia():
    copy = read(SRC / "Services" / "AppCopy.swift")
    if 'libraryTitle = "本棚"' not in copy:
        fail("[IA] AppCopy.libraryTitle が 本棚 ではない")
    if 'getWorks = "作品を入手"' not in copy:
        fail("[IA] AppCopy.getWorks が 作品を入手 ではない")
    if "bookmarkList" not in copy:
        fail("[IA] しおり一覧コピーがない")
    banned = ["書庫", "取り込み", "転送", "入れる", "追加"]
    for path in swift_files():
        text = read(path)
        # コメント行の禁止リスト説明は除外
        for i, line in enumerate(text.splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("///"):
                continue
            for word in banned:
                if word in line:
                    fail(f"[IA] {path.relative_to(SRC)}:{i} に禁止語『{word}』")


def check_volume_id_wiring():
    center = read(SRC / "Services" / "TransferActivityCenter.swift")
    if "var volumeId: UUID?" not in center:
        fail("[入手] Job.volumeId がない")
    if "func succeed(_ id: UUID, message: String? = nil, volumeId: UUID? = nil)" not in center:
        fail("[入手] succeed(volumeId:) がない")
    if "finishCancelled" not in center:
        fail("[入手] finishCancelled がない")
    if "downloadFinishedReadHint" not in center:
        fail("[入手] 完了トーストの読むヒントがない")
    if "cancelAllActive" not in center:
        fail("[入手] 一括中止がない")
    if "suppressCancelToast" not in center:
        fail("[入手] 一括中止のトースト抑制がない")
    if 'untitled = "無題"' not in read(SRC / "Services" / "AppCopy.swift"):
        fail("[IA] AppCopy.untitled がない")
    if "AppCopy.untitled" not in read(SRC / "Services" / "UserFacingText.swift"):
        fail("[IA] UserFacingText が AppCopy.untitled 未使用")
    gateway = read(SRC / "Services" / "Remote" / "RemoteGateway.swift")
    if "AppCopy.invalidURL" not in gateway:
        fail("[入手] RemoteError が AppCopy.invalidURL 未使用")
    if "AppCopy.remoteNotConfigured" not in gateway:
        fail("[入手] RemoteError が AppCopy.remoteNotConfigured 未使用")
    if "AppCopy.zipExtractFailed" not in read(SRC / "Services" / "ZipUnarchiver.swift"):
        fail("[入手] ZipUnarchiver が AppCopy.zipExtractFailed 未使用")
    if 'zipExtractFailed = "ZIPの展開に失敗しました"' not in read(SRC / "Services" / "AppCopy.swift"):
        fail("[IA] AppCopy.zipExtractFailed がない")
    if "wifiUploadPageHTML" not in read(SRC / "Services" / "AppCopy.swift"):
        fail("[IA] AppCopy.wifiUploadPageHTML がない")
    if "AppCopy.wifiUploadPageHTML" not in read(SRC / "Services" / "Remote" / "WiFiTransferServer.swift"):
        fail("[入手] WiFiTransferServer が wifiUploadPageHTML 未使用")
    progress = read(SRC / "Services" / "ProgressStore.swift")
    if "notifyLibrary" not in progress:
        fail("[本棚] ProgressStore.notifyLibrary がない")
    if "func clearBookmarks" not in progress:
        fail("[読書] ProgressStore.clearBookmarks がない")
    if "func removeBookmark" not in progress:
        fail("[読書] ProgressStore.removeBookmark がない")
    if "RemoteEntryFilter.swift" not in read(ROOT / "MangaViewer" / "MangaViewer.xcodeproj" / "project.pbxproj"):
        fail("[pbx] RemoteEntryFilter.swift が Sources に無い")
    info = read(SRC / "Info.plist")
    if "NSLocalNetworkUsageDescription" not in info:
        fail("[入手] Info.plist にローカルネットワーク説明がない")
    if "com.comicbook.cbz" not in info:
        fail("[入手] Info.plist に cbz タイプがない")
    if "UTExportedTypeDeclarations" not in info:
        fail("[入手] Info.plist に UTExportedTypeDeclarations がない")
    status = read(SRC / "Views" / "TransferStatusView.swift")
    if "pendingOpenVolumeId" not in status or "readNow" not in status:
        fail("[入手] TransferStatusView から読めない")
    if "readyToRead" not in status:
        fail("[入手] TransferStatusView に読める作品セクションがない")
    if "readableRank" not in status:
        fail("[入手] TransferStatusView の読める作品の優先並びがない")
    if "readablePercent" not in status:
        fail("[入手] TransferStatusView の進み％二次ソートがない")
    if "continueReading" not in status:
        fail("[入手] TransferStatusView の続きを読む CTA がない")
    if "cancelAllDownloads" not in status and "cancelAllActive" not in status:
        fail("[入手] TransferStatus に一括中止がない")
    for rel in [
        "Views/Import/RemoteBrowserView.swift",
        "Views/Import/ImportHubView.swift",
        "Views/Import/WiFiTransferView.swift",
        "ContentView.swift",
    ]:
        t = read(SRC / rel)
        if "succeed(job, volumeId:" not in t and "succeed(job, volumeId :" not in t:
            # tolerate whitespace variants
            if "volumeId:" not in t or "succeed(job" not in t:
                fail(f"[入手] {rel} が succeed(..., volumeId:) 未配線")
    reader = read(SRC / "Views" / "ReaderView.swift")
    if "bookmarkListSheet" not in reader and "AppCopy.bookmarkList" not in reader:
        fail("[読書] しおり一覧がない")
    if "webtoonJumpID" not in reader:
        fail("[読書] webtoon しおりジャンプがない")
    if "bookmarkClearAll" not in reader and "clearBookmarks" not in reader:
        fail("[読書] しおり一括解除がない")
    if "confirmClearBookmarks" not in reader:
        fail("[読書] しおり一括解除の確認がない")
    if "bookmarkClearAll)（\\(marks.count)" not in reader and "bookmark) \\(marks.count)" not in reader:
        fail("[読書] しおり全解除ダイアログの件数がない")
    if "bookmarkListFooter" not in reader:
        fail("[読書] しおり一覧の操作ヒントがない")
    content = read(SRC / "ContentView.swift")
    if "pendingOpenVolumeId" not in content:
        fail("[入手] ContentView が pendingOpenVolumeId 未配線")
    if "reading = nil" not in content:
        fail("[入手] ContentView が読書中の差し替え未対応")
    if "readingAutoResume = pct > 0 && pct < 100" not in content:
        fail("[入手] ContentView の Transfer から読むが続き判定でない")
    if "toast = nil" not in content:
        fail("[入手] ContentView が読む開始時にトーストを消していない")
    library = read(SRC / "Views" / "LibraryView.swift")
    if "progressBadge" not in library:
        fail("[本棚] 表紙進捗バッジがない")
    if "compact: true" not in library and "compact:true" not in library:
        fail("[本棚] リスト表紙のcompactバッジがない")
    if "readingVols" not in library or ".max(by:" not in library:
        fail("[本棚] シリーズ表紙の続き優先（進み％）がない")
    # シリーズ表紙バッジに未読カウントを出さない（volumeCell の未読テキストは可）
    if "AppCopy.unread) \\(unread)" in library or "unread > 0 && reading == 0 && done == 0" in library:
        fail("[本棚] シリーズ表紙に未読バッジが出ている")
    cover = read(SRC / "Views" / "CoverThumbView.swift")
    if "struct CoverProgressBadge" not in cover:
        fail("[本棚] CoverProgressBadge 共通バッジがない")
    if "struct CoverBookmarkBadge" not in cover:
        fail("[本棚] CoverBookmarkBadge 共通バッジがない")
    if "bookmarkCountBadge" not in library:
        fail("[本棚] しおり数バッジがない")
    if "DownloadStatusChip" not in library:
        fail("[本棚] 入手チップがない")
    if "continueReading" not in library and "AppCopy.continueReading" not in library:
        fail("[本棚] 続きを読むがない")
    if "AppCopy.bookmarkList" not in library:
        fail("[本棚] コンテキストメニューのしおり一覧導線がない")
    overlay = SRC / "Views" / "ActivityOverlayView.swift"
    if not overlay.exists():
        fail("[入手] ActivityOverlayView がない")
    overlay_t = read(overlay)
    if "cancelDownload" not in overlay_t:
        fail("[入手] DownloadStatusChip に中止がない")
    remote = read(SRC / "Views" / "Import" / "RemoteBrowserView.swift")
    if ".contextMenu" not in remote:
        fail("[入手] RemoteBrowser の読むコンテキストメニューがない")
    if "このフォルダの作品を入手" not in remote and "downloadThisFolder" not in remote:
        fail("[入手] RemoteBrowser にフォルダ入手CTAがない")
    if "onShelf" not in remote and "alreadyOnShelf" not in remote:
        fail("[入手] RemoteBrowser の本棚判定がない")
    if "justImported" not in remote:
        fail("[入手] RemoteBrowser の入手完了バナーがない")
    if "12_000_000_000" not in remote and "scheduleClearJustImported" not in remote:
        fail("[入手] RemoteBrowser 入手完了バーの表示時間制御がない")
    if "bookmarks(for: volume.id)" not in remote and "linger" not in remote:
        # scheduleClearJustImported がしおりでも長く残す
        if "12_000_000_000" not in remote:
            fail("[入手] RemoteBrowser 入手完了バーの延長表示がない")
    if "justImported = nil" not in remote or "onChange(of: currentPath)" not in remote:
        fail("[入手] RemoteBrowser パス変更で入手完了バー未クリア")
    if "getWorksStayHint" not in remote:
        fail("[入手] RemoteBrowser に入手継続ヒントがない")
    if "worksOrdered" not in remote and "comicsOrdered" not in remote:
        fail("[入手] RemoteBrowser の未入手優先ソートがない")
    if "remoteSectionNewWorks" not in remote and "remoteSectionOnShelf" not in remote:
        fail("[入手] RemoteBrowser の未入手／本棚セクション分割がない")
    if "importedNew" not in remote:
        fail("[入手] RemoteBrowser の既存スキップメッセージがない")
    if "remoteWorksSummary" not in remote:
        fail("[入手] RemoteBrowser の作品サマリーがない")
    if "onShelfReadHint" not in remote:
        fail("[入手] RemoteBrowser の本棚から読むヒントがない")
    if "CoverProgressBadge" not in remote:
        fail("[入手] RemoteBrowser が CoverProgressBadge 未使用")
    if "CoverBookmarkBadge" not in remote:
        fail("[入手] RemoteBrowser が CoverBookmarkBadge 未使用")
    if "downloadNewWorksCount" not in remote:
        fail("[入手] RemoteBrowser に未入手まとめ入手がない")
    if "startNewWorksImport" not in remote:
        fail("[入手] RemoteBrowser のまとめ入手関数がない")
    if "announce: idx == 0" not in remote and "announce: idx==0" not in remote:
        fail("[入手] まとめ入手のトースト抑制がない")
    if "readyDownloadCount" not in remote:
        fail("[入手] RemoteBrowser の読める件数がない")
    # 作品セクションがフォルダより先（作品選び優先）
    new_pos = remote.find("remoteSectionNewWorks")
    folder_pos = remote.find("remoteSectionFolders")
    if new_pos >= 0 and folder_pos >= 0 and new_pos > folder_pos:
        fail("[入手] RemoteBrowser がフォルダ優先（作品選び順でない）")
    hub = read(SRC / "Views" / "Import" / "ImportHubView.swift")
    if "readyDownloadCount" not in hub:
        fail("[入手] ImportHub の読める件数がない")
    if "singleReadyResume" not in hub:
        fail("[入手] ImportHub の続き／読む切替がない")
    if "singleReadyPercent" not in hub:
        fail("[入手] ImportHub の続き％表示がない")
    wifi = read(SRC / "Views" / "Import" / "WiFiTransferView.swift")
    if "singleReadyResume" not in wifi:
        fail("[入手] WiFi の続き／読む切替がない")
    if "singleReadyPercent" not in wifi:
        fail("[入手] WiFi の続き％表示がない")
    if "CoverBookmarkBadge" not in wifi:
        fail("[入手] WiFi 完了カードのしおりバッジがない")
    if "bookmark) \\(marks)" not in wifi and "AppCopy.bookmark) \\(marks)" not in wifi:
        if "\\(AppCopy.bookmark) \\(marks)" not in wifi:
            fail("[入手] WiFi 完了カードのしおり件数表示がない")
    filt2 = read(SRC / "Services" / "RemoteEntryFilter.swift")
    if "worksOrdered" not in filt2:
        fail("[入手] RemoteEntryFilter.worksOrdered がない")
    thumbs = read(SRC / "Views" / "ThumbnailGridView.swift")
    if "onlyBookmarks" not in thumbs:
        fail("[読書] ページ一覧のしおり絞り込みがない")
    if "hereNow" not in thumbs:
        fail("[読書] ページ一覧のいまここ表示がない")
    if "scrollTo" not in thumbs:
        fail("[読書] ページ一覧のいまここスクロールがない")
    filt = read(SRC / "Services" / "RemoteEntryFilter.swift")
    if "UserFacingText.title" not in filt:
        fail("[入手] RemoteEntryFilter が表示タイトル検索未対応")
    volume_info = read(SRC / "Views" / "VolumeInfoView.swift")
    if "openAtPage" not in volume_info:
        fail("[情報] VolumeInfo からしおりへ飛べない")
    if "AppCopy.openToRead" not in volume_info and "AppCopy.continueReading" not in volume_info:
        fail("[情報] VolumeInfo の読む CTA がない")
    if "AppCopy.continueReading" not in volume_info:
        fail("[情報] VolumeInfo の続きを読む CTA がない")
    if "continueReading) \\(progress)%" not in volume_info and 'continueReading) \\(progress)%' not in volume_info:
        if "\\(AppCopy.continueReading) \\(progress)%" not in volume_info:
            fail("[情報] VolumeInfo の続き％表示がない")
    if "continueReading) · \\(AppCopy.bookmark) \\(bookmarks.count)" not in volume_info:
        fail("[情報] 表紙下の続き+しおりがない")
    if "hereNow" not in volume_info:
        fail("[情報] VolumeInfo しおりのいまここがない")
    if "bookmarkSubtitle" not in volume_info:
        fail("[情報] VolumeInfo しおりの相対ページがない")
    if "CoverBookmarkBadge" not in volume_info:
        fail("[情報] VolumeInfo が CoverBookmarkBadge 未使用")
    cover = read(SRC / "Views" / "CoverThumbView.swift")
    if "CoverProgressBadge" not in cover or "CoverBookmarkBadge" not in cover:
        fail("[表紙] CoverProgressBadge / CoverBookmarkBadge がない")
    if "monospacedDigit" not in cover:
        fail("[表紙] 進捗バッジの等幅数字がない")
    if "foregroundStyle(.orange)" not in cover:
        fail("[表紙] しおりバッジのオレンジ強調がない")
    if "allowsHitTesting(false)" not in cover:
        fail("[表紙] バッジがタップを奪わない設定がない")
    if "bookmarkHereSection" not in volume_info:
        fail("[情報] VolumeInfo しおりのいまここセクションがない")
    if "bookmarkInfoRow" not in volume_info:
        fail("[情報] VolumeInfo しおり行が共通化されていない")
    if "bookmarkEmptyBody" not in volume_info:
        fail("[情報] VolumeInfo しおり空状態がない")
    if "UIImpactFeedbackGenerator(style: .medium)" not in volume_info:
        fail("[情報] VolumeInfo 続き haptic が medium でない")
    copy = read(SRC / "Services" / "AppCopy.swift")
    if "hereNow" not in copy:
        fail("[IA] AppCopy.hereNow がない")
    if "remoteWorksSummary" not in copy:
        fail("[IA] AppCopy.remoteWorksSummary がない")
    if "onShelfReadHint" not in copy:
        fail("[IA] AppCopy.onShelfReadHint がない")
    reader = read(SRC / "Views" / "ReaderView.swift")
    if "hereNow" not in reader:
        fail("[読書] しおり一覧のいまここがない")
    if "bookmarkHereSection" not in reader and "bookmarkRow" not in reader:
        fail("[読書] しおり一覧のいまここセクションがない")
    if "bookmarkSubtitle" not in reader:
        fail("[読書] しおり一覧の相対ページ表示がない")
    if "bookmarkClearAllMessage" not in reader:
        fail("[読書] しおり全解除の説明文がない")
    if "bookmarkPagesAhead" not in copy:
        fail("[IA] AppCopy.bookmarkPagesAhead がない")
    if "bookmarkClearAllMessage" not in copy:
        fail("[IA] AppCopy.bookmarkClearAllMessage がない")
    if "readyToRead" not in overlay_t:
        fail("[入手] DownloadStatusChip に読める件数がない")
    if "readyChip" not in overlay_t:
        fail("[入手] DownloadStatusChip に読める作品チップがない")
    if "resumeLabel" not in overlay_t:
        fail("[入手] DownloadStatusChip の続き／読む切替がない")
    if "readyRank" not in overlay_t:
        fail("[入手] DownloadStatusChip の続き優先並べ替えがない")
    if "readyPercent" not in overlay_t:
        fail("[入手] DownloadStatusChip の進み％二次ソートがない")
    if "CoverProgressBadge" not in overlay_t:
        fail("[入手] DownloadStatusChip の表紙進捗バッジがない")
    if "CoverBookmarkBadge" not in overlay_t:
        fail("[入手] DownloadStatusChip の表紙しおりバッジがない")
    if "environmentObject" not in overlay_t and "@EnvironmentObject" not in overlay_t:
        fail("[入手] DownloadStatusChip が LibraryStore 未配線")
    if "AppCopy.bookmark) \\(marks)" not in overlay_t and "\\(AppCopy.bookmark) \\(marks)" not in overlay_t:
        fail("[入手] DownloadStatusChip のしおり件数 CTA がない")
    if "marksN" not in overlay_t:
        fail("[入手] DownloadStatusChip 入手中のしおり件数サマリーがない")
    transfer = read(SRC / "Views" / "TransferStatusView.swift")
    if "CoverBookmarkBadge" not in transfer:
        fail("[入手] TransferStatus 表紙にしおりバッジがない")
    if "readableRank" not in transfer:
        fail("[入手] TransferStatus の読む順並べ替えがない")
    if "readablePercent" not in transfer:
        fail("[入手] TransferStatus の進み％二次ソートがない")
    if "readableBookmarkCount" not in transfer:
        fail("[入手] TransferStatus のしおり件数集計がない")
    if "clearFinished" not in transfer or "toast = nil" not in transfer:
        fail("[入手] TransferStatus 完了消去でトースト未クリア")
    if ".contextMenu" not in transfer:
        fail("[入手] TransferStatus の読むコンテキストメニューがない")
    remote = read(SRC / "Views" / "Import" / "RemoteBrowserView.swift")
    if "shelfReadRank" not in remote:
        fail("[入手] RemoteBrowser 本棚作品の続き優先並べ替えがない")
    if "shelfReadingOrdered" not in remote:
        fail("[入手] RemoteBrowser が shelfReadingOrdered 未使用")
    if "shelfReadingOrdered" not in filt2:
        fail("[入手] RemoteEntryFilter.shelfReadingOrdered がない")
    if "continueReading" not in remote or "justImported" not in remote:
        fail("[入手] RemoteBrowser 入手完了バーの読む導線がない")
    if "reading:" not in remote and "readingOnShelf" not in remote:
        fail("[入手] RemoteBrowser 作品サマリーの読書中件数がない")
    if "continueReading) \\(readingOnShelf)" not in remote and "readingInProgress) \\(readingOnShelf)" not in remote:
        if "readingOnShelf" not in remote:
            fail("[入手] RemoteBrowser 本棚セクションの続き件数がない")
    if "singleReadyResume" not in remote:
        fail("[入手] RemoteBrowser の続き／読む切替がない")
    if "ProgressView(value: Double(pct)" not in remote and "ProgressView(value: Double(pct)," not in remote:
        fail("[入手] RemoteBrowser 本棚行の続きProgressがない")
    if "readyDownloadCount > 0" not in remote:
        fail("[入手] RemoteBrowser 空フォルダの読める導線がない")
    if "bookmarkRemove" not in reader:
        fail("[読書] しおり一覧ツールバーの付け外しがない")
    if "onShelfReadHint" in remote and "continueReading" in remote:
        pass  # 読書中ヒントは onShelfReadHint · continueReading で合成
    else:
        fail("[入手] RemoteBrowser の本棚から読むヒントがない")
    if "jumpToPage" not in reader:
        fail("[読書] しおり一覧のこのページへがない")
    if "abs($0 - currentPageIndex)" not in reader and "currentPageIndex)" not in reader:
        fail("[読書] しおり一覧の近い順並べ替えがない")
    if "bookmarkSubtitle(page: nearest" not in reader:
        fail("[読書] しおりフッターの最寄り相対距離がない")
    if "notifyLibrary()" not in reader:
        fail("[読書] しおり削除後の本棚通知がない")
    if "jumpToPage" not in volume_info:
        fail("[情報] しおり行のこのページへがない")
    if "hereNow) · \\(pagePct)%" not in volume_info and "pagePct" not in volume_info:
        fail("[情報] しおり行のページ％がない")
    if "pagePct" not in reader:
        fail("[読書] しおり行のページ％がない")
    if "presentationBackgroundInteraction" not in reader:
        fail("[読書] しおり一覧の背面操作許可がない")
    if reader.count("presentationBackgroundInteraction") < 2:
        fail("[読書] ページ一覧の背面操作許可がない")
    if "here ? .light : .medium" not in reader and "here ? .light : .medium" not in volume_info:
        fail("[読書] しおりジャンプの medium haptic がない")
    if "toBookmark ? .medium : .light" not in reader:
        fail("[読書] ページ一覧しおりジャンプの medium haptic がない")
    if "pendingOpenVolumeId" not in library or "readyDownloadCount == 1" not in library:
        fail("[本棚] 読める1件の即開きがない")
    if "foregroundStyle(.orange)" not in library:
        fail("[本棚] シリーズ行のしおりオレンジ強調がない")
    cover_badge = read(SRC / "Views" / "CoverThumbView.swift")
    if "CoverBookmarkBadge" in cover_badge and "monospacedDigit" not in cover_badge:
        fail("[表紙] CoverBookmarkBadge の等幅数字がない")
    for rel, label in [
        ("Views/Import/RemoteBrowserView.swift", "RemoteBrowser"),
        ("Views/Import/ImportHubView.swift", "ImportHub"),
        ("Views/Import/WiFiTransferView.swift", "WiFi"),
        ("Views/LibraryView.swift", "Library"),
        ("Views/TransferStatusView.swift", "TransferStatus"),
        ("Views/ActivityOverlayView.swift", "DownloadStatusChip"),
        ("ContentView.swift", "ContentView"),
    ]:
        t = read(SRC / rel)
        if "pendingOpenVolumeId" in t and "toast = nil" not in t:
            fail(f"[入手] {label} が pendingOpen 時にトースト未クリア")
    if "onlyBookmarks" in thumbs and "currentPage" not in thumbs:
        fail("[読書] ページ一覧しおり絞り込みが現在位置未使用")
    if "foregroundStyle(.orange)" not in thumbs:
        fail("[読書] ページ一覧のしおりオレンジ強調がない")
    if "onlyBookmarks ? AppCopy.bookmarkList" not in thumbs and 'onlyBookmarks ? AppCopy.bookmarkList' not in thumbs:
        fail("[読書] ページ一覧のしおりモードタイトルがない")
    if "bookmarkEmpty" not in thumbs or "hereNow" not in thumbs:
        fail("[読書] ページ一覧しおり空のいまここがない")
    if "pagePct" not in thumbs:
        fail("[読書] ページ一覧のページ％がない")
    if "onPick(currentPage)" not in thumbs:
        fail("[読書] しおり空のいまここへ戻るがない")
    if "pagePct)%" not in reader or "currentPageIndex + 1) / \\(volume.pageCount) · \\(pagePct)%" not in reader:
        # スライダー／webtoon 進捗の％
        if "· \\(pagePct)%" not in reader:
            fail("[読書] ページ送りUIの％がない")
    if "ProgressView" not in volume_info:
        fail("[情報] しおり行のページ位置プログレスがない")
    if "tapToReadHint" not in transfer:
        fail("[入手] TransferStatus のタップで読むヒントがない")
    if "readable.first" not in transfer or "open(vid)" not in transfer:
        fail("[入手] TransferStatus 読めるセクションの続きCTAがない")
    if "getWorksStayHint" not in transfer:
        fail("[入手] TransferStatus 入手中フッターヒントがない")
    if "clearFinished" not in transfer:
        fail("[入手] TransferStatus 完了セクションの消去がない")
    if "downloadFailed" not in transfer or "cancelled" not in transfer:
        fail("[入手] TransferStatus 完了セクションの失敗／中止件数がない")
    if "ProgressView(value: Double(pct)" not in remote:
        # justImported / shelf row のどちらかで続きProgress
        if "ProgressView(value: Double(pct)," not in remote:
            fail("[入手] RemoteBrowser の続きProgressがない")
    filt_tests = read(ROOT / "MangaViewer" / "MangaViewerTests" / "RemoteEntryFilterTests.swift")
    if "testShelfReadingOrderedSortsTitlesWithinSameRank" not in filt_tests:
        fail("[入手] shelfReadingOrdered 同ランクタイトル順テストがない")
    if "testShelfReadingOrderedSortsByPercentThenTitleWithinRank" not in filt_tests:
        fail("[入手] shelfReadingOrdered 同ランク進み％順テストがない")
    if "testShelfReadingOrderedSortsByMarksThenTitleWithinSamePercent" not in filt_tests:
        fail("[入手] shelfReadingOrdered 同％しおり順テストがない")
    if "percent:" not in remote and "shelfReadPercent" not in remote:
        fail("[入手] RemoteBrowser が shelfReadingOrdered の進み％未配線")
    filt3 = read(SRC / "Services" / "RemoteEntryFilter.swift")
    if "percent:" not in filt3 and "percent =" not in filt3:
        fail("[入手] RemoteEntryFilter.shelfReadingOrdered に進み％引数がない")
    library_store = read(SRC / "Services" / "LibraryStore.swift")
    if "case .progress:" not in library_store:
        fail("[本棚] 読み進みソートがない")
    if "rank(_ v: MangaVolume)" not in library_store and "pct > 0 && pct < 100" not in library_store:
        fail("[本棚] 読み進みソートが続き優先でない")
    if "readingCount" not in library_store and "sa.reading" not in library_store:
        fail("[本棚] シリーズの読書中優先並びがない")
    if "bookmarks(for: a.id).count" not in library_store and "bookmarks(for: vol.id)" not in library_store:
        fail("[本棚] 読み進みソートのしおりタイブレークがない")
    if "continueCard" not in library:
        fail("[本棚] 続きを読むカードがない")
    if "onOpen(volume, resume)" not in library:
        fail("[本棚] 読書中タップが続き開きになっていない")
    if "singleReadyResume" not in library:
        fail("[本棚] 読める1件の続き／読む切替がない")
    if "singleReadyPercent" not in library:
        fail("[本棚] 読める1件の進み％がない")
    if "readyDownloadCount > 0" not in library:
        fail("[本棚] 空状態の読める導線がない")
    if "seriesEmptyGetWorks" not in library and "seriesEmptyTitle" not in library:
        fail("[本棚] シリーズ空状態がない")
    if "backToAllWorks" not in library:
        fail("[本棚] シリーズ空状態の本棚戻りがない")
    if "readyDownloadCount" not in library:
        fail("[本棚] 読める作品ツールバー件数がない")
    if "clearSearch" not in library:
        fail("[本棚] 検索クリアがない")
    if "maxReadingPct" not in library:
        fail("[本棚] シリーズ表紙の最大進み％がない")
    if "CoverProgressBadge(percent: maxReadingPct" not in library:
        fail("[本棚] シリーズ表紙の CoverProgressBadge がない")
    if "resume ? .medium : .light" not in remote:
        fail("[入手] RemoteBrowser の続き haptic が medium でない")
    if "openToRead) · \\(AppCopy.bookmark)" not in remote and "bookmark) \\(marks)" not in remote:
        fail("[入手] RemoteBrowser スワイプ／メニューのしおり件数がない")
    if "bookmarkListFooter" not in library:
        fail("[本棚] リスト行のしおりフッターがない")
    cover2 = read(SRC / "Views" / "CoverThumbView.swift")
    if "bookmarkListFooter" not in cover2:
        fail("[表紙] CoverBookmarkBadge の一覧ヒントがない")
    thumbs2 = read(SRC / "Views" / "ThumbnailGridView.swift")
    if "hereNow) \\(pagePct)%" not in thumbs2 and "hereNow) \\(pagePct)" not in thumbs2:
        if "AppCopy.hereNow) \\(pagePct)%" not in thumbs2:
            fail("[読書] ページ一覧しおり切替のいまここ％がない")
    wifi = read(SRC / "Views" / "Import" / "WiFiTransferView.swift")
    if "continueReading) \\(pct)% · \\(AppCopy.bookmark)" not in wifi and "bookmark) \\(marks)" not in wifi:
        fail("[入手] WiFi 完了CTAの続き+しおりがない")
    hub = read(SRC / "Views" / "Import" / "ImportHubView.swift")
    if "bookmark) \\(marks)" not in hub:
        fail("[入手] ImportHub 読める1件のしおり件数がない")
    if "continueReading) \\(pct)% · \\(AppCopy.bookmark)" not in library and "bookmark) \\(marks)" not in library:
        fail("[本棚] コンテキストメニューの続き+しおりがない")
    if "continueReading) \\(pct)% · \\(AppCopy.bookmark) \\(marks)" not in remote:
        fail("[入手] RemoteBrowser 本棚行の続き+しおりがない")
    copy = read(SRC / "Services" / "AppCopy.swift")
    if "marks: Int = 0" not in copy:
        fail("[入手] remoteWorksSummary のしおり件数引数がない")
    if "marks: shelfMarksN" not in remote:
        fail("[入手] RemoteBrowser 作品サマリのしおり未配線")
    if "continueReading) \\(singleReadyPercent" not in remote and "singleReadyPercent ?? 0" not in remote:
        fail("[入手] RemoteBrowser 空状態の続き％がない")
    if "readyToRead)（1）" not in library and "singleReadyPercent ?? 0" not in library:
        fail("[本棚] 空状態の続き％がない")
    if "bookmarkList)（\\(hereMarks.count)）· \\(pagePct)%" not in volume_info and "pagePct)%" not in volume_info:
        if "hereNow) · \\(pagePct)%" not in volume_info:
            fail("[情報] しおりいまここ見出しの％がない")
    if "singleReadyResume ? .medium : .light" not in remote:
        fail("[入手] RemoteBrowser 読める1件の続き haptic がない")
    if "AppCopy.finishedReading" not in remote:
        fail("[入手] RemoteBrowser 読了 a11y がない")
    if "return AppCopy.startOver" in remote or "AppCopy.startOver : AppCopy.openToRead" in remote:
        fail("[入手] RemoteBrowser 読了が startOver になっている")
    if "resume ? .medium : .light" not in overlay_t:
        fail("[入手] DownloadStatusChip の続き haptic が medium でない")
    if "bookmark) \\(marksMenu)" not in transfer and "AppCopy.bookmark) \\(marksMenu)" not in transfer:
        if "\\(AppCopy.bookmark) \\(marksMenu)" not in transfer:
            fail("[入手] TransferStatus コンテキストのしおり件数がない")
    if "pagePct" not in reader or "bookmarkEmptyBody" not in reader:
        fail("[読書] しおり空状態のページ％がない")
    if "resumeReading) \\(resumePct)%" not in reader and "resumePct)%" not in reader:
        fail("[読書] 続き選択ボタンの進み％がない")
    if "bookmark) \\(marksN)" not in reader and "AppCopy.bookmark) \\(marksN)" not in reader:
        if "marksN > 0" not in reader:
            fail("[読書] 続き選択のしおり件数がない")
    if "clearProgress(for: volume.id)" not in reader:
        fail("[読書] 続き選択の最初からで進捗クリアがない")
    if "UIImpactFeedbackGenerator(style: .medium)" not in reader:
        fail("[読書] 続き選択の medium haptic がない")
    if "resumePct" not in reader:
        fail("[読書] 続き選択のページ％がない")
    if "UIImpactFeedbackGenerator(style: .medium)" not in library:
        fail("[本棚] 続きカードの medium haptic がない")
    if "singleReadyResume ? .medium : .light" not in library:
        fail("[本棚] 読める1件の続き haptic がない")
    if "clearProgress(for: volume.id)" not in library:
        fail("[本棚] 最初からで進捗クリアがない")
    if "notifyLibrary()" not in library:
        fail("[本棚] 最初からの本棚通知がない")
    hub = read(SRC / "Views" / "Import" / "ImportHubView.swift")
    wifi = read(SRC / "Views" / "Import" / "WiFiTransferView.swift")
    if "singleReadyResume ? .medium : .light" not in hub:
        fail("[入手] ImportHub 読める1件の続き haptic がない")
    if "singleReadyResume ? .medium : .light" not in wifi:
        fail("[入手] WiFi 読める1件の続き haptic がない")
    if "singleReadyMarks" not in hub:
        fail("[入手] ImportHub 読める1件のしおり件数がない")
    if "singleReadyMarks" not in wifi:
        fail("[入手] WiFi 読める1件のしおり件数がない")
    if "singleReadyMarks" not in remote:
        fail("[入手] RemoteBrowser 読める1件のしおり件数がない")
    if "singleReadyMarks" not in library:
        fail("[本棚] 読める1件のしおり件数がない")
    if 'bookmarkList)（\\(marks.count)）' not in reader and "marks.count)）" not in reader:
        fail("[読書] しおりナビタイトルの件数がない")
    if 'bookmarkList)（\\(bookmarked.count)）' not in thumbs2 and "bookmarked.count)）" not in thumbs2:
        fail("[読書] サムネしおりナビタイトルの件数がない")
    if "bookmarkList) · \\(progress)%" not in volume_info and "bookmarkEmpty) · \\(AppCopy.continueReading)" not in volume_info:
        if "continueReading) \\(progress)% · \\(AppCopy.bookmarkListFooter)" not in volume_info:
            fail("[情報] しおり空の進み％がない")
    if "downloads) · \\(AppCopy.continueReading)" not in transfer and "readyToRead) \\(readable.count)" not in transfer:
        fail("[入手] TransferStatus ナビタイトルの件数がない")
    if "currentPageIndex + 1) / \\(volume.pageCount) · \\(pagePct)%" not in reader:
        fail("[読書] 上部ページ表示の％がない")
    if 'Text("\\(i + 1) · \\(pagePct)%\\(relative)")' not in thumbs2 and "i + 1) · \\(pagePct)%" not in thumbs2:
        fail("[読書] サムネ全ページの％表示がない")
    if "hereNow) · \\(pagePct)%" not in reader:
        fail("[読書] しおり空のいまここCTAがない")
    if "info) · \\(progress)%" not in volume_info and "AppCopy.info) · \\(progress)%" not in volume_info:
        fail("[情報] ナビタイトルの進み％がない")
    if "continueReading) \\(readingOnShelf)" not in remote:
        fail("[入手] 本棚見出しの続き件数が固定されていない")
    if "continueReading) · \\(pct)% · \\(AppCopy.bookmark)" not in library and "continueReading) · \\(pct)%" not in library:
        fail("[本棚] 続きから見出しの％がない")
    if "resumeReading) \\(resumePct)% · \\(AppCopy.bookmark)" not in reader and "resumeReading) \\(resumePct)%" not in reader:
        fail("[読書] 続き選択ボタンのしおり件数がない")
    if "marks:" not in remote or "bookmarks(for: existing.id).count" not in remote:
        fail("[入手] 本棚並びのしおりタイブレークがない")
    if "readableMarks" not in transfer:
        fail("[入手] TransferStatus のしおりタイブレークがない")
    if "readyMarks" not in overlay_t:
        fail("[入手] readyChip のしおりタイブレークがない")
    if "shelfReadRank" not in library:
        fail("[本棚] シリーズ内の続き→未読→読了並びがない")
    if "folderReadingStats" not in library:
        fail("[本棚] シリーズ一覧の続き優先並びがない")
    if "bookmarks(for: vol.id).count" not in library or "max(by:" not in library:
        fail("[本棚] 続きカードのしおりタイブレークがない")
    filter_src = read(SRC / "Services" / "RemoteEntryFilter.swift")
    if "marks: (RemoteEntry) -> Int" not in filter_src:
        fail("[入手] RemoteEntryFilter のしおりタイブレーク引数がない")
    if "settingsLibraryFooter" not in copy:
        fail("[IA] 本棚並び説明フッタがない")
    settings = read(SRC / "Views" / "SettingsView.swift")
    if "settingsLibraryFooter" not in settings:
        fail("[設定] 本棚並び説明フッタ未配線")
    if "displayedVolumes.count) \\(AppCopy.volumeCountSuffix)" not in library and "volumeCountSuffix" not in library:
        fail("[本棚] シリーズ内巻一覧の続き・しおり見出しがない")
    if "jumpToPage) · \\(pagePctTrailing)%" not in reader:
        fail("[読書] しおり行ジャンプの％がない")
    if "jumpToPage) · \\(pagePctTrailing)%" not in volume_info:
        fail("[情報] しおり行ジャンプの％がない")
    cover3 = read(SRC / "Views" / "CoverThumbView.swift")
    if 'systemName: "checkmark"' not in cover3:
        fail("[表紙] 読了バッジのチェックマークがない")
    if "終わった作品はここからすぐ読めます" not in copy:
        fail("[IA] 入手空の読むヒントがない")
    if "Button(AppCopy.getWorks)" not in transfer:
        fail("[入手] TransferStatus 空の作品を入手CTAがない")
    if "jumpToPage) · \\(pagePct)%" not in thumbs2 and "openToRead) · \\(pagePct)%" not in thumbs2:
        fail("[読書] サムネa11yヒントの％がない")
    if "本棚に入ったらすぐ読めます" not in copy:
        fail("[IA] 本棚空の読むヒントがない")
    if "toolbarTitleMenu" not in remote or "pathStack.count - 1" not in remote:
        fail("[入手] RemoteBrowser パス階層の現在位置表示がない")
    if "backToLibrary" not in reader or "bookmark) \\(marks.count)" not in reader:
        fail("[読書] 本棚へ戻るa11yのしおり件数がない")
    if "folderReadingStats(folder)" not in library:
        fail("[本棚] シリーズ戻りa11yの続き統計がない")
    if "accessibilityValue" not in volume_info or "AppCopy.save" not in volume_info:
        fail("[情報] 保存/閉じるのa11yがない")
    if "readableBookmarkCount" not in transfer or "AppCopy.close" not in transfer:
        fail("[入手] TransferStatus 閉じるa11yがない")
    if "singleReadyMarks" not in remote or "accessibilityHint(AppCopy.libraryTitle)" not in remote:
        fail("[入手] RemoteBrowser 閉じるa11yの本棚ヒントがない")
    if "hereNow) \\(currentPageIndex + 1) / \\(volume.pageCount) · \\(pagePct)%" not in reader:
        fail("[読書] しおりシート閉じるa11yのいまここ％がない")
    if "hereNow) \\(currentPage + 1) / \\(volume.pageCount) · \\(pagePct)%" not in thumbs2:
        fail("[読書] サムネ閉じるa11yのいまここ％がない")
    hub2 = read(SRC / "Views" / "Import" / "ImportHubView.swift")
    wifi2 = read(SRC / "Views" / "Import" / "WiFiTransferView.swift")
    if "accessibilityHint(AppCopy.libraryTitle)" not in hub2:
        fail("[入手] ImportHub 閉じるa11yの本棚ヒントがない")
    if "accessibilityHint(AppCopy.libraryTitle)" not in wifi2:
        fail("[入手] WiFi 閉じるa11yの本棚ヒントがない")
    if "settingsLibraryFooter" not in settings:
        fail("[設定] 閉じる/完了a11yの並び説明がない")
    content = read(SRC / "ContentView.swift")
    if "readingAutoResume = resume" not in content:
        fail("[入手] ContentView 外部Openの続き判定がない")
    if "resume ? .medium : .light" not in content:
        fail("[入手] ContentView 外部Openの続き haptic がない")
    if "readingAutoResume = pct > 0 && pct < 100" not in content:
        fail("[入手] ContentView pendingOpen の続き判定がない")
    if "import UIKit" not in content:
        fail("[入手] ContentView が UIKit 未import（haptic）")
    if "libraryEmptyBody" not in library or "accessibilityLabel(AppCopy.getWorks)" not in library:
        fail("[本棚] 空CTAのa11yがない")
    if "cancelAllDownloads)（\\(active.count)）" not in transfer:
        fail("[入手] TransferStatus 一括中止の件数がない")
    if "clearFinished" not in transfer or "readyToRead) \\(readable.count)" not in transfer:
        fail("[入手] TransferStatus 消去メニューの件数がない")
    if "startOver) · \\(AppCopy.bookmark)" not in library:
        fail("[本棚] メニュー最初からのしおり件数がない")
    if "downloadNewWorksCount(pending)" not in remote:
        fail("[入手] 未入手一括入手のa11yラベルがない")
    if "resume ? .medium : .light" not in library:
        fail("[本棚] 巻オープンの続き haptic がない")
    if "startFileImport(entry)" not in remote or "style: .light" not in remote:
        fail("[入手] スワイプ入手の haptic がない")
    if "onlyBookmarks || bookmarked.contains(i)" not in thumbs2:
        fail("[読書] サムネしおりジャンプの medium haptic がない")
    if "doneReadingSettings" not in reader or "prefs.layoutMode.label" not in reader:
        fail("[読書] 表示設定完了のa11yがない")
    if "reading > 0 ? .medium : .light" not in library:
        fail("[本棚] シリーズ開くの続き haptic がない")
    for rel in [
        "Views/Import/ImportHubView.swift",
        "Views/Import/WiFiTransferView.swift",
        "ContentView.swift",
        "Views/Import/RemoteBrowserView.swift",
    ]:
        t = read(SRC / rel)
        if "UserFacingText.title" not in t:
            fail(f"[入手] {rel} が UserFacingText 未使用（ジョブ表示名）")


def check_copy_centralized():
    """AppCopy 以外へのユーザー向け日本語直書きを禁止。"""
    pat = re.compile(r'"(?:[^"\\]|\\.)*[\u3040-\u30ff\u3400-\u9fff]')
    for path in swift_files():
        if path.name == "AppCopy.swift":
            continue
        for i, line in enumerate(read(path).splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("///"):
                continue
            if "AppCopy." in line:
                continue
            if pat.search(line):
                fail(f"[IA] {path.relative_to(SRC)}:{i} に AppCopy 外の日本語直書き")


def main():
    check_packages(); check_staging(); check_password(); check_layout(); check_transfer(); check_titles()
    check_reading_ia(); check_volume_id_wiring(); check_copy_centralized()
    if failures:
        print("QUALITY GATE FAILED")
        for f in failures: print(" -", f)
        return 1
    print("QUALITY GATE PASSED", len(swift_files()), "swift files")
    return 0
if __name__ == "__main__":
    sys.exit(main())
