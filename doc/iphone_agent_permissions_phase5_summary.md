# 第5部：App Extension の能力 + 最終まとめ

---

## 36〜40. App Extensions — アプリの境界を超えたシステムレベル統合

### 36. 🔤 カスタムキーボード Extension

```
Keyboard Extension Target
→ Agent がシステムキーボードとしてあらゆるアプリ上で動作
→ 機能: どの入力欄でも AI アシスト
   - スマート補完
   - リアルタイム翻訳
   - 文法チェック
   - 文体変換（フォーマル・カジュアル・ユーモア）
```

### 37. 🔗 Share Extension

```
Share Extension Target
→ ユーザーが任意のアプリの共有メニューから Agent を呼び出せる
→ 活用シーン:
   - Safari でウェブページを共有 → Agent が要約
   - フォトライブラリで写真を共有 → Agent が認識・分類
   - メモで本文を共有 → Agent が分析・翻訳
```

### 38. 🖼 Photo Editing Extension

```
Photo Editing Extension Target
→ システムの写真アプリから直接 Agent を呼び出して写真を編集
→ 機能: AI による写真の説明・スマートトリミング提案・OCR テキスト抽出
```

### 39. 🌐 Safari Content Blocker

```
Content Blocker Extension Target
→ Agent が Safari の広告・トラッカーブロックルールを管理
→ ユーザー: 「このサイトのポップアップ広告をブロックして」
→ Agent がブロックルールの JSON を動的に更新
```

### 40. 🎯 Action Extension

```
Action Extension Target
→ ユーザーがテキスト・画像を選択 → 長押し → Agent を呼び出す
→ 活用シーン: 英文を選択 → 「日本語に翻訳」 → その場で置き換え
```

---

# 最終まとめ

## 全スキル一覧（権限別分類）

### 🔴 ユーザー認可が必要（Info.plist + ダイアログ）

| # | 権限 | Info.plist キー | スキル | 数 |
|---|------|----------------|--------|----|
| 1 | カメラ | NSCameraUsageDescription | camera_capture, document_scan, barcode_scan, ocr_extract, object_detect, face_analyze, body_pose, live_scene_describe | 8 |
| 2 | マイク | NSMicrophoneUsageDescription | voice_listen, audio_record, meeting_transcribe, sound_detect, audio_to_model | 5 |
| 3 | 音声認識 | NSSpeechRecognitionUsageDescription | （マイクスキルに含む）| - |
| 4 | 位置情報（前景）| NSLocationWhenInUseUsageDescription | location_get, nearby_search, route_plan, compass_heading | 4 |
| 5 | 位置情報（常時）| NSLocationAlwaysAndWhenInUseUsageDescription | location_track, geofence_set | 2 |
| 6 | モーションセンサー | NSMotionUsageDescription | step_count, activity_detect, motion_raw, fall_detect, altitude_track | 5 |
| 7 | NFC | NFCReaderUsageDescription | nfc_read, nfc_write, nfc_tag_info | 3 |
| 8 | Bluetooth | NSBluetoothAlwaysUsageDescription | ble_scan, ble_connect, ble_read, ble_write, ble_subscribe | 5 |
| 9 | フォトライブラリ（読み取り）| NSPhotoLibraryUsageDescription | photos_search, photos_recent, photos_by_location, photos_organize, photo_edit_metadata | 5 |
| 10 | フォトライブラリ（書き込み）| NSPhotoLibraryAddUsageDescription | photos_save | 1 |
| 11 | 連絡先 | NSContactsUsageDescription | contacts_search, contacts_create, contacts_update, contacts_list_all, contacts_birthday_upcoming | 5 |
| 12 | カレンダー | NSCalendarsFullAccessUsageDescription | calendar_query, calendar_create, calendar_check_free, calendar_recurring, calendar_delete | 5 |
| 13 | リマインダー | NSRemindersFullAccessUsageDescription | reminders_query, reminders_create, reminders_location_based, reminders_complete, reminders_batch_create | 5 |
| 14 | ヘルスケア（読み取り）| NSHealthShareUsageDescription | health_steps, health_heart_rate, health_sleep, health_weight_trend, health_blood_oxygen, health_comprehensive_report | 6 |
| 15 | ヘルスケア（書き込み）| NSHealthUpdateUsageDescription | health_workout_log, health_water_log | 2 |
| 16 | ミュージックライブラリ | NSAppleMusicUsageDescription | music_play, music_control, music_now_playing, music_search_library | 4 |
| 17 | Face ID | NSFaceIDUsageDescription | auth_biometric | 1 |
| 18 | HomeKit | NSHomeKitUsageDescription | home_list_devices, home_control, home_read_status, home_scene, home_automation, home_sensor_read | 6 |
| 19 | Siri | NSSiriUsageDescription | siri_integration（全スキルを Siri に公開）| 1 |
| 20 | 集中モード | NSFocusStatusUsageDescription | focus_status | 1 |
| 21 | 通知 | UNUserNotificationCenter（コードで要求）| notification_send, notification_schedule, notification_location, notification_interactive | 4 |

### 🟢 ユーザー認可不要

| # | 機能 | スキル | 数 |
|---|------|--------|----|
| 22 | クリップボード | clipboard_read, clipboard_write, clipboard_analyze | 3 |
| 23 | ファイル（サンドボックス）| file_pick, file_read, file_write, file_list, file_analyze_pdf | 5 |
| 24 | ネットワーク通信 | web_fetch, web_search, api_call, network_status, download_file | 5 |
| 25 | メール/SMS | email_compose, sms_compose | 2 |
| 26 | 触覚フィードバック | haptic_feedback, haptic_pattern | 2 |
| 27 | デバイス情報 | device_info, screen_brightness, battery_status | 3 |
| 28 | キーチェーン | keychain_store, keychain_retrieve | 2 |
| 29 | UserDefaults | preference_set, preference_get | 2 |
| 30 | 音声合成 | tts_speak, tts_stop | 2 |
| 31 | Spotlight | spotlight_index | 1 |
| 32 | ウィジェット | widget_update | 1 |
| 33 | Live Activity | live_activity_start, live_activity_update | 2 |
| 34 | バックグラウンドタスク | bg_refresh, bg_process | 2 |
| 35 | AR | ar_measure, ar_scene_understand, ar_place_info, ar_face_mesh, ar_room_scan | 5 |
| 36 | 画面収録 | screen_record_start, screen_record_stop, screen_capture_frame | 3 |
| 37 | アクセシビリティ | accessibility_check | 1 |
| 38 | CallKit | call_display | 1 |

### 🔵 App Extension

| # | 種類 | 機能 |
|---|------|------|
| 39 | Keyboard Extension | 任意の入力欄で AI アシスト |
| 40 | Share Extension | システム共有メニューへの統合 |
| 41 | Photo Editing Extension | 写真アプリ内で AI 編集 |
| 42 | Content Blocker | Safari 広告ブロック |
| 43 | Action Extension | 選択コンテンツのクイック処理 |

---

## 統計

| 指標 | 数量 |
|------|------|
| **権限タイプ合計** | 認可必要 21 種 + 認可不要 17 種 + Extension 5 種 |
| **スキル総数** | 約 105 個の実装可能な Agent スキル |
| **API 総数** | 約 200 以上の呼び出し可能な iOS API |
| **Info.plist キー** | 21 個の NSUsageDescription |
| **Entitlement** | 3〜5 個（HealthKit・HomeKit・NFC・Siri・BLE バックグラウンド）|
| **Background Modes** | 4 個（Location・Audio・Background fetch・Background processing）|

---

## Info.plist 完全リスト

```xml
<!-- ハードウェア -->
<key>NSCameraUsageDescription</key>
<string>PhoneClaw は写真認識やQRコードスキャンのためにカメラを使用します</string>
<key>NSMicrophoneUsageDescription</key>
<string>PhoneClaw は音声会話や録音のためにマイクを使用します</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>PhoneClaw は音声指示を理解するために音声認識を使用します</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>PhoneClaw は周辺検索やナビゲーションのために位置情報を使用します</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>PhoneClaw はジオフェンスリマインダーのためにバックグラウンドで位置情報を使用します</string>
<key>NSMotionUsageDescription</key>
<string>PhoneClaw は歩数の記録や活動の検出のためにモーションデータを使用します</string>
<key>NFCReaderUsageDescription</key>
<string>PhoneClaw は NFC タグの読み書きのために NFC を使用します</string>
<key>NSBluetoothAlwaysUsageDescription</key>
<string>PhoneClaw は周辺デバイスへの接続のために Bluetooth を使用します</string>

<!-- ユーザーデータ -->
<key>NSPhotoLibraryUsageDescription</key>
<string>PhoneClaw は写真の検索・分析のためにフォトライブラリを使用します</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>PhoneClaw はフォトライブラリへの写真保存のために使用します</string>
<key>NSContactsUsageDescription</key>
<string>PhoneClaw は連絡先の検索・管理のために使用します</string>
<key>NSCalendarsFullAccessUsageDescription</key>
<string>PhoneClaw はスケジュール管理のためにカレンダーを使用します</string>
<key>NSRemindersFullAccessUsageDescription</key>
<string>PhoneClaw はタスク管理のためにリマインダーを使用します</string>
<key>NSHealthShareUsageDescription</key>
<string>PhoneClaw は健康アドバイスの提供のために健康データを読み取ります</string>
<key>NSHealthUpdateUsageDescription</key>
<string>PhoneClaw は運動記録のために健康データを書き込みます</string>
<key>NSAppleMusicUsageDescription</key>
<string>PhoneClaw は音楽の再生・検索のためにミュージックライブラリを使用します</string>

<!-- システム統合 -->
<key>NSFaceIDUsageDescription</key>
<string>PhoneClaw は重要な操作の保護のために Face ID を使用します</string>
<key>NSHomeKitUsageDescription</key>
<string>PhoneClaw はスマートホームデバイスの制御のために HomeKit を使用します</string>
<key>NSSiriUsageDescription</key>
<string>PhoneClaw は音声アシスタント機能の提供のために Siri を使用します</string>
<key>NSFocusStatusUsageDescription</key>
<string>PhoneClaw は集中モード中の通知を抑制するために集中モードの状態を使用します</string>
<key>NSLocalNetworkUsageDescription</key>
<string>PhoneClaw はローカルデバイスの検出のためにローカルネットワークを使用します</string>
```
