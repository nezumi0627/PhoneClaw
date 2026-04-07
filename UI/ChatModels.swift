import SwiftUI

// MARK: - 表示モデル（クロスプラットフォーム共有）

/// 単一 Skill カードのデータ
struct SkillCard: Identifiable, Equatable {
    let id: UUID
    var skillName: String
    var skillStatus: String?   // "identified", "loaded", "executing", "done"
    var toolName: String?      // 実行中の具体的なツール名（例: "device-info"）
}

/// AI 回答ブロック：複数の Skill カード + 思考アニメーション + 回答テキスト
struct ResponseBlock: Identifiable, Equatable {
    let id: UUID
    var skills: [SkillCard] = []
    var thinkingText: String?
    var responseText: String?
    var isThinking: Bool
}

/// チャットリストの統一表示項目
enum DisplayItem: Identifiable {
    case user(ChatMessage)
    case response(ResponseBlock)

    var id: UUID {
        switch self {
        case .user(let msg): return msg.id
        case .response(let block): return block.id
        }
    }
}

// MARK: - メッセージ → 表示項目変換（クロスプラットフォーム共有）

/// 思考プレースホルダー用の安定した ID
private let thinkingPlaceholderID = UUID()
private let thinkingOpenMarker = "[[PHONECLAW_THINK]]"
private let thinkingCloseMarker = "[[/PHONECLAW_THINK]]"

/// テキストから思考チャンネルと回答テキストを分離
private func splitThinkingAndResponse(from text: String) -> (thinking: String?, response: String?) {
    guard !text.isEmpty else { return (nil, nil) }

    var remaining = text
    var thinkingChunks: [String] = []

    while let openRange = remaining.range(of: thinkingOpenMarker) {
        let thoughtStart = openRange.upperBound
        if let closeRange = remaining.range(of: thinkingCloseMarker, range: thoughtStart..<remaining.endIndex) {
            let thought = remaining[thoughtStart..<closeRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !thought.isEmpty {
                thinkingChunks.append(String(thought))
            }
            remaining.removeSubrange(openRange.lowerBound..<closeRange.upperBound)
        } else {
            let thought = remaining[thoughtStart..<remaining.endIndex]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !thought.isEmpty {
                thinkingChunks.append(String(thought))
            }
            remaining.removeSubrange(openRange.lowerBound..<remaining.endIndex)
            break
        }
    }

    let response = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
    return (
        thinkingChunks.isEmpty ? nil : thinkingChunks.joined(separator: "\n\n"),
        response.isEmpty ? nil : response
    )
}

func buildDisplayItems(from messages: [ChatMessage], isProcessing: Bool) -> [DisplayItem] {
    var items: [DisplayItem] = []
    var block: ResponseBlock? = nil

    func flush() {
        if let b = block { items.append(.response(b)); block = nil }
    }

    for msg in messages {
        switch msg.role {
        case .user:
            flush()
            items.append(.user(msg))
        case .system:
            if let name = msg.skillName {
                if block == nil { block = ResponseBlock(id: msg.id, isThinking: false) }

                let content = msg.content
                // 同名カードが既にある場合はステータスを更新、なければ新規作成
                if let idx = block?.skills.firstIndex(where: { $0.skillName == name }) {
                    if content.hasPrefix("executing:") {
                        block?.skills[idx].skillStatus = "executing"
                        block?.skills[idx].toolName = String(content.dropFirst("executing:".count))
                    } else {
                        block?.skills[idx].skillStatus = content
                    }
                } else {
                    var card = SkillCard(id: msg.id, skillName: name)
                    if content.hasPrefix("executing:") {
                        card.skillStatus = "executing"
                        card.toolName = String(content.dropFirst("executing:".count))
                    } else {
                        card.skillStatus = content
                    }
                    block?.skills.append(card)
                }
            } else if !msg.content.isEmpty {
                if block == nil { block = ResponseBlock(id: msg.id, isThinking: false) }
                let parsed = splitThinkingAndResponse(from: msg.content)
                if let thinking = parsed.thinking {
                    block?.thinkingText = thinking
                }
                block?.responseText = parsed.response
            }
        case .skillResult:
            break
        case .assistant:
            if block == nil { block = ResponseBlock(id: msg.id, isThinking: false) }
            if msg.content != "▍" && !msg.content.isEmpty {
                let parsed = splitThinkingAndResponse(from: msg.content)
                if let thinking = parsed.thinking {
                    block?.thinkingText = thinking
                }
                block?.responseText = parsed.response
            }
        }
    }

    if var b = block, !b.skills.isEmpty || b.thinkingText != nil || b.responseText != nil {
        if isProcessing && !b.skills.isEmpty && b.responseText == nil {
            b.isThinking = true
        }
        items.append(.response(b))
    }

    if isProcessing {
        let hasAI = block.map { !$0.skills.isEmpty || $0.thinkingText != nil || $0.responseText != nil } ?? false
        if !hasAI {
            items.append(.response(ResponseBlock(id: thinkingPlaceholderID, isThinking: true)))
        }
    }

    return items
}
