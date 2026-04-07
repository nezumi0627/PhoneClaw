# 第4部：高度な機能 + App Extension

---

## 26. 🔮 AR 拡張現実 — ARKit + RealityKit

### 権限設定
```
Info.plist: NSCameraUsageDescription（カメラ権限を共有）
デバイス要件: A12+ チップ（iPhone XS 以降）、LiDAR（iPhone 12 Pro 以降）
```

### 利用可能な API

| API | フレームワーク | 機能 |
|-----|--------------|------|
| `ARSession` | ARKit | AR セッションの管理 |
| `ARWorldTrackingConfiguration` | ARKit | 6DOF ワールドトラッキング |
| `ARPlaneDetection` | ARKit | 平面検出（水平・垂直）|
| `ARMeshAnchor` | ARKit | LiDAR によるメッシュスキャン |
| `ARFaceTrackingConfiguration` | ARKit | 前面カメラによる顔トラッキング |
| `ARBodyTrackingConfiguration` | ARKit | 全身スケルトントラッキング |
| `ARGeoTrackingConfiguration` | ARKit | 地理位置 AR アンカー |
| `ARAnchor` | ARKit | 3D 空間にアンカーを配置 |
| `ARRaycastQuery` | ARKit | レイキャスト（空間上の位置をタップ）|
| `RealityView` | RealityKit | 3D レンダリングビュー |
| `ModelEntity` | RealityKit | 3D モデルエンティティ |
| `Entity.generateText()` | RealityKit | 3D テキスト |

### Agent スキル

```
skill: ar_measure
  → ARKit 平面検出 + ユーザーが2点をマーク
  → 返却値: { distance: "1.82m" }
  → 「この壁の幅は1メートル82センチです」

skill: ar_scene_understand
  → ARKit ワールドトラッキング + 平面検出
  → 返却値: { planes: [{type:"floor", size:{w:4,h:3}},
                        {type:"wall", count:3}],
              meshVertices: 12400 }

skill: ar_place_info
  → 写真で物体を認識 → AR 空間に情報ラベルを配置
  → ユーザーには物体の隣に説明テキストが浮かんで見える

skill: ar_face_mesh
  → ARFaceTrackingConfiguration → 52 個の表情係数
  → 返却値: { blendShapes: { jawOpen: 0.3, eyeBlinkLeft: 0.0, ... } }

skill: ar_room_scan
  → LiDAR で部屋の3D 構造をスキャン
  → 部屋のサイズと家具の位置を推定して返却
```

---

## 27. 📹 画面収録 — ReplayKit

### 権限設定
```
システムがユーザー確認ダイアログを自動表示。Info.plist への記載不要
```

### 利用可能な API

| API | フレームワーク | 機能 |
|-----|--------------|------|
| `RPScreenRecorder.shared().startRecording()` | ReplayKit | 録画開始 |
| `RPScreenRecorder.shared().stopRecording()` | ReplayKit | 録画停止 |
| `RPScreenRecorder.shared().startCapture()` | ReplayKit | 画面をフレーム単位でキャプチャ |
| `RPPreviewViewController` | ReplayKit | 録画内容のプレビューと保存 |
| `RPBroadcastActivityViewController` | ReplayKit | ライブ配信 |

### Agent スキル

```
skill: screen_record_start   → 録画を開始
skill: screen_record_stop    → 録画を停止して保存
skill: screen_capture_frame  → 現在の画面フレームをキャプチャ → Gemma 4 で画面内容を分析
```

> **重要**: `startCapture` を使うと画面フレームを逐次取得できるため、
> Agent が画面上のコンテンツを「見て」理解することが可能になります！

---

## 28. 👁 集中モード — Focus ステータス

### 権限設定
```
Info.plist: NSFocusStatusUsageDescription
```

### 利用可能な API

| API | フレームワーク | 機能 |
|-----|--------------|------|
| `INFocusStatusCenter.default.focusStatus` | Intents | 現在の集中モード状態を取得 |
| `.isFocused` | Intents | 集中モードが有効かどうか |

### Agent スキル

```
skill: focus_status
  → INFocusStatusCenter.default.focusStatus
  → 返却値: { focused: true }
  → Agent はこの情報を元に動作を調整（集中モード中は通知を減らすなど）
```

---

## 29. 🔍 Spotlight 検索 — CoreSpotlight

### 権限: 不要

| API | フレームワーク | 機能 |
|-----|--------------|------|
| `CSSearchableItem` | CoreSpotlight | 検索可能な項目を作成 |
| `CSSearchableIndex.default().indexSearchableItems()` | CoreSpotlight | システム検索にインデックスを登録 |
| `CSSearchableItemAttributeSet` | CoreSpotlight | タイトル・説明・サムネイルを設定 |

### Agent スキル

```
skill: spotlight_index
  → Agent の会話・メモ・分析結果を Spotlight にインデックス登録
  → ユーザーがシステム検索から Agent が生成したコンテンツを見つけられる
```

---

## 30. 📊 WidgetKit — ホーム画面ウィジェット

### 権限: 不要（App Extension 経由）

| API | フレームワーク | 機能 |
|-----|--------------|------|
| `TimelineProvider` | WidgetKit | ウィジェットのデータを提供 |
| `Widget` | WidgetKit | ウィジェットの UI を定義 |
| `TimelineEntry` | WidgetKit | タイムラインエントリ |
| App Intents インタラクション | WidgetKit + App Intents | ウィジェットのボタン操作 |

### Agent スキル

```
Agent がホーム画面ウィジェットに表示する情報:
  - 今日の健康サマリー（歩数・心拍数・睡眠）
  - 次の予定
  - 未完了リマインダーの件数
  - 天気 + AI アドバイス
  - クイックアクションボタン（写真認識・音声入力・メモ）
```

---

## 31. 🏃 Live Activity — ロック画面のリアルタイム情報

### 権限: 不要

| API | フレームワーク | 機能 |
|-----|--------------|------|
| `ActivityKit.Activity.request()` | ActivityKit | Live Activity を開始 |
| `Activity.update()` | ActivityKit | リアルタイムデータを更新 |
| `Activity.end()` | ActivityKit | Live Activity を終了 |
| Dynamic Island UI | ActivityKit | Dynamic Island への表示 |

### Agent スキル

```
skill: live_activity_start
  → Agent がロック画面・Dynamic Island にリアルタイム情報を表示:
    - 会議のカウントダウン
    - 運動中のリアルタイムデータ
    - ナビゲーションの進捗
    - 「写真を分析中 (3/10)...」
```

---

## 32. 📞 VoIP — CallKit

### 権限: VoIP 関連 Entitlement が必要

| API | フレームワーク | 機能 |
|-----|--------------|------|
| `CXProvider` | CallKit | 着信・発信 UI の管理 |
| `CXCallController` | CallKit | 通話の発信・終了 |
| `CXCallAction` | CallKit | 通話操作（応答・切断・ミュート・保留）|

### Agent スキル

```
skill: call_display
  → Agent が開始する音声会話をネイティブ通話 UI で表示
  → ロック画面に着信画面が表示され、応答すると Agent との音声会話が始まる
```

---

## 33. ♿ アクセシビリティ — Accessibility

### 権限: 不要（アプリ内で自身の UI 階層を読み取る）

| API | フレームワーク | 機能 |
|-----|--------------|------|
| `UIAccessibility.post(notification:)` | UIKit | アクセシビリティ通知を送信 |
| `UIAccessibility.isVoiceOverRunning` | UIKit | VoiceOver が有効かどうか |
| `UIAccessibility.isReduceMotionEnabled` | UIKit | モーション低減が有効かどうか |
| `UIAccessibility.isBoldTextEnabled` | UIKit | 太字テキストが有効かどうか |
| `UIAccessibility.preferredContentSizeCategory` | UIKit | ユーザーのフォントサイズ設定 |

### Agent スキル

```
skill: accessibility_check
  → ユーザーのアクセシビリティ設定を確認
  → Agent が自動適応: VoiceOver モードでは音声応答を自動有効化
  → 大きなフォントモードでは UI を調整
```

---

## 34. ⏰ バックグラウンドタスク — BackgroundTasks

### 権限設定
```
Background Mode: Background fetch + Background processing
Info.plist: BGTaskSchedulerPermittedIdentifiers
```

| API | フレームワーク | 機能 |
|-----|--------------|------|
| `BGAppRefreshTask` | BackgroundTasks | 短いタスク（〜30秒）、定期的な更新 |
| `BGProcessingTask` | BackgroundTasks | 長いタスク、充電中や端末アイドル時に実行 |
| `BGTaskScheduler.shared.register()` | BackgroundTasks | バックグラウンドタスクを登録 |
| `BGTaskScheduler.shared.submit()` | BackgroundTasks | タスクリクエストを送信 |

### Agent スキル

```
skill: bg_refresh
  → BGAppRefreshTask: 定期的に天気・カレンダー変更・健康データを取得
  → 重要な変化があれば通知をプッシュ

skill: bg_process
  → BGProcessingTask: 夜間の充電中に実行:
    - 写真の整理・分類
    - 健康週次レポートの生成
    - ML モデルの更新
    - 新しい連絡先・カレンダーイベントのインデックス更新
```

---

## 35. 🗣 Siri 統合 — SiriKit + App Intents

### 権限設定
```
Info.plist: NSSiriUsageDescription
```

| API | フレームワーク | 機能 |
|-----|--------------|------|
| `INInteraction.donate()` | Intents | ユーザー行動を Siri に提供 |
| `INShortcut` | Intents | Siri ショートカットを作成 |
| `AppIntent` + `AppShortcutsProvider` | App Intents | Siri に自動登録 |

### Agent スキル

```
すべての Agent スキルを App Intents 経由で Siri に公開:
  「Hey Siri、PhoneClaw で今日の歩数を確認して」
  「Hey Siri、PhoneClaw で明日の午後に会議を設定して」
  「Hey Siri、PhoneClaw でコピーした内容を分析して」
```
