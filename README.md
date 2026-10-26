# 漫画ビューア（iPhone Duo）

SwiftUI 製の漫画ビューアです。外部 Swift パッケージは使いません（Apple 標準フレームワークのみ）。

## できること

- 書庫（フォルダ整理・検索・グリッド/リスト）
- 全画面読書、スライド / ページめくり
- 縦は常に1ページ、横で十分な幅のときだけ見開き
- 裏取り込みと転送状況画面
- SMB / WebDAV / SFTP / FTP / OPDS / S3 / URL / Wi‑Fi / Files からの取り込み

## 開発

Xcode で `MangaViewer/MangaViewer.xcodeproj` を開いてください。

```bash
python3 scripts/quality-gate.py
```
