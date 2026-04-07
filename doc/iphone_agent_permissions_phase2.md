# 第二部: ユーザーデータ権限（ユーザー認証が必要）

---

## 7. 📸 写真ライブラリ — PhotoKit (Photos Framework)

### 権限設定
```
Info.plist: NSPhotoLibraryUsageDescription          （読み取り）
Info.plist: NSPhotoLibraryAddUsageDescription        （書き込みのみ）
```

> iOS 14+ では「一部の写真のみ選択」の制限アクセスモード (PHAccessLevel.limited) に対応

### 呼び出し可能 API

| API | フレームワーク | 機能 |
|-----|------|------|
| `PHAsset.fetchAssets()` | Photos | 全写真/動画アセットの照会 |
| `PHAsset` 属性 | Photos | 作成日・位置情報・サイズ・メディアタイプ・お気に入り状態の取得 |
| `PHImageManager.requestImage()` | Photos | 指定サイズの画像データ取得 |
| `PHImageManager.requestAVAsset()` | Photos | 動画の AVAsset 取得 |
| `PHAssetCollection.fetchAssetCollections()` | Photos | アルバム一覧の照会 |
| `PHAssetCreationRequest` | Photos | 新しい写真をアルバムに保存 |
| `PHAssetChangeRequest` | Photos | 写真のメタデータ変更（お気に入り・非表示など）|
| `PHFetchOptions` (predicate/sortDescriptors) | Photos | 日付・位置・メディアタイプでフィルタ |
| `PHPhotoLibrary.shared().performChanges()` | Photos | バッチ変更操作 |

### Agent Skills

```
skill: photos_search
  パラメータ: { query: "先週のレシート", type: "image", dateRange: "last_week" }
  → PHFetchOptions で日付フィルタ 
  → PHImageManager でサムネイル取得 → Gemma 4 で一括画像理解
  → 返り値: { matches: [{ id: "...", date: "2026-03-28", 
            description: "スターバックスのレシート ¥580" }] }

skill: photos_recent
  パラメータ: { count: 10 }
  → 最新 N 枚の写真を取得
  → 返り値: [{ id, date, location, thumbnail }]

skill: photos_save
  パラメータ: { image: UIImage }
  → PHAssetCreationRequest でアルバムに保存
  → 返り値: { saved: true, assetId: "..." }

skill: photos_by_location
  パラメータ: { location: "東京", radius: 5000 }
  → PHFetchOptions + CLLocation predicate
  → 場所でフィルタされた写真一覧を返す

skill: photos_organize
  → 写真を一括取得 → Gemma 4 で分類（風景/人物/文書/食べ物/スクリーンショット）
  → 分類の提案を返す: { categories: { food: [ids], docs: [ids], ... } }

skill: photo_edit_metadata
  パラメータ: { assetId: "...", favorite: true }
  → PHAssetChangeRequest でメタデータを変更
  → 返り値: { updated: true }
```

### 強力なシナリオ

```
ユーザー: 「先週撮った領収書を探してください」
  → photos_search(query: "領収書", dateRange: "last_week")
  → Gemma 4 がサムネイルを1枚ずつ分析して領収書を識別
  → 「見つかりました。3月28日撮影の領収書、金額¥12,800、
     発行元: ○○テクノロジー株式会社です。詳細情報を抽出しましょうか？」

ユーザー: 「今月の写真を整理してください」
  → photos_organize → Gemma 4 が一括分類
  → 「今月は合計 247 枚の写真があります:
     - 自撮り/人物: 45枚
     - 食べ物: 32枚  
     - 風景: 28枚
     - スクリーンショット: 89枚（削除を推奨）
     - 文書/領収書: 18枚
     - その他: 35枚
     スクリーンショットを別のアルバムに移動しましょうか？」
```

---

## 8. 👤 連絡先 — Contacts Framework

### 権限設定
```
Info.plist: NSContactsUsageDescription
```

### 呼び出し可能 API

| API | フレームワーク | 機能 |
|-----|------|------|
| `CNContactStore.requestAccess()` | Contacts | 連絡先権限の要求 |
| `CNContactStore.unifiedContacts(matching:)` | Contacts | 条件による連絡先検索 |
| `CNContactStore.enumerateContacts()` | Contacts | 全連絡先の列挙 |
| `CNContact` 属性 | Contacts | 名前・電話・メール・住所・誕生日・会社・肩書き・写真・SNSアカウント |
| `CNContactFormatter` | Contacts | ローカライズされた連絡先名のフォーマット |
| `CNSaveRequest.add()` | Contacts | 新しい連絡先の作成 |
| `CNSaveRequest.update()` | Contacts | 連絡先情報の更新 |
| `CNSaveRequest.delete()` | Contacts | 連絡先の削除 |
| `CNContactFetchRequest` | Contacts | 取得するフィールドの指定（パフォーマンス最適化）|
| `CNGroup` / `CNContainer` | Contacts | 連絡先グループ管理 |

### Agent Skills

```
skill: contacts_search
  パラメータ: { name: "田中太郎" } または { company: "ソフトバンク" }
  → CNContactStore.unifiedContacts(matching: predicate)
  → 返り値: { name: "田中太郎", phone: "090xxxx5678", 
            email: "tanaka@xxx.com", company: "ソフトバンク" }

skill: contacts_create
  パラメータ: { name: "鈴木一郎", phone: "080xxxx1234", company: "ドコモ" }
  → CNSaveRequest.add(contact)
  → 返り値: { created: true, contactId: "..." }

skill: contacts_update
  パラメータ: { contactId: "...", phone: "新しい番号" }
  → CNSaveRequest.update()
  → 返り値: { updated: true }

skill: contacts_list_all
  → CNContactStore.enumerateContacts()
  → 返り値: { total: 352, contacts: [...] }

skill: contacts_birthday_upcoming
  → 全連絡先を列挙 → 7日以内の誕生日をフィルタ
  → 返り値: [{ name: "お母さん", birthday: "4月5日", daysUntil: 2 }]
```

### 強力なシナリオ

```
ユーザー: [名刺を撮影]
  → camera_capture → ocr_extract → Gemma 4 が名刺を解析
  → contacts_create(name: "山田花子", phone: "080...", 
                     company: "株式会社○○", title: "プロダクトマネージャー")
  → 「山田花子さんの情報を連絡先に保存しました:
     山田花子 | 株式会社○○ プロダクトマネージャー
     電話: 080xxxx7890 | メール: yamada@company.co.jp」

ユーザー: 「今週誰かの誕生日はありますか？」
  → contacts_birthday_upcoming
  → 「明後日（4月5日）はお母さんの誕生日です！リマインダーを設定しましょうか？」
```

---

## 9. 📅 カレンダー — EventKit

### 権限設定
```
Info.plist: NSCalendarsFullAccessUsageDescription      （読み書き）
Info.plist: NSCalendarsWriteOnlyAccessUsageDescription  （書き込みのみ）
```

### 呼び出し可能 API

| API | フレームワーク | 機能 |
|-----|------|------|
| `EKEventStore.requestFullAccessToEvents()` | EventKit | カレンダーの完全権限を要求 |
| `EKEventStore.events(matching:)` | EventKit | 日付範囲内のイベントを照会 |
| `EKEvent(eventStore:)` | EventKit | 新しいカレンダーイベントを作成 |
| `EKEvent` 属性 | EventKit | タイトル・開始/終了時刻・場所・メモ・URL・繰り返しルール・リマインダー |
| `EKAlarm` | EventKit | イベントリマインダー（時間オフセットまたは絶対時刻）|
| `EKRecurrenceRule` | EventKit | 繰り返しルール（毎日/毎週/毎月/カスタム）|
| `EKEventStore.save()` | EventKit | イベントの保存 |
| `EKEventStore.remove()` | EventKit | イベントの削除 |
| `EKCalendar` | EventKit | カレンダーの管理（仕事/個人/祝日など）|
| `EKEventStore.calendars(for: .event)` | EventKit | 全カレンダー一覧の取得 |

### Agent Skills

```
skill: calendar_query
  パラメータ: { from: "today", to: "next_week" }
  → EKEventStore.events(matching: predicate)
  → 返り値: [{ title: "製品レビュー", start: "2026-04-04 14:00",
             end: "15:00", location: "3F会議室", calendar: "仕事" }]

skill: calendar_create
  パラメータ: { title: "田中さんと食事", date: "明日", time: "18:30",
               location: "和食さと渋谷店", alert: "30min_before" }
  → EKEvent + EKAlarm を作成
  → 返り値: { created: true, eventId: "..." }

skill: calendar_check_free
  パラメータ: { date: "2026-04-05" }
  → 当日のイベントを照会 → 空き時間帯を計算
  → 返り値: { busy: ["9:00-10:00", "14:00-16:00"],
            free: ["10:00-14:00", "16:00-18:00"] }

skill: calendar_recurring
  パラメータ: { title: "週次ミーティング", every: "weekly", day: "monday", time: "10:00" }
  → EKRecurrenceRule + EKEvent
  → 返り値: { created: true, recurrence: "毎週月曜日 10:00" }

skill: calendar_delete
  パラメータ: { eventId: "..." }
  → EKEventStore.remove()
  → 返り値: { deleted: true }
```

---

## 10. ⏰ リマインダー — EventKit (Reminders)

### 権限設定
```
Info.plist: NSRemindersFullAccessUsageDescription
```

### 呼び出し可能 API

| API | フレームワーク | 機能 |
|-----|------|------|
| `EKEventStore.requestFullAccessToReminders()` | EventKit | リマインダー権限の要求 |
| `EKEventStore.fetchReminders(matching:)` | EventKit | リマインダーの照会 |
| `EKReminder(eventStore:)` | EventKit | リマインダーの作成 |
| `EKReminder` 属性 | EventKit | タイトル・メモ・優先度・完了状態・期限日 |
| `EKAlarm` | EventKit | 時間リマインダーまたは位置リマインダー |
| `EKAlarm(relativeOffset:)` | EventKit | 相対時間リマインダー |
| `EKAlarm(structuredLocation:proximity:)` | EventKit | 特定の場所への到着/退出時のリマインダー |
| `EKEventStore.save()` / `.remove()` | EventKit | リマインダーの保存/削除 |

### Agent Skills

```
skill: reminders_query
  パラメータ: { list: "買い物リスト", completed: false }
  → fetchReminders → 未完了リマインダーの一覧を返す

skill: reminders_create
  パラメータ: { title: "牛乳を買う", list: "買い物リスト", 
               dueDate: "明日", priority: 1 }
  → EKReminder を作成 + 期限日を設定
  → 返り値: { created: true, id: "..." }

skill: reminders_location_based
  パラメータ: { title: "宅配便を受け取る", location: "マンション入口",
               trigger: "arriving" }
  → EKAlarm(structuredLocation:, proximity: .enter)
  → 指定場所に到着した時にリマインダーをトリガー

skill: reminders_complete
  パラメータ: { id: "..." }
  → reminder.isCompleted = true → save
  → 返り値: { completed: true }

skill: reminders_batch_create
  パラメータ: { list: "出張チェックリスト", items: ["モバイルバッテリー","身分証","ノートPC"] }
  → リマインダーを一括作成
  → 返り値: { created: 3, list: "出張チェックリスト" }
```

---

## 11. ❤️ ヘルスデータ — HealthKit

### 権限設定
```
Info.plist: NSHealthShareUsageDescription    （読み取り）
Info.plist: NSHealthUpdateUsageDescription   （書き込み）
Entitlement: com.apple.developer.healthkit
Background Mode: Background fetch （バックグラウンドでのヘルスデータ更新が必要な場合）
```

> HealthKit の権限粒度は非常に細かく、各データタイプ（歩数/心拍数/睡眠など）を個別に認証する必要があります

### 呼び出し可能 API

| API / データタイプ | フレームワーク | 機能 |
|-----|------|------|
| `HKHealthStore.requestAuthorization()` | HealthKit | タイプ別に権限を要求 |
| `HKQuantityType(.stepCount)` | HealthKit | 歩数 |
| `HKQuantityType(.heartRate)` | HealthKit | 心拍数 (bpm) |
| `HKQuantityType(.activeEnergyBurned)` | HealthKit | 活動消費カロリー |
| `HKQuantityType(.distanceWalkingRunning)` | HealthKit | 歩行・走行距離 |
| `HKQuantityType(.bloodOxygenSaturation)` | HealthKit | 血中酸素濃度 (SpO2) |
| `HKQuantityType(.bodyMass)` | HealthKit | 体重 |
| `HKQuantityType(.height)` | HealthKit | 身長 |
| `HKQuantityType(.bodyMassIndex)` | HealthKit | BMI |
| `HKQuantityType(.bloodPressureSystolic/Diastolic)` | HealthKit | 血圧 |
| `HKQuantityType(.bloodGlucose)` | HealthKit | 血糖値 |
| `HKQuantityType(.bodyTemperature)` | HealthKit | 体温 |
| `HKQuantityType(.dietaryEnergyConsumed)` | HealthKit | 食事カロリー摂取量 |
| `HKQuantityType(.dietaryWater)` | HealthKit | 水分摂取量 |
| `HKCategoryType(.sleepAnalysis)` | HealthKit | 睡眠分析（入眠/浅眠/深眠/REM）|
| `HKCategoryType(.mindfulSession)` | HealthKit | マインドフルネス瞑想記録 |
| `HKWorkout` | HealthKit | ワークアウト記録（種類/時間/消費）|
| `HKStatisticsQuery` | HealthKit | 統計照会（合計/平均/最大/最小）|
| `HKStatisticsCollectionQuery` | HealthKit | 時間帯別統計（日別/週別の歩数トレンド）|
| `HKAnchoredObjectQuery` | HealthKit | 増分照会（新規追加データ）|
| `HKObserverQuery` | HealthKit | データ変化の監視 |
| `HKQuantitySample` | HealthKit | ヘルスデータサンプルの書き込み |

### Agent Skills

```
skill: health_steps
  パラメータ: { period: "today" | "this_week" | "this_month" }
  → HKStatisticsQuery(stepCount, sum)
  → 返り値: { steps: 8432, goal: 10000, progress: "84%" }

skill: health_heart_rate
  パラメータ: { period: "today" }
  → HKStatisticsQuery(heartRate, min/max/avg)
  → 返り値: { resting: 62, average: 75, max: 142, 
            readings: [{ time: "08:30", value: 68 }, ...] }

skill: health_sleep
  パラメータ: { date: "last_night" }
  → HKSampleQuery(sleepAnalysis)
  → 返り値: { total: "7時間12分", inBed: "7時間45分",
            deep: "1時間30分", rem: "1時間48分", light: "3時間54分",
            awake: "33分", efficiency: "93%" }

skill: health_workout_log
  パラメータ: { type: "running", duration: 30, distance: 5.2 }
  → HKWorkout サンプルを作成
  → 返り値: { logged: true, calories: 320 }

skill: health_weight_trend
  パラメータ: { period: "last_3_months" }
  → HKStatisticsCollectionQuery(bodyMass, weekly)
  → 返り値: { trend: "減少", data: [{week: "W1", kg: 72.5}, ...],
            change: "-2.3kg" }

skill: health_water_log
  パラメータ: { ml: 250 }
  → HKQuantitySample(dietaryWater) を書き込む
  → 返り値: { logged: true, todayTotal: "1,750ml", goal: "2,000ml" }

skill: health_blood_oxygen
  → HKSampleQuery(bloodOxygenSaturation, latest)
  → 返り値: { spo2: 98, time: "10:30" }

skill: health_comprehensive_report
  → 並列照会: 歩数 + 心拍数 + 睡眠 + ワークアウト + 体重
  → Gemma 4 が総合分析
  → 自然言語による健康レポートを返す
```

### 強力なシナリオ

```
ユーザー: 「今日の体調はどうですか？」
  → health_comprehensive_report
  → Gemma 4 が総合分析:
  → 「全体的に良好な状態です:
     😴 昨夜は7時間12分の睡眠、深眠1.5時間、品質スコア88点
     🚶 本日 8,432 歩（目標の84%）
     ❤️ 安静時心拍数62、正常範囲内
     💧 水分摂取1,250ml、あと750ml必要
     提案: 午後にあと3杯の水を飲み、夜に20分散歩して目標達成を」

ユーザー: 「記録しておいてください、さっき5km走りました」
  → health_workout_log(type: "running", distance: 5.0)
  → 「記録しました: ランニング5km、推定消費約310kcal、今週の累計ランニング15km、素晴らしい！」
```

---

## 12. 🎵 音楽ライブラリ — MediaPlayer + MusicKit

### 権限設定
```
Info.plist: NSAppleMusicUsageDescription
```

### 呼び出し可能 API

| API | フレームワーク | 機能 |
|-----|------|------|
| `MPMediaQuery.songs()` | MediaPlayer | 全ローカル楽曲の照会 |
| `MPMediaQuery` (predicate) | MediaPlayer | アーティスト/アルバム/ジャンルでフィルタ |
| `MPMusicPlayerController.systemMusicPlayer` | MediaPlayer | システム音楽プレーヤーの操作 |
| `.play()` / `.pause()` / `.skipToNextItem()` | MediaPlayer | 再生コントロール |
| `.nowPlayingItem` | MediaPlayer | 現在再生中の楽曲情報 |
| `.setQueue(with:)` | MediaPlayer | 再生キューの設定 |
| `MPMediaPickerController` | MediaPlayer | システム楽曲選択 UI |
| `MusicCatalogSearchRequest` | MusicKit | Apple Music カタログの検索 |
| `MusicSubscription` | MusicKit | ユーザーのサブスクリプション状態 |

### Agent Skills

```
skill: music_play
  パラメータ: { query: "宇多田ヒカル" | genre: "jazz" | album: "First Love" }
  → MPMediaQuery でフィルタ → setQueue → play()
  → 返り値: { playing: "First Love", artist: "宇多田ヒカル", album: "First Love" }

skill: music_control
  パラメータ: { action: "pause" | "next" | "previous" | "volume_up" }
  → MPMusicPlayerController でコントロール
  → 返り値: { action: "paused" }

skill: music_now_playing
  → nowPlayingItem
  → 返り値: { title: "First Love", artist: "宇多田ヒカル", duration: "5:53", 
            progress: "2:15" }

skill: music_search_library
  パラメータ: { artist: "椎名林檎" }
  → MPMediaQuery
  → 返り値: { songs: [{ title: "ここでキスして。", album: "無罪モラトリアム" }, ...], total: 23 }
```

---

## 13. 📁 ファイルアクセス — FileManager + UIDocumentPickerViewController

### 権限設定
```
特別な権限不要 — アプリサンドボックス内のファイルを自由に読み書き
UIDocumentPickerViewController — ユーザーが手動でファイルを選択（権限宣言不要）
```

### 呼び出し可能 API

| API | フレームワーク | 機能 |
|-----|------|------|
| `FileManager.default` | Foundation | サンドボックス内ファイルの CRUD |
| `.contentsOfDirectory(atPath:)` | Foundation | ディレクトリ内容の一覧 |
| `.createFile()` / `.createDirectory()` | Foundation | ファイル/ディレクトリの作成 |
| `.removeItem(atPath:)` | Foundation | ファイルの削除 |
| `.copyItem()` / `.moveItem()` | Foundation | ファイルのコピー/移動 |
| `.attributesOfItem()` | Foundation | ファイル属性の取得（サイズ/日付）|
| `UIDocumentPickerViewController` | UIKit | iCloud/ローカルファイルのユーザー選択 |
| `Data(contentsOf:)` | Foundation | ファイル内容の読み取り |
| `data.write(to:)` | Foundation | ファイル内容の書き込み |
| `JSONSerialization` / `JSONDecoder` | Foundation | JSON の読み書き |
| `QLPreviewController` | QuickLook | PDF/Office/画像ファイルのプレビュー |

### Agent Skills

```
skill: file_pick
  → UIDocumentPickerViewController
  → ユーザーがファイルを選択 → ファイル URL を返す
  → 内容を読み込む → Gemma 4 が分析

skill: file_read
  パラメータ: { path: "sandbox://Documents/notes.txt" }
  → Data(contentsOf:) → String
  → 返り値: { content: "ファイルの内容...", size: "2.3KB" }

skill: file_write
  パラメータ: { path: "Documents/summary.md", content: "..." }
  → data.write(to:)
  → 返り値: { written: true, path: "..." }

skill: file_list
  パラメータ: { directory: "Documents" }
  → contentsOfDirectory
  → 返り値: [{ name: "notes.txt", size: "2.3KB", modified: "..." }]

skill: file_analyze_pdf
  → file_pick（ユーザーが PDF を選択）→ テキスト抽出 → Gemma 4 が要約
  → 返り値: { pages: 12, summary: "この契約書の主な内容は..." }
```

---

> **フェーズ2完了** — ユーザーデータ権限 7 種、**70+ の呼び出し可能 API**
>
> 次のフェーズ: システム統合機能（クリップボード・通知・HomeKit・Shortcuts・アクセシビリティ・ネットワークなど）
