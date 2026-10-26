import Foundation

/// マンガビューアの画面文言。読書が主で、入手は副。
/// 使わない: 書庫 / 取り込み / 転送 / 入れる / 追加（主動詞として）
enum AppCopy {
    // MARK: 本棚
    static let libraryTitle = "本棚"
    static let continueReading = "続きを読む"
    static let libraryEmptyTitle = "まだ作品がありません"
    static let libraryEmptyBody = "右上の ＋ から作品を入手できます。本棚に入ったらすぐ読めます。"
    static let libraryEmptyCTA = "作品を入手"
    static let librarySearchPrompt = "作品やシリーズ名"
    static let librarySearchEmptyTitle = "見つかりません"
    static let librarySearchEmptyBody = "キーワードを変えてみてください"
    static let backToLibrary = "本棚"
    static let unread = "未読"
    static let finishedReading = "読了"
    static let volumeCountSuffix = "冊"
    static let pageCountSuffix = "ページ"
    static let newSeries = "シリーズを作る"
    static let seriesName = "シリーズ名"
    static let displayMode = "表示切替"
    static let sort = "並び替え"
    static let settings = "設定"
    static let more = "その他"
    static let cancel = "キャンセル"
    static let save = "保存"
    static let create = "作成"
    static let delete = "削除"
    static let rename = "名前を変更"
    static let moveToSeries = "シリーズへ移動"
    static let uncategorized = "未分類"
    static let info = "情報"
    static let titleField = "タイトル"
    static let openToRead = "読む"
    static let startOver = "最初から"
    static let resumeReading = "続きから"

    // MARK: 入手
    static let getWorks = "作品を入手"
    static let thisDevice = "この端末から"
    static let newConnection = "新しい場所に接続"
    static let fromFiles = "ファイル App から選ぶ"
    static let fromWiFi = "同じ Wi‑Fi の PC から送る"
    static let wifiTitle = "PC から送る"
    static let wifiInstruction = "同じ Wi‑Fi の PC のブラウザで、次のアドレスを開いてください。"
    static let wifiWaiting = "ファイルが届くのを待っています…"
    static let wifiReceived = "受信しました。本棚に反映しています…"
    static let wifiStarting = "起動中…"
    static let wifiThisDevice = "この端末"
    static let wifiStartFailed = "起動に失敗しました"
    static let wifiReceivedHTML = "<p>受け取りました。アプリの本棚に反映します。</p>"
    static let wifiUploadPageHTML = """
        <!DOCTYPE html><html lang="ja"><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <body style="font-family:-apple-system,sans-serif;padding:24px;max-width:480px;margin:auto;line-height:1.5">
        <h1 style="font-size:1.4rem">作品を送る</h1>
        <p>同じ Wi‑Fi の iPhone へ、CBZ / ZIP / 画像を送れます。送信後はアプリの本棚に入ります。</p>
        <form method="POST" enctype="multipart/form-data" action="/upload">
        <p><input type="file" name="file" accept=".cbz,.zip,.jpg,.jpeg,.png,image/*" style="width:100%"/></p>
        <p><button type="submit" style="font-size:1rem;padding:10px 16px">送る</button></p>
        </form></body></html>
        """
    static let wifiNoBoundary = "multipart 境界がありません"
    static let wifiNoFilePart = "ファイル部分が見つかりません"
    static let wifiNoFileEnd = "ファイル終端が見つかりません"
    static let wifiBadPartHeader = "パートヘッダが不正です"
    static let downloadFailedHTTP = "入手に失敗しました"
    static let savedConnections = "保存した場所"
    static let lastConnected = "前回つながった"
    static func connectKind(_ kind: String) -> String { kind }
    static let connect = "接続して開く"
    static let testConnection = "接続を確認"

    // MARK: 入手の進み
    static let downloads = "入手の進み"
    static let downloadActive = "入手中"
    static func downloadActiveCount(_ n: Int) -> String { "\(downloadActive) \(n)件" }
    static let downloadEmptyTitle = "いま入手中のものはありません"
    static let downloadEmptyBody = "作品を選ぶと、ここに進み具合が出ます。終わった作品はここからすぐ読めます。"
    static let downloading = "入手中"
    static let cancelDownload = "中止"
    static let cancelAllDownloads = "すべて中止"
    static let cancelling = "中止しています…"
    static let cancelled = "中止しました"
    static let clearFinished = "完了を消す"
    static let done = "完了"
    static let downloadStarted = "入手を始めました"
    static let downloadFinished = "本棚に入りました"
    static let downloadFailed = "入手に失敗しました"
    static let unpacking = "展開しています…"
    static let zipExtractFailed = "ZIPの展開に失敗しました"
    static let collecting = "ファイルを調べています…"
    static let downloadingItem = "受け取っています…"
    static let queued = "入手中"
    static let alreadyHave = "同じタイトルが本棚にあります"
    static let readNow = "今すぐ読む"
    static let readyToRead = "読める作品"
    static let tapToReadHint = "行をタップするか「今すぐ読む」で開けます"

    // MARK: リモート
    static let browseSearchPrompt = "このフォルダ内を探す"
    static let browseSearchEmpty = "一致する項目がありません"
    static let clearSearch = "検索をやめる"
    static let downloadThisFolder = "このフォルダの作品を入手"
    static let downloadNewWorks = "まだない作品を入手"
    static func downloadNewWorksCount(_ n: Int) -> String { "まだない作品を入手（\(n)）" }
    static let downloadingFolder = "入手しています…"
    static let emptyFolder = "このフォルダは空です"
    static let onShelf = "本棚にあり"
    static let getThisWork = "入手"
    static let browseFailed = "一覧を取得できません"
    static let retry = "再試行"
    static let close = "閉じる"
    static let back = "戻る"
    static let loading = "読み込み中…"
    static let errorTitle = "エラー"
    static let ok = "OK"

    // MARK: 読書
    static let readingSettings = "表示"
    static let thumbnails = "ページ一覧"
    static let bookmark = "しおり"
    static let bookmarkAdd = "しおりを付ける"
    static let bookmarkRemove = "しおりを外す"
    static let bookmarkList = "しおり一覧"
    static let bookmarkEmpty = "しおりはまだありません"
    static let bookmarkEmptyBody = "読書中にしおりを付けると、ここに並びます"
    static let bookmarkClearAll = "しおりをすべて外す"
    static let bookmarkClearAllMessage = "この作品のしおりをすべて外します。読書位置はそのままです。"
    static let bookmarkListFooter = "行をタップするとそのページから読めます"
    static let bookmarkHereSection = "いまここ"
    static let bookmarkOtherSection = "ほかのしおり"
    static func bookmarkPagesAhead(_ n: Int) -> String { "あと \(n) \(pageCountSuffix)" }
    static func bookmarkPagesBehind(_ n: Int) -> String { "\(n) \(pageCountSuffix)前" }
    static let seriesEmptyTitle = "このシリーズは空です"
    static let seriesEmptyBody = "作品を入手するか、本棚からこのシリーズへ移せます。"
    static let seriesEmptyGetWorks = "作品を入手"
    static let backToAllWorks = "本棚に戻る"
    static let deleteSeriesTitle = "シリーズを削除"
    static let deleteVolumeTitle = "作品を削除"
    static func deleteSeriesMessage(_ name: String) -> String {
        "「\(name)」を削除します。中の作品は未分類に移します。"
    }
    static func deleteVolumeMessage(_ title: String) -> String {
        "「\(title)」を削除します。この操作は取り消せません。"
    }
    static let readingInProgress = "読書中"
    static let remoteSectionFolders = "フォルダ"
    static let remoteSectionWorks = "作品"
    static let remoteSectionNewWorks = "まだない作品"
    static let remoteSectionOnShelf = "本棚にある作品"
    static let remoteSectionOther = "その他"
    static func remoteWorksSummary(new: Int, onShelf: Int, reading: Int = 0, marks: Int = 0) -> String {
        var parts = ["作品 \(new + onShelf) 冊", "未入手 \(new)", "本棚 \(onShelf)"]
        if reading > 0 { parts.append("\(continueReading) \(reading)") }
        if marks > 0 { parts.append("\(bookmark) \(marks)") }
        return parts.joined(separator: " · ")
    }
    static let onShelfReadHint = "本棚にある作品はタップで読めます。"
    static let openFolder = "フォルダを開く"
    static let unsupportedFile = "非対応"
    static let emptyFolderHint = "上の階層に戻るか、別のフォルダを開いてください。"
    static let currentPageLabel = "いま読んでいるページ"
    static let hereNow = "いまここ"
    static func resumePrompt(page: Int, total: Int) -> String {
        "前回は \(page) / \(total) \(pageCountSuffix)です。続きから読みますか？"
    }
    static let getWorksStayHint = "入手を始めてもこの画面のままです。進み具合は下に出ます。"
    static let downloadFinishedReadHint = "本棚に入りました。下のチップか入手の進みから読めます。"
    static let savedConnectionsHint = "よく使う NAS やサーバーを保存すると、次回からすぐ開けます。"
    static let settingsReadingFooter = "ここは新しく入手した作品の初期値です。開いている作品の読み方は、読書画面の表示メニューから変えられます。"
    static let layoutExplain = "縦画面は常に1ページ。横に広く開いたときだけ見開きになります。"
    static let noPagesTitle = "ページがありません"
    static let noPagesBody = "この作品には表示できるページがありません。"
    static let untitled = "無題"
    static let unsupportedFormat = "未対応の形式です"
    static let noImagePages = "画像ページが見つかりません"
    static let invalidURL = "URLが不正です"
    static let remoteUnsupported = "この形式は未対応です"
    static let remoteNotConfigured = "接続情報が不足しています"
    static let pickFolderFirst = "フォルダを選んでから作品を入手してください"
    static let smbNoFolders = "接続はできましたが、見えるフォルダがありません。ユーザー権限を確認してください。"
    static let smbClientInitFailed = "SMB クライアントを初期化できません（IP の形式を確認してください）"
    static let opdsFetchFailed = "OPDS フィードの取得に失敗しました"
    static let opdsNotAtom = "OPDS（Atom）フィードではありません"
    static let opdsDownloadFailed = "OPDS からの入手に失敗しました"
    static let webdavInitFailed = "WebDAV クライアントを初期化できません"
    static let ftpInitFailed = "FTP クライアントを初期化できません"
    static func smbLoginFailed(_ detail: String) -> String {
        "ログインできませんでした。ユーザー名とパスワードを確認してください。\n\(detail)"
    }
    static func smbFolderNotFound(_ detail: String) -> String {
        "フォルダが見つかりません。\n\(detail)"
    }
    static func smbUnreachable(_ detail: String) -> String {
        "NAS に届きません。同じ Wi‑Fi か、IP が合っているか、ローカルネットワーク許可を確認してください。\n\(detail)"
    }
    static func smbConnectFailed(_ detail: String) -> String {
        "接続できませんでした。IP と、NAS 側の SMB が有効かを確認してください。\n\(detail)"
    }
    static func smbConnectError(_ detail: String) -> String {
        "接続エラー: \(detail)"
    }
    static let libraryLoadFailed = "本棚データの読み込みに失敗しました。既存データは上書きしていません。"
    static let librarySaveFailed = "本棚の保存に失敗しました。"
    static let connectSuccessHint = "接続に成功しました。このまま「接続して開く」で作品を選べます。"
    static let addSourceFooter = "つながったらフォルダを選んで作品を入手します。"
    static let smbShareFooter = "空のままでも接続できます。後からフォルダを選べます。"
    static let displayName = "表示名"
    static let urlField = "URL"
    static let hostOrIP = "ホスト / IP"
    static let shareFolderOptional = "共有フォルダ名（任意）"
    static let pathOrBucket = "パス / バケット"
    static let region = "リージョン"
    static let bucket = "バケット"
    static let username = "ユーザー名"
    static let password = "パスワード"
    static let useTLS = "TLS を使う"
    static func portLabel(_ port: Int) -> String { "ポート: \(port)" }
    static let jumpToPage = "このページへ"
    static let fit = "画像の合わせ方"
    static let brightness = "明るさ"
    static let readingDirection = "読み方"
    static let doneReadingSettings = "完了"

    // MARK: 設定
    static let settingsTitle = "設定"
    static let settingsReadingDefaults = "新しい作品の読み方"
    static let settingsDisplay = "表示"
    static let settingsLibrary = "本棚"
    static let settingsLibraryFooter = "「読み進み」は続きを読む作品を先に並べます。同じ進みならしおりが多い順です。"
    static let keepScreenOn = "読んでいる間はスリープしない"
    static let coverAlone = "表紙を単独表示"
    static let pageLayout = "ページ"
    static let pageTurn = "ページ送り"

    // MARK: 読み方ラベル
    static let fitWidth = "幅に合わせる"
    static let fitHeight = "高さに合わせる"
    static let fitScreen = "画面に合わせる"
    static let layoutSingle = "単ページ"
    static let layoutSpread = "見開き"
    static let layoutWebtoon = "縦スクロール"
    static let turnSlide = "スライド"
    static let turnCurl = "ページめくり"
    static let sortRecent = "最近"
    static let sortTitle = "タイトル"
    static let sortProgress = "読み進み"
    static let displayList = "リスト"
    static let displayGrid = "グリッド"
    static let directionRTL = "右開き（日本語）"
    static let directionLTR = "左開き"
    static let directionRTLShort = "右開き"
    static let directionLTRShort = "左開き"
    static let kindSMB = "SMB（NAS）"
    static let kindWebDAV = "WebDAV"
    static let kindSFTP = "SFTP"
    static let kindFTP = "FTP"
    static let kindOPDS = "OPDS"
    static let kindS3 = "S3互換"
    static let kindHTTP = "URL"
}
