#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""基本機能ゲート：本棚・読む・入手。ページ送りを壊す構成を拒否する。"""
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
        "Services/LibraryStore.swift",
        "Services/VolumeImporter.swift",
        "Services/ZipExtractor.swift",
        "Services/ReadingProgress.swift",
        "Models/MangaVolume.swift",
        "Models/ReadingModels.swift",
        "Services/DuoLayout.swift",
        "Views/DuoFrameView.swift",
    ]
    for rel in required:
        if not (SRC / rel).exists():
            fail(f"[基本] {rel} が無い")

    # 旧実装の残骸を禁止
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
    if "animated: !reduceMotion" in browser or "animated: true" in browser:
        fail("[読む] PageBrowser が animated setViewControllers している（scroll で落ちる）")
    if "Failed to determine navigation direction" in browser:
        fail("[読む] コメント以外の異常文字列")
    if "animated: false" not in browser:
        fail("[読む] setViewControllers を非アニメーションにしていない")

    reader = read(SRC / "Views" / "ReaderView.swift")
    if "PageBrowser(" not in reader:
        fail("[読む] ReaderView が PageBrowser を使っていない")
    if "allowsHitTesting(false)" not in reader:
        fail("[読む] Chrome 中央のヒット無効化が無い")
    if "containerSize = geo.size" in reader or "let _ = { containerSize" in reader:
        fail("[読む] GeometryReader 内で @State を書き換えている（起動／表示で落ちる）")
    if "DuoLayout.resolve" not in reader:
        fail("[Duo] ReaderView が DuoLayout を使っていない")
    if "DuoFrameView" not in reader:
        fail("[Duo] ReaderView が DuoFrameView を使っていない")
    if "duoEdgeTaps" not in reader:
        fail("[Duo] 見開きの端タップが無い")

    duo = read(SRC / "Services" / "DuoLayout.swift")
    if "aspect >= 1.25" not in duo:
        fail("[Duo] 横向き判定が無い")
    models = read(SRC / "Models" / "ReadingModels.swift")
    if "layoutMode: PageLayoutMode = .duo" not in models:
        fail("[Duo] 既定レイアウトが Duo ではない")

    pbx = read(ROOT / "MangaViewer" / "MangaViewer.xcodeproj" / "project.pbxproj")
    for path in swift_files():
        if path.name not in pbx:
            fail(f"[pbx] {path.relative_to(SRC)} が project.pbxproj に無い")
    if "SampleManga" not in pbx:
        fail("[pbx] SampleManga が無い")
    if "AMSMB2" in pbx or "Citadel" in pbx or "FeedKit" in pbx:
        fail("[範囲] リモート用 SPM が残っている")

    if failures:
        print("QUALITY GATE FAILED")
        for item in failures:
            print(" -", item)
        return 1
    print(f"QUALITY GATE PASSED {len(swift_files())} swift files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
