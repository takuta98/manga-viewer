# MangaViewer

SwiftUI 製の iPhone 向け漫画ビューアです。外部 Swift パッケージは使いません。

## 基本機能

- 本棚（サンプル作品・進捗表示）
- 読む（スワイプ／端タップのページ送り）
- iPhone Duo（縦は単ページ、横に広いときだけ見開き）
- 作品を入手（Files から CBZ / ZIP / 画像）

## 開発

Xcode で `MangaViewer/MangaViewer.xcodeproj` を開いてください。

```bash
python3 scripts/quality-gate.py
```
