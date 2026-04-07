# 第3部：システム統合能力

---

## 14. 📋 クリップボード — UIPasteboard

### 権限設定
```
Info.plist への宣言不要
iOS 14+: 読み取り時、画面上部に通知バナーを表示
iOS 16+: アプリをまたいだ貼り付け時、ユーザー確認ダイアログが必要
```

### 利用可能な API

| API | フレームワーク | 機能 |
|-----|--------------|------|
| `UIPasteboard.general.string` | UIKit | クリップボードのテキストを読み取り/書き込み |
| `UIPasteboard.general.image` | UIKit | クリップボードの画像を読み取り/書き込み |
| `UIPasteboard.general.url` | UIKit | クリップボードの URL を読み取り |
| `UIPasteboard.general.hasStrings` | UIKit | テキストの有無を確認（通知を発火しない）|

### Agent スキル

```
skill: clipboard_read    → クリップボードの内容を読み取り・分析
skill: clipboard_write   → 翻訳・整形した結果をクリップボードに書き込み
skill: clipboard_analyze → 読み取り → Gemma 4 が種別（テキスト/URL/画像）を自動判定 → 要約・翻訳
```

---

## 15. 🔔 通知 — UserNotifications

### 権限設定
```
UNUserNotificationCenter.requestAuthorization() による認可が必要
```

### 利用可能な API

| API | フレームワーク | 機能 |
|-----|--------------|------|
| `UNMutableNotificationContent` | UserNotifications | 通知コンテンツ（タイトル・本文・サウンド・添付）|
| `UNTimeIntervalNotificationTrigger` | UserNotifications | 一定時間後にトリガー |
| `UNCalendarNotificationTrigger` | UserNotifications | カレンダー日時でトリガー |
| `UNLocationNotificationTrigger` | UserNotifications | 場所でトリガー |
| `UNNotificationAction` / `UNNotificationCategory` | UserNotifications | 操作ボタン付き通知 |
| `UNNotificationAttachment` | UserNotifications | リッチメディア添付 |

### Agent スキル

```
skill: notification_send        → 時刻指定・遅延ローカル通知を送信
skill: notification_schedule    → 繰り返し通知（毎日の服薬リマインダーなど）
skill: notification_location    → 特定の場所に到着/離れたときに通知
skill: notification_interactive → 操作ボタン付き通知
```

---

## 16. 🏠 スマートホーム — HomeKit

### 権限設定
```
Info.plist: NSHomeKitUsageDescription
Entitlement: com.apple.developer.homekit
```

### 利用可能な API

| API | フレームワーク | 機能 |
|-----|--------------|------|
| `HMHomeManager` | HomeKit | すべてのホームを取得 |
| `HMAccessory` | HomeKit | アクセサリデバイス（照明・エアコン・ロックなど）|
| `HMCharacteristic.writeValue()` | HomeKit | デバイスを制御 |
| `HMCharacteristic.readValue()` | HomeKit | デバイスの状態を読み取り |
| `HMActionSet` | HomeKit | シーンを実行 |
| `HMEventTrigger` / `HMTimerTrigger` | HomeKit | オートメーション |

### Agent スキル

```
skill: home_list_devices  → すべての部屋とデバイスを一覧表示
skill: home_control       → デバイスを制御（照明オン・温度調整・カーテン閉めなど）
skill: home_read_status   → デバイスの状態を読み取り
skill: home_scene         → シーンを実行（「帰宅モード」など）
skill: home_automation    → オートメーションを作成（日没に照明を点灯など）
skill: home_sensor_read   → 温湿度センサーの値を読み取り
```

---

## 17. ⌨️ ショートカット — App Intents

### 権限: 特別な権限不要

| API | フレームワーク | 機能 |
|-----|--------------|------|
| `AppIntent` プロトコル | App Intents | Siri / ショートカットから呼び出せる操作を定義 |
| `AppShortcutsProvider` | App Intents | ショートカットを自動登録 |

Agent の各スキルを App Intent として登録することで、Siri から直接呼び出せるようになります。

---

## 18. 🌐 ネットワーク通信 — URLSession + Network

### 権限: 不要（ローカルネットワークは NSLocalNetworkUsageDescription が必要）

| API | フレームワーク | 機能 |
|-----|--------------|------|
| `URLSession.shared.data(from:)` | Foundation | HTTP リクエスト |
| `URLSession.shared.download(from:)` | Foundation | ファイルのダウンロード |
| `URLSession.shared.webSocketTask()` | Foundation | WebSocket |
| `NWPathMonitor` | Network | ネットワーク状態の監視 |
| `NWBrowser` | Network | ローカルネットワークのサービス検出 |
| `NEHotspotConfiguration` | NetworkExtension | プログラムによる Wi-Fi 接続 |

### Agent スキル
```
skill: web_fetch      → HTTP リクエスト
skill: web_search     → 検索 + Gemma 4 による要約
skill: api_call       → REST API の呼び出し
skill: network_status → ネットワーク状態の確認
skill: download_file  → ファイルをサンドボックスにダウンロード
```

---

## 19. 🔐 Face ID — LocalAuthentication

### 権限: NSFaceIDUsageDescription

| API | 機能 |
|-----|------|
| `LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)` | 生体認証 |
| `LAContext.biometryType` | Face ID / Touch ID の検出 |

### Agent スキル
```
skill: auth_biometric → 重要な操作の前に顔認証・指紋認証を要求
```

---

## 20. 💬 メール/SMS — MessageUI

### 権限: 不要 — システムが編集画面を表示し、ユーザーが手動で送信を確認

| API | 機能 |
|-----|------|
| `MFMailComposeViewController` | メールを編集して送信（添付ファイル対応）|
| `MFMessageComposeViewController` | SMS / iMessage を編集して送信 |

### Agent スキル
```
skill: email_compose → メールの内容を事前入力し、ユーザーが確認して送信
skill: sms_compose   → SMS の内容を事前入力し、ユーザーが確認して送信
```
