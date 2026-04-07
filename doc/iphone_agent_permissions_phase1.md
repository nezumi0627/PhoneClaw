# PhoneClaw: iPhone エージェント 権限全景図

> Apple 公式ドキュメントに基づいた真の iOS API 一覧。想像ではありません。すべて呼び出し可能なシステム機能です。

## アーキテクチャの核心

```
ユーザー入力（音声/テキスト/撮影）
        │
        ▼
┌───────────────┐
│   Gemma 4     │  ← デバイス内推論、CoreML/MLX
│   (LLM Brain) │
└───────┬───────┘
        │ Function Calling（意図 → Skill 名）
        ▼
┌───────────────┐
│  Skill Router │  ← 具体的な iOS API ラッパーにルーティング
└───────┬───────┘
        │
        ▼
┌───────────────────────────────────────────┐
│            iOS Skill Layer                │
│                                           │
│  各 Skill = 1つの Swift 関数ラッパー       │
│  JSON パラメータを受け取り、JSON 結果を返す │
│  すべてのデータはデバイス外に出ない        │
└───────────────────────────────────────────┘
```

### Skill プロトコル定義（Swift）

```swift
protocol AgentSkill {
    var name: String { get }
    var description: String { get }
    var parameters: [SkillParameter] { get }
    
    func execute(args: [String: Any]) async throws -> SkillResult
}
```

### 権限取得方法

| 方法 | 説明 |
|------|------|
| `Info.plist` NSUsageDescription | 初回呼び出し時にポップアップで許可を要求 |
| Entitlements | Xcode Signing & Capabilities で設定 |
| 権限不要 | サンドボックス内 API、直接利用可能 |
| Background Mode | Info.plist + BGTaskScheduler |

---

# 第一部分：ハードウェアセンサー権限（ユーザー認証が必要）

---

## 1. 📷 カメラ — AVFoundation + VisionKit

### 権限設定
```
Info.plist: NSCameraUsageDescription
```

### 呼び出し可能 API

| API | フレームワーク | 機能 |
|-----|------|------|
| `AVCaptureSession` | AVFoundation | カメラ起動、リアルタイムフレーム取得 |
| `AVCapturePhotoOutput` | AVFoundation | 静止写真撮影 |
| `AVCaptureMovieFileOutput` | AVFoundation | 動画録画 |
| `AVCaptureVideoDataOutput` | AVFoundation | フレームごとの映像ストリーム取得（Vision/CoreML に供給）|
| `VNDocumentCameraViewController` | VisionKit | システム文書スキャン UI（自動裁断・補正）|
| `DataScannerViewController` | VisionKit | リアルタイムコードスキャン + OCR UI |
| `VNDetectBarcodesRequest` | Vision | バーコード/QRコード検出 |
| `VNRecognizeTextRequest` | Vision | OCR 文字認識 |
| `VNCoreMLRequest` | Vision | カスタム CoreML モデル推論 |
| `VNDetectFaceLandmarksRequest` | Vision | 顔の特徴点検出 |
| `VNDetectHumanBodyPoseRequest` | Vision | 人体姿勢検出 |
| `VNDetectHumanHandPoseRequest` | Vision | ジェスチャー検出 |
| `VNClassifyImageRequest` | Vision | 組み込み画像分類 |
| `VNGenerateObjectnessBasedSaliencyImageRequest` | Vision | 画像顕著領域検出 |

### Agent Skills

```
skill: camera_capture
  → 写真を撮影して UIImage を返す
  → Gemma 4 が直接画像内容を分析

skill: document_scan  
  → VNDocumentCameraViewController を呼び出す
  → 補正後の文書画像を返す
  → Gemma 4 が文書内容を分析して要約

skill: barcode_scan
  → VNDetectBarcodesRequest でリアルタイムスキャン
  → 返り値: { type: "QR", payload: "https://..." }

skill: ocr_extract
  → VNRecognizeTextRequest
  → 返り値: { text: "認識されたすべてのテキスト", confidence: 0.95 }

skill: object_detect
  → VNCoreMLRequest + カスタムモデル
  → 返り値: { objects: [{ label: "猫", confidence: 0.92, bbox: {...} }] }

skill: face_analyze
  → VNDetectFaceLandmarksRequest
  → 返り値: { faces: [{ landmarks: {...}, bbox: {...} }] }

skill: body_pose
  → VNDetectHumanBodyPoseRequest
  → 返り値: { joints: { leftShoulder: {x,y}, rightKnee: {x,y}, ... } }

skill: live_scene_describe
  → AVCaptureVideoDataOutput → フレームごとに Gemma 4 に送信
  → 現在の画面をリアルタイムで描写（アクセシビリティシーン向け）
```

### 強力なシナリオ

```
ユーザー: 「この薬箱に何と書いてあるか見てください」
  → camera_capture → Gemma 4 画像理解
  → 返り値: 「イブプロフェン徐放性カプセル、仕様0.3g×24粒、
             有効期限2026年8月、1回1〜2粒、1日2回」

ユーザー: 「このQRコードをスキャンして」
  → barcode_scan
  → 返り値: 「これはApple Payコードです、金額980円、店舗: スターバックス西湖店」
 
ユーザー: 「これは何という物ですか？」
  → camera_capture → object_detect + Gemma 4
  → 返り値: 「モンステラ・デリシオサという植物です。
             半日陰の湿潤な環境を好み、週1〜2回の水やりが必要です」
```

---

## 2. 🎤 マイク — AVFoundation + Speech + SoundAnalysis

### 権限設定
```
Info.plist: NSMicrophoneUsageDescription
Info.plist: NSSpeechRecognitionUsageDescription  （音声認識を使用する場合）
```

### 呼び出し可能 API

| API | フレームワーク | 機能 |
|-----|------|------|
| `AVAudioRecorder` | AVFoundation | 音声ファイル録音 |
| `AVAudioEngine` | AVFoundation | リアルタイム音声ストリーム処理（低遅延）|
| `AVAudioEngine.inputNode` | AVFoundation | マイクからのリアルタイム PCM データ取得 |
| `SFSpeechRecognizer` | Speech | Apple 音声テキスト変換（日本語対応）|
| `SFSpeechAudioBufferRecognitionRequest` | Speech | リアルタイムストリーミング音声認識 |
| `SNAudioStreamAnalyzer` | SoundAnalysis | リアルタイム環境音分類 |
| `SNClassifySoundRequest` | SoundAnalysis | 組み込み音声分類（300+種類）|

### Agent Skills

```
skill: voice_listen
  → AVAudioEngine + SFSpeechRecognizer
  → リアルタイム音声テキスト変換、エージェント入力として使用
  → Gemma 4 が音声入力をネイティブサポートする場合は生音声を直接供給

skill: audio_record
  → AVAudioRecorder → 音声ファイル録音
  → 返り値: { filePath: "/tmp/recording.m4a", duration: 45.2 }

skill: meeting_transcribe
  → SFSpeechAudioBufferRecognitionRequest（ストリーミング）
  → 継続的な文字起こし → 終了後 Gemma 4 が要約
  → 返り値: { transcript: "...", summary: "..." }

skill: sound_detect
  → SNClassifySoundRequest（組み込み300+種類）
  → 返り値: { sound: "dog_bark", confidence: 0.88 }
  → 識別可能: ドアベル・赤ちゃんの泣き声・警報・咳・拍手など

skill: audio_to_model
  → AVAudioEngine → 生音声バッファ
  → Gemma 4 のマルチモーダル入力に直接供給
  → Gemma 4 が音声内容を理解（モデルが対応している場合）
```

### 強力なシナリオ

```
ユーザー: 「この会議を録音して、終わったら要約してください」
  → audio_record + meeting_transcribe（並列）
  → 会議終了後 Gemma 4 が要約
  → 返り値: 「会議のポイント: 1. Q2目標を〜に変更、2. 田中さんが担当、
             3. 来週金曜までに提案書提出 | タスク: 3件 | 所要時間: 47分」

ユーザー: [バックグラウンド動作] sound_detect で継続的に監視
  → 赤ちゃんの泣き声を検知 → notification_send
  → 「赤ちゃんの泣き声を検知しました、30秒間継続しています」
```

---

## 3. 📍 位置情報 — CoreLocation

### 権限設定
```
Info.plist: NSLocationWhenInUseUsageDescription     （フォアグラウンド）
Info.plist: NSLocationAlwaysAndWhenInUseUsageDescription （バックグラウンド）
Background Mode: Location updates （バックグラウンドでの継続的な位置情報が必要な場合）
```

### 呼び出し可能 API

| API | フレームワーク | 機能 |
|-----|------|------|
| `CLLocationManager.requestLocation()` | CoreLocation | 単発位置情報取得 |
| `CLLocationManager.startUpdatingLocation()` | CoreLocation | 継続的位置情報取得 |
| `CLLocationManager.startMonitoringSignificantLocationChanges()` | CoreLocation | 大幅な位置変化の監視（省電力）|
| `CLLocationManager.startMonitoring(for: CLCircularRegion)` | CoreLocation | ジオフェンス監視（進入/退出）|
| `CLLocationManager.startMonitoringVisits()` | CoreLocation | ユーザーの「訪問」検出 |
| `CLGeocoder.reverseGeocodeLocation()` | CoreLocation | 緯度経度 → 住所名称 |
| `CLGeocoder.geocodeAddressString()` | CoreLocation | 住所名称 → 緯度経度 |
| `CLLocationManager.heading` | CoreLocation | 電子コンパス方位 |
| `CLLocationManager.startRangingBeacons()` | CoreLocation | iBeacon 測距 |
| `MKLocalSearch` | MapKit | 近隣 POI 検索（飲食店・ガソリンスタンドなど）|
| `MKDirections` | MapKit | ルート案内（車/徒歩/公共交通）|
| `MKMapSnapshotter` | MapKit | 静的地図スクリーンショット生成 |

### Agent Skills

```
skill: location_get
  → CLLocationManager.requestLocation()
  → CLGeocoder.reverseGeocodeLocation()
  → 返り値: { lat: 35.68, lng: 139.69, 
            address: "東京都千代田区丸の内XX番", altitude: 15.2 }

skill: location_track
  → startUpdatingLocation() で継続追跡
  → リアルタイム位置ストリームを返す

skill: geofence_set
  → startMonitoring(for: CLCircularRegion)
  → ジオフェンスを設定、進入/退出時にトリガー
  → 返り値: { fenceId: "office", radius: 200, center: {...} }

skill: nearby_search
  → MKLocalSearch(query: "カフェ")
  → 返り値: { results: [{ name: "スターバックス", distance: "350m", rating: 4.5 }] }

skill: route_plan
  → MKDirections
  → 返り値: { distance: "12.3km", eta: "25分", steps: [...] }

skill: compass_heading
  → CLLocationManager.heading
  → 返り値: { heading: 127.5, direction: "南東" }
```

### 強力なシナリオ

```
ユーザー: 「会社に着いたらメールを確認するよう教えてください」
  → geofence_set(address: "会社", event: "enter")
  → [ユーザーがフェンスに進入] → notification_send("会社に到着しました、メールを確認してください")

ユーザー: 「近くに何か食べるところはありますか？」
  → location_get → nearby_search(query: "レストラン")
  → 返り値: 「現在地付近、500m以内に:
             1. 和食さと（4.3★、平均2,000円）
             2. CoCo壱番屋（4.5★、平均1,000円）
             徒歩で最も近いのは和食さとで約6分です」
```

---

## 4. 🏃 モーションセンサー — CoreMotion

### 権限設定
```
Info.plist: NSMotionUsageDescription
```

### 呼び出し可能 API

| API | フレームワーク | 機能 |
|-----|------|------|
| `CMMotionManager.accelerometerData` | CoreMotion | 加速度計 (x, y, z) |
| `CMMotionManager.gyroData` | CoreMotion | ジャイロスコープ（回転速度）|
| `CMMotionManager.magnetometerData` | CoreMotion | 磁力計 |
| `CMMotionManager.deviceMotion` | CoreMotion | 融合データ（姿勢・重力・ユーザー加速度）|
| `CMPedometer.startUpdates()` | CoreMotion | リアルタイム歩数カウント |
| `CMPedometer.queryPedometerData()` | CoreMotion | 過去の歩数データ照会 |
| `CMAltimeter.startRelativeAltitudeUpdates()` | CoreMotion | 気圧高度変化 |
| `CMMotionActivityManager.startActivityUpdates()` | CoreMotion | 活動タイプ認識（歩行/走行/運転/静止）|
| `CMHeadphoneMotionManager` | CoreMotion | AirPods ヘッド動作追跡 |

### Agent Skills

```
skill: step_count
  → CMPedometer.queryPedometerData(from: today)
  → 返り値: { steps: 8432, distance: 6.1km, floorsAscended: 12 }

skill: activity_detect 
  → CMMotionActivityManager.startActivityUpdates()
  → 返り値: { activity: "walking", confidence: "high" }
  → 識別可能: stationary / walking / running / cycling / driving

skill: motion_raw
  → CMMotionManager.deviceMotion
  → 返り値: { attitude: { pitch, roll, yaw }, 
            gravity: { x, y, z },
            userAcceleration: { x, y, z },
            rotationRate: { x, y, z } }

skill: fall_detect
  → deviceMotion を継続的に監視
  → 突然の加速度変化を検出 → 転倒判定
  → 通知または緊急連絡をトリガー

skill: altitude_track
  → CMAltimeter
  → 返り値: { relativeAltitude: 15.3, pressure: 101.325 } // kPa
```

---

## 5. 📱 NFC — CoreNFC

### 権限設定
```
Info.plist: NFCReaderUsageDescription
Entitlement: com.apple.developer.nfc.readersession.formats
デバイス要件: iPhone 7+（読み取り）、iPhone XS+（バックグラウンド読み取り）
```

### 呼び出し可能 API

| API | フレームワーク | 機能 |
|-----|------|------|
| `NFCNDEFReaderSession` | CoreNFC | NDEF タグの読み取り |
| `NFCNDEFReaderSession.write()` | CoreNFC | NDEF データの書き込み |
| `NFCTagReaderSession` | CoreNFC | ISO 7816 / ISO 15693 / FeliCa / MIFARE タグの読み取り |
| Background Tag Reading | CoreNFC | iPhone XS+ でバックグラウンド自動 NFC タグ検出 |

### Agent Skills

```
skill: nfc_read
  → NFCNDEFReaderSession
  → 返り値: { type: "URI", payload: "https://example.com" }
  → または: { type: "TEXT", payload: "Hello World", locale: "ja" }

skill: nfc_write
  → NFCNDEFReaderSession + write
  → URL / テキスト / vCard を空白タグに書き込む
  → 返り値: { success: true, bytesWritten: 128 }

skill: nfc_tag_info
  → NFCTagReaderSession
  → 返り値: { standard: "ISO14443", uid: "04:A2:...", type: "MIFARE Ultralight" }
```

### 強力なシナリオ

```
ユーザー: 「この NFC タグをスキャンして」
  → nfc_read → Gemma 4 が内容を分析
  → 「このタグには Wi-Fi 設定が含まれています:
     SSID: HomeNetwork、暗号化: WPA2
     接続しましょうか？」

ユーザー: 「この URL を NFC シールに書き込んでください」
  → nfc_write(type: "URI", payload: "https://my-portfolio.com")
  → 「書き込みました。どのスマートフォンをかざしてもポートフォリオサイトが開きます」
```

---

## 6. 📶 Bluetooth — CoreBluetooth

### 権限設定
```
Info.plist: NSBluetoothAlwaysUsageDescription
Background Mode: Uses Bluetooth LE accessories （バックグラウンドが必要な場合）
```

### 呼び出し可能 API

| API | フレームワーク | 機能 |
|-----|------|------|
| `CBCentralManager.scanForPeripherals()` | CoreBluetooth | BLE デバイスのスキャン |
| `CBCentralManager.connect()` | CoreBluetooth | 周辺機器への接続 |
| `CBPeripheral.discoverServices()` | CoreBluetooth | サービスの検出 |
| `CBPeripheral.discoverCharacteristics()` | CoreBluetooth | 特性値の検出 |
| `CBPeripheral.readValue()` | CoreBluetooth | データの読み取り |
| `CBPeripheral.writeValue()` | CoreBluetooth | データの書き込み |
| `CBPeripheral.setNotifyValue()` | CoreBluetooth | データ変化の購読 |
| `CBPeripheralManager` | CoreBluetooth | 周辺機器としてアドバタイズ |

### Agent Skills

```
skill: ble_scan
  → CBCentralManager.scanForPeripherals()
  → 返り値: { devices: [
      { name: "Mi Band 7", rssi: -45, uuid: "..." },
      { name: "AirPods Pro", rssi: -32, uuid: "..." }
    ]}

skill: ble_connect
  → 指定デバイスに接続 → サービスと特性値を検出
  → 返り値: { connected: true, services: ["heart_rate", "battery"] }

skill: ble_read
  → 指定した特性値を読み取る
  → 返り値: { characteristic: "heart_rate", value: 72 }

skill: ble_write
  → 周辺機器にデータを書き込む
  → 返り値: { success: true }

skill: ble_subscribe
  → setNotifyValue → データ更新を継続受信
  → リアルタイムストリーム: { heart_rate: 75 }, { heart_rate: 78 }, ...
```

---

> **フェーズ1完了** — ハードウェアセンサー権限 6 種、**50+ の呼び出し可能 API**
> 
> 次のフェーズ: ユーザーデータ権限（写真・連絡先・カレンダー・リマインダー・ヘルスケア・音楽ライブラリ）
