#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""基本機能ゲート：本棚・読む・入手・Duo。ページ送りとレイアウトループを拒否する。"""
from __future__ import annotations
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "MangaViewer" / "MangaViewer"
failures: list[str] = []


def fail(msg: str) -> None:
    failures.append(msg)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def swift_files():
    return sorted(SRC.rglob("*.swift"))


def main() -> int:
    required = [
        "MangaViewerApp.swift",
        "ContentView.swift",
        "Views/LibraryView.swift",
        "Views/ReaderView.swift",
        "Views/PageBrowser.swift",
        "Views/PageImageView.swift",
        "Views/DuoFrameView.swift",
        "Services/LibraryStore.swift",
        "Services/VolumeImporter.swift",
        "Services/ZipExtractor.swift",
        "Services/ReadingProgress.swift",
        "Services/DuoLayout.swift",
        "Models/MangaVolume.swift",
        "Models/ReadingModels.swift",
    ]
    for rel in required:
        if not (SRC / rel).exists():
            fail(f"[基本] {rel} が無い")

    banned_names = [
        "ZipUnarchiver.swift",
        "PageTurnHost.swift",
        "PagePaneView.swift",
        "RemoteBrowserView.swift",
        "TransferStatusView.swift",
        "ActivityOverlayView.swift",
        "AppCopy.swift",
    ]
    for name in banned_names:
        if list(SRC.rglob(name)):
            fail(f"[削除] 旧ファイル {name} が残っている")

    if (SRC / "Services" / "Remote").exists():
        fail("[削除] Services/Remote が残っている")
    if (SRC / "Views" / "Import").exists():
        fail("[削除] Views/Import が残っている")

    library = read(SRC / "Views" / "LibraryView.swift")
    if 'navigationTitle("本棚")' not in library:
        fail("[本棚] タイトルが 本棚 ではない")
    if "fileImporter" not in library:
        fail("[入手] fileImporter が無い")
    if "作品を入手" not in library:
        fail("[入手] 作品を入手 が無い")
    if "読む" not in library:
        fail("[読む] 読む CTA が無い")

    image = read(SRC / "Views" / "PageImageView.swift")
    if "DragGesture" in image or ".gesture(" in image:
        fail("[読む] PageImageView にジェスチャがある（ページ送りを奪う）")

    browser = read(SRC / "Views" / "PageBrowser.swift")
    if "UIPageViewController" not in browser:
        fail("[読む] PageBrowser が UIPageViewController ではない")
    if "viewControllerBefore" not in browser or "viewControllerAfter" not in browser:
        fail("[読む] 前後ページ dataSource が無い")
    if "handleTap" not in browser:
        fail("[読む] 端タップめくりが無い")
    if "isBusy" not in browser:
        fail("[読む] めくり中の SwiftUI 同期抑止が無い")
    if "publishIndex" not in browser:
        fail("[読む] PageBrowser の Binding 更新遅延が無い")
    if "pageCurl" not in browser:
        fail("[読む] pageCurl（めくり）が無い")
    if "isTurning" not in browser:
        fail("[読む] 端タップめくりアニメ経路が無い")
    if "pageRevision" not in browser:
        fail("[読む] ページ再生成 revision が無い")

    reader = read(SRC / "Views" / "ReaderView.swift")
    if "PageBrowser(" not in reader:
        fail("[読む] ReaderView が PageBrowser を使っていない")
    if "allowsHitTesting(false)" not in reader:
        fail("[読む] Chrome 中央のヒット無効化が無い")
    if "containerSize = geo.size" in reader or "let _ = { containerSize" in reader:
        fail("[読む] GeometryReader 内で @State を書き換えている")
    if "onPreferenceChange(ReaderSizeKey" in reader or "ReaderSizeKey" in reader:
        fail("[Duo] preference→State ループの残骸がある")
    if "else if layout == .duo" in reader or "if layout == .duo" in reader:
        fail("[Duo] 単ページと Duo で View 木を分岐している（固まる）")
    if "appliedLayout" not in reader:
        fail("[Duo] 安定レイアウト状態が無い")
    if "DuoLayout.isUsable" not in reader:
        fail("[Duo] 不正サイズの無視が無い")
    if "adoptSize" not in reader:
        fail("[Duo] サイズ採用経路が無い")
    if 'style: appliedLayout == .duo ? .slide' in reader:
        fail("[読む] Duo 中にめくりをスライドへ落としている")
    if "pageRevision" not in reader:
        fail("[読む] pageRevision が無い")

    duo = read(SRC / "Services" / "DuoLayout.swift")
    if "isUsable" not in duo:
        fail("[Duo] isUsable が無い")
    if "aspect >= 1.25" not in duo:
        fail("[Duo] 横向き判定が無い")

    frame = read(SRC / "Views" / "DuoFrameView.swift")
    if ".aspectRatio(" in frame:
        fail("[Duo] DuoFrameView が aspectRatio で自分のサイズを変えている（計測ループ）")

    models = read(SRC / "Models" / "ReadingModels.swift")
    if "layoutMode: PageLayoutMode = .duo" not in models:
        fail("[Duo] 既定レイアウトが Duo ではない")
    if "turnStyle: PageTurnStyle = .curl" not in models:
        fail("[読む] 既定のページ送りがめくり（curl）ではない")

    pbx = read(ROOT / "MangaViewer" / "MangaViewer.xcodeproj" / "project.pbxproj")
    for path in swift_files():
        if path.name not in pbx:
            fail(f"[pbx] {path.relative_to(SRC)} が project.pbxproj に無い")
    if "SampleManga" not in pbx:
        fail("[pbx] SampleManga が無い")
    # AMSMB2 は NAS (SMB) 対応で許可。それ以外のリモート用 SPM は引き続き禁止。
    if "Citadel" in pbx or "FeedKit" in pbx:
        fail("[範囲] リモート用 SPM が残っている")
    if "AMSMB2" not in pbx:
        fail("[NAS] AMSMB2 が project.pbxproj に無い")

    if failures:
        print("QUALITY GATE FAILED")
        for item in failures:
            print(" -", item)
        return 1
    print(f"QUALITY GATE PASSED {len(swift_files())} swift files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
