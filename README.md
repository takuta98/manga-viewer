# manga-viewer

iPhone Duo 向け SwiftUI manga viewer。

参考にした取得経路・機能の系統: **Andrea / Comink / KedaReader**（SMB・WebDAV・OPDS・クラウド/Files）、および **ComicFlow**（ローカル RTL 見開き）。

## 開き方

```bash
open MangaViewer/MangaViewer.xcodeproj
```

初回は Xcode が Swift Package（AMSMB2 / Citadel）を解決します。iOS 17+。

## ファイルの入れ方（書庫右上 +）

| 方法 | 用途 |
|------|------|
| **Files / iCloud / クラウド** | Files に出る iCloud・Dropbox・Google Drive・OneDrive・Files の SMB 接続など |
| **SMB (NAS)** | Synology / QNAP / Windows 共有 |
| **WebDAV** | NAS WebDAV / Nextcloud |
| **SFTP** | SSH ファイル転送 |
| **FTP** | PASV FTP |
| **OPDS / Komga / Kavita** | OPDS カタログ |
| **S3 / MinIO** | S3 互換オブジェクトストレージ |
| **URL ダウンロード** | 直リンク CBZ/PDF 等 |
| **Wi-Fi 転送** | 同一 LAN のブラウザから Upload |

対応取り込み形式: **CBZ / ZIP / PDF / 画像**。CBR/RAR/7z は未デコード（変換が必要）。

## 主な機能

- 書庫: 検索・並び替え・改名・削除・進捗
- リーダー: 見開き / 単ページ / 縦スクロール、RTL/LTR、表紙単独、ズーム、しおり、サムネ、明るさ、スリープ防止
- Duo ポーズ: 見開き / 閉じ / 卓上
- ComicInfo.xml のタイトル・方向を反映
