# 第3部（続き）：権限不要のシステム API

---

## 21. ⚡ 触覚フィードバック — Core Haptics

### 権限: 不要

| API | 機能 |
|-----|------|
| `UIImpactFeedbackGenerator` | 衝撃フィードバック（弱・中・強）|
| `UISelectionFeedbackGenerator` | 選択フィードバック |
| `UINotificationFeedbackGenerator` | 通知フィードバック（成功・警告・エラー）|
| `CHHapticEngine` + `CHHapticPattern` | カスタム振動パターンの設計 |

### スキル: `haptic_feedback` → Agent の応答・エラー・ナビゲーション時に触覚でフィードバック

---

## 22. 📺 デバイス情報 — UIDevice / UIScreen / ProcessInfo

### 権限: 不要

| API | 機能 |
|-----|------|
| `UIScreen.main.brightness` | 画面の明るさを取得/設定 |
| `UIDevice.current.batteryLevel` | バッテリー残量 |
| `UIDevice.current.batteryState` | 充電状態 |
| `UIDevice.current.model` | デバイスモデル |
| `UIDevice.current.systemVersion` | iOS バージョン |
| `ProcessInfo.processInfo.thermalState` | デバイスの温度状態 |
| `ProcessInfo.processInfo.isLowPowerModeEnabled` | 低電力モードの状態 |
| `ProcessInfo.processInfo.physicalMemory` | 物理メモリ容量 |

### スキル
```
skill: device_info       → デバイスモデル・バージョン・バッテリー・温度を返す
skill: screen_brightness → 画面の明るさを取得または調整
skill: battery_status    → バッテリー残量・充電状態・低電力モードを確認
```

---

## 23. 🔑 キーチェーン — Security Framework

### 権限: 不要（サンドボックス内で自動的に利用可能）

| API | 機能 |
|-----|------|
| `SecItemAdd()` | APIキー・パスワードを暗号化して保存 |
| `SecItemCopyMatching()` | 保存された項目を検索 |
| `SecItemUpdate()` / `SecItemDelete()` | 更新・削除 |

### スキル: Agent が API キーとユーザー認証情報を安全に保存

---

## 24. 💾 UserDefaults — 軽量データ保存

### 権限: 不要（Privacy Manifest への記載が必要）

用途: ユーザーの設定（言語・目標・パーソナリティ設定）を Agent が記憶する

---

## 25. 🎙 音声合成 — AVSpeechSynthesizer

### 権限: 不要

| API | 機能 |
|-----|------|
| `AVSpeechSynthesizer.speak()` | テキストを音声に変換して再生 |
| `AVSpeechSynthesisVoice` | 言語・音声の選択 |
| `.rate` / `.pitchMultiplier` / `.volume` | 速度・ピッチ・音量 |

### スキル: `tts_speak` → Agent がユーザーに音声で返答
