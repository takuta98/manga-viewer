# DuoSpread — iPhone Duo Manga Viewer (SwiftUI)

iPhone Duo の折りたたみ形状向け **SwiftUI** manga viewer。  
開いた Duo を単行本のように扱い、右 → 左（RTL）の見開きで読みます。

## Open in Xcode

```bash
open DuoSpread/DuoSpread.xcodeproj
```

1. Signing & Capabilities で自分の Team を選択
2. iPhone シミュレータ（または実機 / Duo）を選んで Run
3. 書庫の『夜の駅』を開く

最低: **iOS 17+** / Xcode 15+

## Features

| Pose | 説明 |
|------|------|
| 見開き (Open) | 左右二ペイン + 中央ヒンジ隙間 |
| 閉じ (Closed) | 外画面想定の単ページ |
| 卓上 (Table) | 上にページ、下に操作 |

- 日本語漫画 **RTL**（右=先、左タップで進む）
- 書庫 + サンプル 16 ページ同梱
- 進捗は `UserDefaults`（`ProgressStore`）

## Tests

Xcode で `DuoSpreadTests` を実行、または:

```bash
xcodebuild test \
  -project DuoSpread/DuoSpread.xcodeproj \
  -scheme DuoSpread \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Linux 上では Xcode がないためビルド不可。RTL ロジックの静的ミラー検証:

```bash
python3 scripts/verify_spread_index.py
```

## Layout

```
DuoSpread/
  DuoSpread.xcodeproj
  DuoSpread/
    DuoSpreadApp.swift
    ContentView.swift
    Models/ Views/ Services/
    Resources/SampleManga/night-station/
    Assets.xcassets/
  DuoSpreadTests/
```
