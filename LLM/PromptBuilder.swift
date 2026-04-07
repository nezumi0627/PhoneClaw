import Foundation

// MARK: - プロンプト構築器（Gemma 4 対話テンプレート + Function Calling）
//
// Gemma 4 は新しいトークン形式を使用：
//   <|turn>system\n ... <turn|>
//   <|turn>user\n ... <turn|>
//   <|turn>model\n ... <turn|>

struct PromptBuilder {

    static let defaultSystemPrompt = "あなたは PhoneClaw です。ローカルデバイス上で動作するプライベート AI アシスタントです。完全にオフラインで動作し、インターネットに接続しません。"
    private static let thinkingOpenMarker = "[[PHONECLAW_THINK]]"
    private static let thinkingCloseMarker = "[[/PHONECLAW_THINK]]"
    private static let thinkingLanguageInstruction = "思考モードが有効な場合、思考チャンネルと最終回答は必ず日本語で行ってください。英語は使用しないでください。"

    /// マルチモーダル専用システムプロンプト（画像・音声対応）
    static func multimodalSystemPrompt(hasImages: Bool, hasAudio: Bool, enableThinking: Bool = false) -> String {
        let base: String
        if hasAudio && !hasImages {
            base = "あなたは PhoneClaw です。ローカルデバイス上で動作する音声アシスタントです。ユーザーが提供した音声を分析素材として扱い、ユーザーが今あなたに話しかけているものとして扱わないでください。音声とテキストのタスクに基づいて直接回答し、ユーザーの意図を勝手に書き換えたり、存在しない意図を追加したりしないでください。聞き取れない、または不確かな場合は明確に説明し、内容を捏造しないでください。音声の内容を尋ねている場合、または文字起こし・識別を明示的に求めている場合は、認識結果を直接提供し、ユーザーの質問を繰り返したり、挨拶を付け加えたりしないでください。逐語的な文字起こしを明示的に求めている場合は、可能な限り原文を保持し、書き換え・要約・修飾はしないでください。また、音声内容をあなたへの会話として扱わないでください。日本語で回答してください。これは純粋な音声問答です。ツールや能力を呼び出さないでください。"
        } else if hasImages && hasAudio {
            base = "あなたは PhoneClaw です。ローカルデバイス上で動作するマルチモーダルアシスタントです。ユーザーが提供した音声を分析素材として扱い、ユーザーが今あなたに話しかけているものとして扱わないでください。ユーザーが提供した画像・音声・テキストに基づいて直接回答し、ユーザーの意図を勝手に書き換えたり、存在しない意図を追加したりしないでください。見えない、聞き取れない、または不確かな場合は直接説明し、内容を捏造しないでください。音声の内容を尋ねている場合、または文字起こし・識別を明示的に求めている場合は、認識結果を直接提供し、ユーザーの質問を繰り返したり、挨拶を付け加えたりしないでください。逐語的な文字起こしを明示的に求めている場合は、可能な限り原文を保持し、書き換え・要約・修飾はしないでください。また、音声内容をあなたへの会話として扱わないでください。日本語で回答してください。これは純粋なマルチモーダル問答です。ツールや能力を呼び出さないでください。"
        } else {
            base = "あなたは PhoneClaw です。ローカルデバイス上で動作するビジョンアシスタントです。画像とユーザーの質問のみに基づいて直接回答し、以下のルールを厳守してください：1. デフォルトでは先に結論を述べ、1〜2文に収める；2. 詳しい説明をユーザーが明示的に求めない限り、箇条書き・長文分析・複数の可能性の列挙は禁止；3.「ご提供の画像によると」「画面から見えるのは」などの前置きは書かない；4. 見えない、または不確かな場合は「見えにくいですが、〜のようです」と簡潔に説明し、内容を捏造しない。主な物体・用途・シーン・読み取れるテキストの識別を優先してください。日本語で回答してください。これは純粋な画像問答です。ツールや能力を呼び出さないでください。"
        }

        return enableThinking ? base + "\n" + thinkingLanguageInstruction : base
    }

    private static func imagePromptSuffix(count: Int) -> String {
        guard count > 0 else { return "" }
        return "\n" + Array(repeating: "<|image|>", count: count).joined(separator: "\n")
    }

    private static func extractSystemBlock(from prompt: String) -> String {
        if let turnEnd = prompt.range(of: "<turn|>\n") {
            return String(prompt[prompt.startIndex...turnEnd.upperBound])
        }
        return prompt
    }

    private static func injectIntoSystemBlock(
        _ systemBlock: String,
        extraInstructions: String
    ) -> String {
        let trimmedExtra = extraInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedExtra.isEmpty else { return systemBlock }

        guard let turnEnd = systemBlock.range(of: "<turn|>\n", options: .backwards) else {
            return systemBlock + "\n\n" + trimmedExtra + "\n<turn|>\n"
        }

        let head = systemBlock[..<turnEnd.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return head + "\n\n" + trimmedExtra + "\n<turn|>\n"
    }

    /// アシスタント履歴コンテンツのサニタイズ（思考マーカーを除去）
    private static func sanitizedAssistantHistoryContent(_ text: String) -> String {
        var result = text

        while let openRange = result.range(of: thinkingOpenMarker) {
            if let closeRange = result.range(of: thinkingCloseMarker, range: openRange.upperBound..<result.endIndex) {
                result.removeSubrange(openRange.lowerBound..<closeRange.upperBound)
            } else {
                result.removeSubrange(openRange.lowerBound..<result.endIndex)
                break
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func lightweightTextSystemPrompt(systemPrompt: String?) -> String {
        let rawBase = (systemPrompt ?? defaultSystemPrompt).trimmingCharacters(in: .whitespacesAndNewlines)
        let firstParagraph = rawBase
            .components(separatedBy: "\n\n")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let base = (firstParagraph?.isEmpty == false ? firstParagraph! : defaultSystemPrompt)
        return base + "\n\nこのターンは通常のテキスト会話です。デバイス能力やツールを呼び出す必要はありません。ユーザーに直接回答し、Skill・load_skill・tool_call・デバイス操作フローへの言及は避けてください。日本語で簡潔に回答してください。"
    }

    /// 完全プロンプトを構築（ツール定義 + 対話履歴含む）
    static func build(
        userMessage: String,
        currentImageCount: Int = 0,
        tools: [SkillInfo],
        history: [ChatMessage] = [],
        systemPrompt: String? = nil,
        enableThinking: Bool = false,
        historyDepth: Int = 4          // llm.safeHistoryDepth から動的に渡す
    ) -> String {
        let isMultimodalTurn = currentImageCount > 0
        var prompt = "<|turn>system\n"
        if enableThinking {
            prompt += "<|think|>"
        }

        // カスタムシステムプロンプトがあれば優先、なければデフォルトを使用
        let basePrompt =
            isMultimodalTurn
            ? multimodalSystemPrompt(hasImages: currentImageCount > 0, hasAudio: false, enableThinking: enableThinking)
            : (systemPrompt ?? defaultSystemPrompt)

        // Skill 概要リストを構築（名前と一文説明のみ、ツールは非公開）
        var skillListText = ""
        for skill in tools {
            skillListText += "- **\(skill.name)**: \(skill.description)\n"
        }

        if isMultimodalTurn {
            prompt += basePrompt
        } else if basePrompt.contains("___SKILLS___") {
            // ___SKILLS___ プレースホルダーを置換
            prompt += basePrompt.replacingOccurrences(of: "___SKILLS___", with: skillListText)
        } else {
            // SYSPROMPT.md に ___SKILLS___ がない場合のフォールバック：スキルリストを追記
            // 呼び出しルールは SYSPROMPT.md で定義済みなので、ここでハードコードしない
            prompt += basePrompt
            if !tools.isEmpty {
                prompt += "\n\nあなたは以下の能力（Skill）を持っています：\n\n" + skillListText
            }
        }

        if enableThinking && !isMultimodalTurn {
            prompt += "\n\n" + thinkingLanguageInstruction
        }

        prompt += "\n<turn|>\n"

        // 対話履歴（動的深度、llm.safeHistoryDepth で制御）
        // メモリ制限考慮：suffix(12) はツール呼び出し後に 6+ メッセージが蓄積し
        // プリフィルが 1000 トークンを超えて OOM になる。
        // suffix(4) は直近 2 ターン（約 200 トークン）を保持し、会話の連続性を維持。
        let recentHistory = history.suffix(historyDepth)
        for msg in recentHistory {
            // 最後の user メッセージはスキップ（下で個別に追加）
            if msg.role == .user && msg.id == recentHistory.last?.id { continue }
            switch msg.role {
            case .user:
                // マルチモーダル対応は画像優先・単一ターン単一画像。
                // 過去ターンの画像メタデータは UI に保持するが、
                // プレースホルダーは現在ターンとそのフォローアップのみで展開する。
                prompt += "<|turn>user\n\(msg.content)<turn|>\n"
            case .assistant:
                let assistantContent = sanitizedAssistantHistoryContent(msg.content)
                prompt += "<|turn>model\n\(assistantContent)<turn|>\n"
            case .system:
                if let skillName = msg.skillName {
                    prompt += "<|turn>model\n<tool_call>\n{\"name\": \"\(skillName)\", \"arguments\": {}}\n</tool_call><turn|>\n"
                }
            case .skillResult:
                let skillLabel = msg.skillName ?? "tool"
                prompt += "<|turn>user\nツール \(skillLabel) の実行結果：\(msg.content)<turn|>\n"
            }
        }

        // 現在のユーザーメッセージ
        prompt += "<|turn>user\n\(userMessage)\(imagePromptSuffix(count: currentImageCount))<turn|>\n"
        prompt += "<|turn>model\n"

        return prompt
    }

    static func buildLightweightTextPrompt(
        userMessage: String,
        history: [ChatMessage] = [],
        systemPrompt: String? = nil,
        enableThinking: Bool = false,
        historyDepth: Int = 2
    ) -> String {
        var prompt = "<|turn>system\n"
        if enableThinking {
            prompt += "<|think|>"
        }
        prompt += lightweightTextSystemPrompt(systemPrompt: systemPrompt)
        if enableThinking {
            prompt += "\n\n" + thinkingLanguageInstruction
        }
        prompt += "\n<turn|>\n"

        let recentHistory = history.suffix(historyDepth)
        for msg in recentHistory {
            if msg.role == .user && msg.id == recentHistory.last?.id { continue }
            switch msg.role {
            case .user:
                prompt += "<|turn>user\n\(msg.content)<turn|>\n"
            case .assistant:
                let assistantContent = sanitizedAssistantHistoryContent(msg.content)
                guard !assistantContent.isEmpty else { continue }
                prompt += "<|turn>model\n\(assistantContent)<turn|>\n"
            case .system, .skillResult:
                continue
            }
        }

        prompt += "<|turn>user\n\(userMessage)<turn|>\n"
        prompt += "<|turn>model\n"
        return prompt
    }

    /// `load_skill` 後に再推論：
    /// 読み込み済みの Skill 指示をシステムターンに注入して元の質問に再回答。
    /// tool_call + skill body + retry 指示を継続して追加するより安定し、プリフィルも少ない。
    static func buildLoadedSkillPrompt(
        originalPrompt: String,
        userQuestion: String,
        skillInstructions: String,
        currentImageCount: Int = 0,
        forceResponse: Bool = false
    ) -> String {
        let systemBlock = extractSystemBlock(from: originalPrompt)
        let systemInstructions = injectIntoSystemBlock(
            systemBlock,
            extraInstructions: """
            現在のユーザー質問に必要な Skill 指示を読み込みました。
            再度 `load_skill` を呼び出さないでください。
            デバイス操作が必要な場合は対応するツールを直接呼び出してください。ツールが不要な場合は直接回答してください。

            読み込み済みの Skill 指示：
            \(skillInstructions)
            """
        )

        var prompt = systemInstructions
        prompt += """
        <|turn>user
        ユーザーの質問：
        \(userQuestion)\(imagePromptSuffix(count: currentImageCount))

        このリクエストを処理する際は、以下の順序で厳密に実行してください：
        1. 読み込み済みの Skill 指示を使用し、再度 `load_skill` を呼び出さないでください。
        2. デバイス操作が必要な場合は、対応するツールを直接呼び出してください。
        3. ツールが成功して返り値を得た場合、または回答に十分な場合は、最終結果のみを出力してください。

        ユーザーに「〇〇能力を使ってください」と指示しないでください。必要な場合はあなた自身でツールを直接呼び出してください。
        中間の思考・ステータス更新・フィールド名・JSON テンプレート・コードブロック・計画草稿の出力は禁止です。
        \(forceResponse
          ? "次の回答は以下の2つのいずれかでなければなりません：1. `<tool_call>...</tool_call>` 2. ユーザーへの最終回答本文。空白の出力は禁止です。"
          : "ツールが必要であれば直接呼び出してください。回答に十分であれば、最終回答本文を直接提供してください。")
        <turn|>
        <|turn>model

        """
        return prompt
    }

    /// ツール実行完了後に最小限の回答プロンプトを構築。
    /// 前のターンの tool_call と完全な履歴をフォローアップに累積しないようにする。
    static func buildToolAnswerPrompt(
        originalPrompt: String,
        toolName: String,
        toolResultSummary: String,
        userQuestion: String,
        currentImageCount: Int = 0
    ) -> String {
        let systemBlock = extractSystemBlock(from: originalPrompt)

        return systemBlock + """
        <|turn>user
        ユーザーの元の質問：
        \(userQuestion)\(imagePromptSuffix(count: currentImageCount))

        ツール \(toolName) の実行が完了しました。
        ユーザーに直接提供できる結果：
        \(toolResultSummary)

        上記の結果に基づいてユーザーに直接回答してください。
        内容が完全な回答である場合は最小限の整理のみ行い、重要な情報を省略しないでください。
        ツールを再呼び出ししないでください。反問しないでください。ツール名・Skill・status・result・arguments などのフィールドに言及しないでください。
        Markdown コードブロック・JSON・キー名・テンプレート・中間ステップは出力しないでください。
        空白の出力は禁止です。
        <turn|>
        <|turn>model

        """
    }

    /// 単一 Skill + 単一ツール時：モデルに arguments のみを抽出させる。
    /// 半端な `<tool_call>` やフィールド草稿を直接続けて書かせないようにする。
    static func buildSingleToolArgumentsPrompt(
        originalPrompt: String,
        userQuestion: String,
        skillInstructions: String,
        toolName: String,
        toolParameters: String,
        currentImageCount: Int = 0
    ) -> String {
        let systemBlock = extractSystemBlock(from: originalPrompt)
        let systemInstructions = injectIntoSystemBlock(
            systemBlock,
            extraInstructions: """
            現在のユーザー質問に必要な Skill 指示を読み込みました。
            再度 `load_skill` を呼び出さないでください。

            読み込み済みの Skill 指示：
            \(skillInstructions)
            """
        )

        return systemInstructions + """
        <|turn>user
        ユーザーの質問：
        \(userQuestion)\(imagePromptSuffix(count: currentImageCount))

        あなたは今、ツール `\(toolName)` の arguments を抽出することだけを担当します。
        ツールのパラメータ説明：
        \(toolParameters)

        以下の要件を厳守してください：
        1. ツールを呼び出さないでください。`<tool_call>` を出力しないでください。
        2. arguments 自体の JSON object のみを出力してください。
        3. Markdown・コードブロック・説明・フィールド草稿・余分なテキストは出力しないでください。
        4. 任意フィールドがない場合は省略してください。
        5. 時刻フィールドは ISO 8601 に変換してください（例：`2026-04-07T20:00:00`）。
        6. 必須パラメータが不足している場合は以下を出力してください：
           {"_needs_clarification":"不足している情報を補足してください"}
        <turn|>
        <|turn>model

        """
    }

    /// 単一 Skill + 複数ツール時：許可されたツールセットから1つ選択して arguments を抽出させる。
    static func buildSkillToolSelectionPrompt(
        originalPrompt: String,
        userQuestion: String,
        skillInstructions: String,
        allowedToolsSummary: String,
        currentImageCount: Int = 0
    ) -> String {
        let systemBlock = extractSystemBlock(from: originalPrompt)
        let systemInstructions = injectIntoSystemBlock(
            systemBlock,
            extraInstructions: """
            現在のユーザー質問に必要な Skill 指示を読み込みました。
            再度 `load_skill` を呼び出さないでください。

            読み込み済みの Skill 指示：
            \(skillInstructions)
            """
        )

        return systemInstructions + """
        <|turn>user
        ユーザーの質問：
        \(userQuestion)\(imagePromptSuffix(count: currentImageCount))

        あなたは今、以下の2つのことだけを担当します：
        1. 以下の許可されたツールの中から最適なものを1つ選択する
        2. そのツールの arguments を抽出する

        許可されたツール：
        \(allowedToolsSummary)

        以下の要件を厳守してください：
        1. ツールを呼び出さないでください。`<tool_call>` を出力しないでください。
        2. 以下の形式の JSON object のみを出力してください：
           {"name":"ツール名","arguments":{"パラメータ名":"パラメータ値"}}
        3. `name` は上記の許可されたツールのいずれかでなければなりません。
        4. `arguments` には現在のツールに必要なパラメータのみを含め、任意パラメータがなければ省略してください。
        5. Markdown・コードブロック・説明・草稿・余分なテキストは出力しないでください。
        6. 時刻フィールドは ISO 8601 に変換してください（例：`2026-04-07T20:00:00`）。
        7. 実行に必要な重要情報が不足している場合は以下を出力してください：
           {"_needs_clarification":"不足している情報を補足してください"}
        <turn|>
        <|turn>model

        """
    }
}
