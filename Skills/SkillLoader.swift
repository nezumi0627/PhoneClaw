import Foundation
import Yams

// MARK: - SKILL.md パーサー + ローダー
//
// Vera プロジェクトの skill_loader.py を参考にした Swift 版実装。
// 段階的ロード：
//   1. 起動時：YAML フロントマター（メタデータ）のみロード
//   2. load_skill 呼び出し時：完全な本文（指示体）をロード

// MARK: - データモデル

struct SkillExample {
    let query: String
    let scenario: String
}

struct SkillMetadata {
    let id: String              // ディレクトリ名（例: "clipboard"）
    let name: String            // デフォルト英語名 / フォールバック表示名
    let localizedNameJa: String? // 日本語ローカライズ名
    let description: String
    let version: String
    let icon: String
    let disabled: Bool
    let triggers: [String]
    let allowedTools: [String]
    let examples: [SkillExample]

    var displayName: String {
        // 日本語環境では日本語名を優先
        if Locale.preferredLanguages.contains(where: { $0.lowercased().hasPrefix("ja") }),
           let localizedNameJa,
           !localizedNameJa.isEmpty {
            return localizedNameJa
        }
        return name
    }
}

struct SkillDefinition: Identifiable {
    let id: String
    let filePath: URL
    let metadata: SkillMetadata
    var body: String?           // Markdown 本文（遅延ロード）
    var isEnabled: Bool

    /// SKILL.md の生の内容
    var rawContent: String? {
        try? String(contentsOf: filePath, encoding: .utf8)
    }
}

// MARK: - Skill ローダー

class SkillLoader {
    // スキルエイリアス（旧名 → 正規名）
    private static let skillAliases: [String: String] = [
        "contacts_delete": "contacts",
        "contacts-delete": "contacts"
    ]

    let skillsDirectory: URL
    private var cache: [String: SkillDefinition] = [:]

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.skillsDirectory = appSupport.appendingPathComponent("PhoneClaw/skills", isDirectory: true)
        ensureDefaultSkills()
    }

    // MARK: - 公開インターフェース

    /// 全スキルのメタデータを発見・ロード
    func discoverSkills() -> [SkillDefinition] {
        cache.removeAll()
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: skillsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        var results: [SkillDefinition] = []
        for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir)
            guard isDir.boolValue else { continue }

            let skillFile = item.appendingPathComponent("SKILL.md")
            guard FileManager.default.fileExists(atPath: skillFile.path) else { continue }

            let skillId = item.lastPathComponent
            // エイリアスディレクトリはスキップ
            if Self.skillAliases[skillId] != nil { continue }

            if let def = loadDefinition(skillId: skillId, file: skillFile) {
                cache[skillId] = def
                results.append(def)
            }
        }
        return results
    }

    /// スキルの本文を完全ロード（load_skill 呼び出し時）
    func loadBody(skillId: String) -> String? {
        let resolvedSkillId = canonicalSkillId(for: skillId)
        if let cached = cache[resolvedSkillId], cached.body != nil {
            return cached.body
        }
        let skillFile = skillsDirectory
            .appendingPathComponent(resolvedSkillId, isDirectory: true)
            .appendingPathComponent("SKILL.md")

        guard let content = try? String(contentsOf: skillFile, encoding: .utf8) else { return nil }
        let body = parseBody(content)
        cache[resolvedSkillId]?.body = body
        return body
    }

    /// SKILL.md を保存（編集後に書き戻す）
    func saveSkill(skillId: String, content: String) throws {
        let skillFile = skillsDirectory
            .appendingPathComponent(skillId, isDirectory: true)
            .appendingPathComponent("SKILL.md")
        try content.write(to: skillFile, atomically: true, encoding: .utf8)
        // キャッシュをクリアして次回再解析を強制
        cache.removeValue(forKey: skillId)
    }

    /// 全スキルを再ロード（ホットリロードのエントリポイント）
    func reloadAll() -> [SkillDefinition] {
        return discoverSkills()
    }

    /// ツール名からスキルIDを逆引き
    func findSkillId(forTool toolName: String) -> String? {
        for (id, def) in cache {
            if def.metadata.allowedTools.contains(toolName) {
                return id
            }
        }
        return nil
    }

    /// キャッシュされた SkillDefinition を取得
    func getDefinition(_ skillId: String) -> SkillDefinition? {
        cache[canonicalSkillId(for: skillId)]
    }

    /// 有効/無効状態を更新
    func setEnabled(_ skillId: String, enabled: Bool) {
        cache[canonicalSkillId(for: skillId)]?.isEnabled = enabled
    }

    func canonicalSkillId(for skillId: String) -> String {
        Self.skillAliases[skillId] ?? skillId
    }

    // MARK: - 解析

    private func loadDefinition(skillId: String, file: URL) -> SkillDefinition? {
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        guard let frontmatter = parseFrontmatter(content) else { return nil }

        let metadata = SkillMetadata(
            id: skillId,
            name: frontmatter["name"] as? String ?? skillId,
            localizedNameJa: frontmatter["name-ja"] as? String,
            description: frontmatter["description"] as? String ?? "",
            version: frontmatter["version"] as? String ?? "1.0.0",
            icon: frontmatter["icon"] as? String ?? "wrench",
            disabled: frontmatter["disabled"] as? Bool ?? false,
            triggers: frontmatter["triggers"] as? [String] ?? [],
            allowedTools: frontmatter["allowed-tools"] as? [String] ?? [],
            examples: parseExamples(frontmatter["examples"])
        )

        return SkillDefinition(
            id: skillId,
            filePath: file,
            metadata: metadata,
            body: nil, // 遅延ロード
            isEnabled: !metadata.disabled
        )
    }

    private func parseFrontmatter(_ content: String) -> [String: Any]? {
        // --- ... --- で囲まれた YAML をマッチング
        guard let regex = try? NSRegularExpression(
            pattern: "^---\\s*\\n(.*?)\\n---\\s*\\n",
            options: .dotMatchesLineSeparators
        ) else { return nil }

        let range = NSRange(content.startIndex..., in: content)
        guard let match = regex.firstMatch(in: content, range: range),
              let yamlRange = Range(match.range(at: 1), in: content) else { return nil }

        let yamlString = String(content[yamlRange])
        // Yams で YAML を解析
        guard let parsed = try? Yams.load(yaml: yamlString) as? [String: Any] else { return nil }
        return parsed
    }

    private func parseBody(_ content: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "^---\\s*\\n.*?\\n---\\s*\\n(.*)$",
            options: .dotMatchesLineSeparators
        ) else { return content }

        let range = NSRange(content.startIndex..., in: content)
        if let match = regex.firstMatch(in: content, range: range),
           let bodyRange = Range(match.range(at: 1), in: content) {
            return String(content[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseExamples(_ raw: Any?) -> [SkillExample] {
        guard let list = raw as? [[String: Any]] else { return [] }
        return list.compactMap { dict in
            guard let query = dict["query"] as? String,
                  let scenario = dict["scenario"] as? String else { return nil }
            return SkillExample(query: query, scenario: scenario)
        }
    }

    // MARK: - 初回起動時：デフォルトスキルを書き込む

    private func ensureDefaultSkills() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: skillsDirectory.path) {
            try? fm.createDirectory(at: skillsDirectory, withIntermediateDirectories: true)
        }

        for (dirName, content) in Self.defaultSkills {
            let dir = skillsDirectory.appendingPathComponent(dirName, isDirectory: true)
            let file = dir.appendingPathComponent("SKILL.md")
            let normalized = content.hasSuffix("\n") ? content : content + "\n"
            let current = try? String(contentsOf: file, encoding: .utf8)
            if current == normalized { continue }
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try? normalized.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - 組み込みデフォルト SKILL.md

    static let defaultSkills: [(String, String)] = [
        ("clipboard", """
        ---
        name: Clipboard
        name-ja: クリップボード
        description: 'システムクリップボードの読み書きを行います。ユーザーがクリップボードの読み取り、コピー、操作を必要とする場合に使用します。'
        version: "1.0.0"
        icon: doc.on.clipboard
        disabled: false

        triggers:
          - クリップボード
          - コピー
          - 貼り付け
          - clipboard

        allowed-tools:
          - clipboard-read
          - clipboard-write

        examples:
          - query: "クリップボードの内容を読んで"
            scenario: "クリップボードを読む"
          - query: "このテキストをクリップボードにコピーして"
            scenario: "クリップボードに書き込む"
        ---

        # クリップボード操作

        ユーザーのシステムクリップボードの読み書きをサポートします。

        ## 利用可能なツール

        - **clipboard-read**: クリップボードの現在の内容を読み取る（パラメータなし）
        - **clipboard-write**: テキストをクリップボードに書き込む（パラメータ: text — コピーするテキスト）

        ## 実行フロー

        1. 読み取りを求められた場合 → `clipboard-read` を呼び出す
        2. コピー/書き込みを求められた場合 → `clipboard-write` を呼び出し、text パラメータを渡す
        3. ツールの返り値に基づいて簡潔に回答する

        ## 呼び出し形式

        <tool_call>
        {"name": "ツール名", "arguments": {}}
        </tool_call>
        """),

        ("device", """
        ---
        name: Device
        name-ja: デバイス
        description: 'iOS 公式公開 API を使用して現在のデバイス名、タイプ、システムバージョン、メモリ、プロセッサ数を照会します。'
        version: "1.0.0"
        icon: desktopcomputer
        disabled: false

        triggers:
          - デバイス
          - システム情報
          - 現在のデバイス
          - 本体

        allowed-tools:
          - device-info
          - device-name
          - device-model
          - device-system-version
          - device-memory
          - device-processor-count
          - device-identifier-for-vendor

        examples:
          - query: "このデバイスの情報を教えて"
            scenario: "デバイス情報の概要を表示"
          - query: "システムバージョンは何"
            scenario: "システムバージョンを確認"
          - query: "このデバイスの名前は"
            scenario: "デバイス名を確認"
          - query: "メモリはどのくらい"
            scenario: "物理メモリを確認"
          - query: "プロセッサのコア数は"
            scenario: "プロセッサ数を確認"
        ---

        # デバイス情報照会

        現在のデバイスのシステム・ハードウェアの基本情報を確認するサポートをします。

        ## 利用可能なツール

        - **device-info**: 現在のデバイス名、タイプ、システムバージョン、物理メモリ、プロセッサ数を一括取得
        - **device-name**: デバイス名を取得
        - **device-model**: デバイスタイプを取得（公式 `UIDevice.model` / `localizedModel`）
        - **device-system-version**: システム名とバージョンを取得
        - **device-memory**: 物理メモリサイズを取得
        - **device-processor-count**: プロセッサコア数を取得
        - **device-identifier-for-vendor**: 現在の App の `identifierForVendor` を取得

        ## 実行フロー

        1. ユーザーが現在のデバイス、本体、システムバージョン、メモリ、プロセッサなどを明確に質問した場合のみツールを呼び出す
        2. 最小限の専用ツールで回答できる場合はそれを優先し、全体的な情報が必要な場合のみ `device-info` を使用
        3. ツール結果をユーザーフレンドリーな日本語で提供する

        ## 呼び出し形式

        <tool_call>
        {"name": "device-info", "arguments": {}}
        </tool_call>
        """),

        ("text", """
        ---
        name: Text
        name-ja: テキスト
        description: 'テキスト処理ツール：ハッシュ計算、反転など。ユーザーがテキストを処理・変換する必要がある場合に使用します。'
        version: "1.0.0"
        icon: textformat
        disabled: false

        triggers:
          - ハッシュ
          - hash
          - 反転
          - 逆順
          - テキスト処理

        allowed-tools:
          - calculate-hash
          - text-reverse

        examples:
          - query: "Hello World のハッシュ値を計算して"
            scenario: "ハッシュ計算"
          - query: "このテキストを反転して"
            scenario: "テキスト反転"
        ---

        # テキスト処理

        テキスト処理操作をサポートします。

        ## 利用可能なツール

        - **calculate-hash**: テキストのハッシュ値を計算（パラメータ: text — ハッシュを計算するテキスト）
        - **text-reverse**: テキストを反転（パラメータ: text — 反転するテキスト）

        ## 実行フロー

        1. ユーザーが必要とするテキスト操作を判断
        2. 対応するツールを呼び出し、text パラメータを渡す
        3. 処理結果を返す

        ## 呼び出し形式

        <tool_call>
        {"name": "ツール名", "arguments": {"text": "処理するテキスト"}}
        </tool_call>
        """),

        ("calendar", """
        ---
        name: Calendar
        name-ja: カレンダー
        description: '新しいカレンダーイベントを作成します。ユーザーがスケジュール、会議、約束、カレンダーへの書き込みを必要とする場合に使用します。'
        version: "1.0.0"
        icon: calendar
        disabled: false

        triggers:
          - カレンダー
          - 予定
          - 会議
          - 約束
          - スケジュール

        allowed-tools:
          - calendar-create-event

        examples:
          - query: "明日の午後2時に会議を作成して"
            scenario: "カレンダーイベントを新規作成"
        ---

        # カレンダーイベント作成

        新しいカレンダーイベントの作成をサポートします。

        ## 利用可能なツール

        - **calendar-create-event**: カレンダーイベントを作成
          - `title`: 必須、イベントタイトル
          - `start`: 必須、ISO 8601 開始時刻（例: `2026-04-07T14:00:00`）
          - `end`: 任意、ISO 8601 終了時刻（省略時は開始の1時間後）
          - `location`: 任意、場所
          - `notes`: 任意、メモ

        ## 実行フロー

        1. ユーザーが明確にカレンダーイベントの新規作成/スケジュール設定を求めた場合のみツールを呼び出す
        2. ユーザーの発言からパラメータを抽出し、時刻は ISO 8601 文字列に変換する
        3. `title` または `start` が欠けている場合は簡潔に追加質問する
        4. ツール成功後、作成したイベントと時刻をユーザーに伝える

        ## 呼び出し形式

        <tool_call>
        {"name": "calendar-create-event", "arguments": {"title": "会議", "start": "2026-04-07T14:00:00"}}
        </tool_call>
        """),

        ("reminders", """
        ---
        name: Reminders
        name-ja: リマインダー
        description: '新しいリマインダーを作成します。ユーザーが何かを覚えておく必要がある場合、ToDo の設定やリマインドが必要な場合に使用します。'
        version: "1.0.0"
        icon: bell
        disabled: false

        triggers:
          - リマインド
          - リマインダー
          - ToDo
          - 覚えておいて
          - 思い出させて

        allowed-tools:
          - reminders-create

        examples:
          - query: "今夜8時にファイルを送るのをリマインドして"
            scenario: "リマインダーを新規作成"
        ---

        # リマインダー作成

        新しいリマインダーの作成をサポートします。

        ## 利用可能なツール

        - **reminders-create**: リマインダーを作成
          - `title`: 必須、リマインダータイトル
          - `due`: 任意、ISO 8601 リマインド時刻（例: `2026-04-07T20:00:00`）
          - `notes`: 任意、メモ

        ## 実行フロー

        1. ユーザーが明確にリマインダーや ToDo の設定を求めた場合のみツールを呼び出す
        2. タイトル、時刻、メモを抽出し、時刻がある場合は ISO 8601 文字列に変換する
        3. `title` が欠けている場合は簡潔に追加質問する
        4. ツール成功後、リマインダーが作成されたことをユーザーに伝える

        ## 呼び出し形式

        <tool_call>
        {"name": "reminders-create", "arguments": {"title": "ファイルを送る", "due": "2026-04-07T20:00:00"}}
        </tool_call>
        """),

        ("contacts", """
        ---
        name: Contacts
        name-ja: 連絡先
        description: '連絡先の照会、作成、更新、削除を行います。ユーザーが電話番号の確認、連絡先の保存、情報の補足、連絡先の削除を必要とする場合に使用します。'
        version: "1.1.0"
        icon: person.crop.circle
        disabled: false

        triggers:
          - 連絡先
          - アドレス帳
          - 電話番号を調べる
          - 番号を保存
          - 連絡方法
          - 連絡先を削除

        allowed-tools:
          - contacts-search
          - contacts-upsert
          - contacts-delete

        examples:
          - query: "田中さんの電話番号 090-1234-5678 を連絡先に追加して"
            scenario: "連絡先を新規作成または更新"
          - query: "山田花子さんの電話番号を調べて"
            scenario: "連絡先の電話番号を照会"
          - query: "田中さんを連絡先から削除して"
            scenario: "連絡先を削除"
        ---

        # 連絡先の照会・管理

        アドレス帳の連絡先の照会、作成、更新、削除をサポートします。

        ## 利用可能なツール

        - **contacts-search**: 連絡先を検索
          - `query`: キーワード（あいまい検索可）
          - `name`: 連絡先の名前
          - `phone`: 電話番号
          - `email`: メールアドレス
          - `identifier`: 連絡先の識別子
        - **contacts-upsert**: 連絡先を作成または更新
          - `name`: 必須、連絡先の名前
          - `phone`: 任意、電話番号（提供された場合、電話番号で重複チェック）
          - `company`: 任意、会社名
          - `email`: 任意、メールアドレス
          - `notes`: 任意、メモ
        - **contacts-delete**: 連絡先を削除
          - `query`: キーワード（あいまい検索可）
          - `name`: 連絡先の名前
          - `phone`: 電話番号
          - `email`: メールアドレス
          - `identifier`: 連絡先の識別子

        ## 実行フロー

        1. 電話番号やメール確認 → `contacts-search`
        2. 削除 → `contacts-delete`
        3. 保存・追加・更新 → `contacts-upsert`
        4. `name` を優先して抽出し、取得できない場合は `query` を使用
        5. 保存に必要な `name` が欠けている場合は簡潔に追加質問する
        6. 削除時に複数マッチした場合は推測せず、より具体的な情報を求める
        7. ツール成功後、簡潔な日本語で結果を伝える

        ## 呼び出し形式

        <tool_call>
        {"name": "contacts-search", "arguments": {"name": "山田花子"}}
        </tool_call>

        <tool_call>
        {"name": "contacts-upsert", "arguments": {"name": "田中", "phone": "090-1234-5678", "company": "○○株式会社"}}
        </tool_call>

        <tool_call>
        {"name": "contacts-delete", "arguments": {"name": "田中"}}
        </tool_call>
        """),
    ]
}
