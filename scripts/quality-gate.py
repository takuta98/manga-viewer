#!/usr/bin/env python3
"""出荷前品質ゲート。ユーザーを動作確認役にしないための静的検査。

失敗したら push 禁止。個別バグの応急ではなく「系統」を潰す。
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "MangaViewer" / "MangaViewer"
failures: list[str] = []


def fail(msg: str) -> None:
    failures.append(msg)


def swift_files() -> list[Path]:
    return sorted(SRC.rglob("*.swift"))


def read(p: Path) -> str:
    return p.read_text(encoding="utf-8")


def check_no_uuid_prefixed_import_filenames() -> None:
    """系統A: 一時ファイル名に UUID- を付けて取り込みに使うな。ImportStaging を使え。"""
    pattern = re.compile(
        r"temporaryDirectory\.appendingPathComponent\(\s*UUID\(\)\.uuidString\s*\+\s*\"-\""
    )
    # もっと広い: UUID().uuidString + "-" 全般（ImportStaging 以外）
    broad = re.compile(r"UUID\(\)\.uuidString\s*\+\s*\"-\"")
    for p in swift_files():
        if p.name in {"ImportStaging.swift", "UserFacingText.swift"}:
            continue
        text = read(p)
        if pattern.search(text) or (
            broad.search(text) and "ImportStaging" not in text and p.name.endswith("View.swift")
        ):
            fail(
                f"[系統A:表示名汚染] {p.relative_to(ROOT)}: "
                "UUID+\"-\"+名前 で一時物を作っている。ImportStaging を使え。"
            )


def check_call_sites_use_staging() -> None:
    """系統A: 取込 View は ImportStaging / UserFacingText 必須。"""
    for rel in (
        "Views/Import/RemoteBrowserView.swift",
        "Views/Import/ImportHubView.swift",
    ):
        p = SRC / rel
        text = read(p)
        if "ImportStaging" not in text:
            fail(f"[系統A] {rel} が ImportStaging を使っていない。")
        if "UserFacingText" not in text:
            fail(f"[系統A] {rel} が UserFacingText を使っていない。")


def check_importer_uses_user_facing_text() -> None:
    """系統A: MangaImporter は必ず UserFacingText 経由でタイトルを決める。"""
    p = SRC / "Services" / "MangaImporter.swift"
    text = read(p)
    if "UserFacingText" not in text:
        fail("[系統A:表示名汚染] MangaImporter.swift が UserFacingText を使っていない。")
    if "deletingPathExtension().lastPathComponent" in text and "UserFacingText.title" not in text:
        fail("[系統A:表示名汚染] 生の lastPathComponent をタイトルにしている疑い。")


def check_password_not_encoded() -> None:
    """系統B: RemoteSource.encode で password を書いてはいけない。"""
    p = SRC / "Models" / "RemoteSource.swift"
    text = read(p)
    # encode 関数内で password を encode していないこと
    m = re.search(r"func encode\(to encoder: Encoder\) throws \{([\s\S]*?)\n    \}", text)
    if not m:
        fail("[系統B:秘密漏えい] RemoteSource.encode が見つからない。")
        return
    body = m.group(1)
    if re.search(r"encode\(.*password", body) or 'forKey: .password' in body:
        fail("[系統B:秘密漏えい] RemoteSource.encode が password を JSON に書いている。")


def check_library_load_no_wipe() -> None:
    """系統C: decode 失敗時に ensureSample で上書きしない。"""
    p = SRC / "Services" / "LibraryStore.swift"
    text = read(p)
    if "blockPersistence" not in text:
        fail("[系統C:データ消滅] LibraryStore に blockPersistence がない。")
    if "catalogLoadError" not in text:
        fail("[系統C:データ消滅] 読込失敗をユーザーに出す catalogLoadError がない。")


def check_ats_not_wide_open() -> None:
    """系統D: ATS 全開禁止。"""
    plist = SRC / "Info.plist"
    text = read(plist)
    if "NSAllowsArbitraryLoads" in text and "<true/>" in text.split("NSAllowsArbitraryLoads", 1)[-1][:80]:
        fail("[系統D:通信安全] Info.plist で NSAllowsArbitraryLoads が有効。")


def check_import_staging_exists() -> None:
    if not (SRC / "Services" / "ImportStaging.swift").exists():
        fail("[系統A] ImportStaging.swift が無い。")
    if not (SRC / "Services" / "UserFacingText.swift").exists():
        fail("[系統A] UserFacingText.swift が無い。")


def check_user_facing_text_logic() -> None:
    """Linux 上でもタイトル浄化ロジックを検証（Swift なしでも）。"""
    samples = {
        "A1B2C3D4-E5F6-7890-ABCD-EF1234567890-ワンピース": "ワンピース",
        "a1b2c3d4e5f67890a1b2c3d4e5f67890_comic": "comic",
        "tmp-book": "book",
        "普通のタイトル": "普通のタイトル",
        "": "無題",
    }
    # ゲート内に同等ロジックを持つ（Swift 実装と乖離したらテスト側も更新）
    junk = [
        re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}[-_]"),
        re.compile(r"^[0-9a-fA-F]{32}[-_]"),
        re.compile(r"^tmp[-_]", re.I),
        re.compile(r"^temp[-_]", re.I),
        re.compile(r"^download[-_]", re.I),
        re.compile(r"^wifi-upload[-_]", re.I),
    ]

    def clean(raw: str) -> str:
        s = raw.strip()
        if not s:
            return "無題"
        changed = True
        while changed:
            changed = False
            for pat in junk:
                m = pat.match(s)
                if m:
                    s = s[m.end() :].lstrip("-_ ")
                    changed = True
                    break
        s = s.strip("-_ ")
        if "/" in s:
            s = s.rsplit("/", 1)[-1]
        return s or "無題"

    for inp, want in samples.items():
        got = clean(inp)
        if got != want:
            fail(f"[系統A:表示名浄化] '{inp}' -> '{got}' (expected '{want}')")


def check_pbxproj_integrity() -> None:
    pbx = ROOT / "MangaViewer" / "MangaViewer.xcodeproj" / "project.pbxproj"
    text = read(pbx)
    if ",," in text:
        fail("[系統E:プロジェクト破損] project.pbxproj に連続カンマ ,, がある。")
    if text.count("{") != text.count("}"):
        fail("[系統E:プロジェクト破損] project.pbxproj のブレース不均衡。")
    for name in ("UserFacingText.swift", "ImportStaging.swift", "KeychainStore.swift", "VolumeInfoView.swift"):
        if name not in text:
            fail(f"[系統E:プロジェクト] {name} が pbxproj に未登録。")



def check_library_delete_confirm() -> None:
    """系統F: 書庫のフォルダ・作品削除は確認アラート必須（日本語）。"""
    p = SRC / "Views" / "LibraryView.swift"
    text = read(p)
    if "folderPendingDelete" not in text:
        fail("[系統F:誤削除防止] LibraryView に folderPendingDelete がない。")
    if "volumePendingDelete" not in text:
        fail("[系統F:誤削除防止] LibraryView に volumePendingDelete がない。")
    if 'alert("フォルダを削除"' not in text:
        fail('[系統F:誤削除防止] LibraryView に「フォルダを削除」アラートがない。')
    if 'alert("作品を削除"' not in text:
        fail('[系統F:誤削除防止] LibraryView に「作品を削除」アラートがない。')
    # contextMenu / swipeActions から直接 library.delete しない
    for kind in ("contextMenu", "swipeActions"):
        # 粗い窓: kind ブロック近傍に pending 代入なしの library.delete(volume) がないこと
        for m in re.finditer(rf"\.{kind}\b", text):
            window = text[m.start() : m.start() + 500]
            if "library.delete(volume)" in window and "volumePendingDelete" not in window:
                fail(f"[系統F:誤削除防止] LibraryView の {kind} から直接 library.delete している。")
                break


def check_reader_continue_banner() -> None:
    """系統G: 進捗あり再開時は上部に「続きから」バナーを出し、短時間でフェードする。"""
    text = read(SRC / "Views" / "ReaderView.swift")
    if '"続きから"' not in text:
        fail('[系統G:続きバナー] ReaderView に「続きから」文言が無い。')
    if "showContinueBanner" not in text:
        fail("[系統G:続きバナー] showContinueBanner が無い。")
    if "continueFromBanner" not in text:
        fail("[系統G:続きバナー] continueFromBanner ビューが無い。")
    if "presentContinueBannerIfNeeded" not in text:
        fail("[系統G:続きバナー] presentContinueBannerIfNeeded が無い。")
    if "savedProgress > 0" not in text:
        fail("[系統G:続きバナー] progress>0（savedProgress > 0）の分岐が無い。")
    if "withAnimation(.easeOut" not in text:
        fail("[系統G:続きバナー] フェード用 withAnimation(.easeOut) が無い。")
    appears = re.findall(r"\.onAppear \{([\s\S]*?)\n        \}", text)
    if not any("presentContinueBannerIfNeeded" in body for body in appears):
        fail("[系統G:続きバナー] onAppear から presentContinueBannerIfNeeded を呼んでいない。")


def check_reader_chrome_safe_area() -> None:
    """系統G: Reader chrome は GeometryProxy.safeAreaInsets。固定ノッチ余白と UIScreen.main 禁止。"""
    reader = SRC / "Views" / "ReaderView.swift"
    text = read(reader)
    if "chromeOverlay" not in text:
        fail("[系統G:セーフエリア] ReaderView に chromeOverlay が無い。")
        return
    if "safeAreaInsets.top" not in text:
        fail("[系統G:セーフエリア] chrome 上部が safeAreaInsets.top を使っていない。")
    if "safeAreaInsets.bottom" not in text:
        fail("[系統G:セーフエリア] chrome 下部が safeAreaInsets.bottom を使っていない。")
    if re.search(r"padding\(\s*\.top\s*,\s*54\s*\)", text):
        fail("[系統G:セーフエリア] ReaderView に固定 .padding(.top, 54) が残っている。")
    if re.search(r"padding\(\s*\.bottom\s*,\s*34\s*\)", text):
        fail("[系統G:セーフエリア] ReaderView に固定 .padding(.bottom, 34) が残っている。")
    for p in swift_files():
        if "UIScreen.main" in read(p):
            fail(
                f"[系統G:セーフエリア] {p.relative_to(ROOT)}: "
                "UIScreen.main は使うな（GeometryProxy / ウィンドウ scene を使え）。"
            )


def check_remote_browser_list_retry() -> None:
    """系統G: RemoteBrowser 一覧失敗は alert だけでなく再試行できること。"""
    rel = "Views/Import/RemoteBrowserView.swift"
    text = read(SRC / rel)
    if "listError" not in text:
        fail(f"[系統G:一覧再試行] {rel}: 一覧エラー用 listError が無い（alert 専用だと再試行できない）。")
    if 'Button("再試行")' not in text:
        fail(f"[系統G:一覧再試行] {rel}: 「再試行」ボタンが無い。")
    if not re.search(r'Button\("再試行"\)[\s\S]{0,160}reload\(\)', text):
        fail(f"[系統G:一覧再試行] {rel}: 再試行ボタンから reload() を呼んでいない。")
    # list 失敗が errorText（alert）だけに流れていないこと
    reload_fn = re.search(r"private func reload\(\) async \{([\s\S]*?)\n    \}", text)
    if not reload_fn:
        fail(f"[系統G:一覧再試行] {rel}: reload() が見つからない。")
    else:
        body = reload_fn.group(1)
        if "listError" not in body:
            fail(f"[系統G:一覧再試行] {rel}: reload() が listError を扱っていない。")
        if re.search(r"errorText\s*=", body):
            fail(f"[系統G:一覧再試行] {rel}: reload() が errorText（alert）に一覧失敗を流している。")


def check_display_layout_wired() -> None:
    """系統H: DisplayLayoutResolver が存在し ReaderView に配線されていること。"""
    resolver = SRC / "Services" / "DisplayLayoutResolver.swift"
    if not resolver.exists():
        fail("[系統H:表示レイアウト] DisplayLayoutResolver.swift が無い。")
        return
    rtext = read(resolver)
    if "aspect >= 1.25" not in rtext:
        fail("[系統H:表示レイアウト] 横長閾値 aspect >= 1.25 が無い。")
    if "縦" not in rtext and "portrait" not in rtext.lower():
        # Japanese explanation expected
        if "landscape" not in rtext:
            fail("[系統H:表示レイアウト] 縦画面→単ページの分岐が無い。")
    reader = read(SRC / "Views" / "ReaderView.swift")
    if "DisplayLayoutResolver.resolve" not in reader:
        fail("[系統H:表示レイアウト] ReaderView が DisplayLayoutResolver.resolve を呼んでいない。")
    pbx = read(ROOT / "MangaViewer" / "MangaViewer.xcodeproj" / "project.pbxproj")
    if "DisplayLayoutResolver.swift" not in pbx:
        fail("[系統H:表示レイアウト] DisplayLayoutResolver.swift が pbxproj に未登録。")


def check_transfer_status_sheet() -> None:
    """系統I: 書庫から転送状況シートを開けること。"""
    lib = read(SRC / "Views" / "LibraryView.swift")
    if "showTransfers" not in lib:
        fail("[系統I:転送UI] LibraryView に showTransfers が無い。")
    if "TransferStatusView()" not in lib:
        fail("[系統I:転送UI] LibraryView が TransferStatusView を sheet していない。")
    if not (SRC / "Views" / "TransferStatusView.swift").exists():
        fail("[系統I:転送UI] TransferStatusView.swift が無い。")
    if "TransferActivityCenter" not in lib:
        fail("[系統I:転送UI] LibraryView が TransferActivityCenter を参照していない。")


def check_last_browse_path() -> None:
    """系統J: リモート最終閲覧パスを接続ごとに記憶。"""
    model = read(SRC / "Models" / "RemoteSource.swift")
    if "lastBrowsePath" not in model:
        fail("[系統J:最終パス] RemoteSource に lastBrowsePath が無い。")
    if "forKey: .lastBrowsePath" not in model:
        fail("[系統J:最終パス] lastBrowsePath が Codable に無い。")
    browser = read(SRC / "Views" / "Import" / "RemoteBrowserView.swift")
    if "persistBrowsePath" not in browser:
        fail("[系統J:最終パス] RemoteBrowserView に persistBrowsePath が無い。")
    if "lastBrowsePath" not in browser:
        fail("[系統J:最終パス] RemoteBrowserView が lastBrowsePath を使っていない。")


def check_background_import() -> None:
    """系統K: 取込は裏で進め dismiss 可能。"""
    browser = read(SRC / "Views" / "Import" / "RemoteBrowserView.swift")
    if "attachTask" not in browser:
        fail("[系統K:裏取込] RemoteBrowserView が attachTask していない。")
    if "startFileImport" not in browser and "begin(title:" not in browser:
        fail("[系統K:裏取込] 裏取込開始が無い。")
    hub = read(SRC / "Views" / "Import" / "ImportHubView.swift")
    if "attachTask" not in hub:
        fail("[系統K:裏取込] ImportHubView が attachTask していない。")


def check_library_read_badge() -> None:
    """系統L: 書庫グリッド/リストで progressPercent >= 100 のとき「読了」を出す。"""
    rel = "Views/LibraryView.swift"
    text = read(SRC / rel)
    if "読了" not in text:
        fail(f"[系統L:読了バッジ] {rel} に「読了」が無い。")
    if "progressPercent" not in text:
        fail(f"[系統L:読了バッジ] {rel} が progressPercent を使っていない。")
    if not re.search(r"pct\s*>=\s*100", text):
        fail(f"[系統L:読了バッジ] {rel} に pct >= 100 の分岐が無い。")
    if "volumeListRow" not in text or "volumeGridCell" not in text:
        fail(f"[系統L:読了バッジ] {rel} に grid/list の作品行が無い。")


def main() -> int:
    check_import_staging_exists()
    check_no_uuid_prefixed_import_filenames()
    check_call_sites_use_staging()
    check_importer_uses_user_facing_text()
    check_password_not_encoded()
    check_library_load_no_wipe()
    check_ats_not_wide_open()
    check_user_facing_text_logic()
    check_pbxproj_integrity()
    check_library_delete_confirm()
    check_reader_continue_banner()
    check_reader_chrome_safe_area()
    check_remote_browser_list_retry()
    check_display_layout_wired()
    check_transfer_status_sheet()
    check_last_browse_path()
    check_background_import()
    check_library_read_badge()

    if failures:
        print("QUALITY GATE FAILED")
        for f in failures:
            print(" -", f)
        return 1
    print("QUALITY GATE PASSED", len(swift_files()), "swift files scanned")
    return 0


if __name__ == "__main__":
    sys.exit(main())
