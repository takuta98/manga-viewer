#!/usr/bin/env python3
from __future__ import annotations
import re, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "MangaViewer" / "MangaViewer"
failures: list[str] = []

def fail(m): failures.append(m)
def swift_files(): return sorted(SRC.rglob("*.swift"))
def read(p): return p.read_text(encoding="utf-8")

def check_no_packages():
    pbx = read(ROOT/"MangaViewer"/"MangaViewer.xcodeproj"/"project.pbxproj")
    if "XCRemoteSwiftPackageReference" in pbx or "AMSMB2" in pbx or "Citadel" in pbx:
        fail("[パッケージ禁止] SPM / AMSMB2 / Citadel が残っている")

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

def main():
    check_no_packages(); check_staging(); check_password(); check_layout(); check_transfer(); check_titles()
    if failures:
        print("QUALITY GATE FAILED")
        for f in failures: print(" -", f)
        return 1
    print("QUALITY GATE PASSED", len(swift_files()), "swift files")
    return 0
if __name__ == "__main__":
    sys.exit(main())
