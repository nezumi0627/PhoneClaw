import Foundation

// MARK: - Skill データモデル
//
// ファイル駆動アーキテクチャ：
//   - SKILL.md が Skill のメタデータ + 指示本文を定義（ホットリロード対応）
//   - ToolRegistry.swift がネイティブツール実装を登録（コンパイル時）
//   - SkillLoader.swift が SKILL.md を解析・ロード
//
// 以下は UI と PromptBuilder が使用する軽量データ構造のみ。

// MARK: - スキルエントリー（UI管理用）

struct ToolInfo: Equatable {
    let name: String
    let description: String
    let parameters: String
}

struct SkillEntry: Identifiable {
    let id: String          // スキルディレクトリ名（例: "clipboard"）
    var name: String        // 表示名（例: "クリップボード"）
    var description: String
    var icon: String
    var samplePrompt: String
    var tools: [ToolInfo] = []
    var isEnabled: Bool = true
    var filePath: URL?      // SKILL.md のパス（編集用）

    /// SkillDefinition から変換
    init(from def: SkillDefinition, registry: ToolRegistry) {
        self.id = def.id
        self.name = def.metadata.displayName
        self.description = def.metadata.description
        self.icon = def.metadata.icon
        self.samplePrompt = def.metadata.examples.first?.query ?? ""
        self.isEnabled = def.isEnabled
        self.filePath = def.filePath
        self.tools = def.metadata.allowedTools.compactMap { toolName in
            guard let tool = registry.find(name: toolName) else { return nil }
            return ToolInfo(name: tool.name, description: tool.description, parameters: tool.parameters)
        }
    }
}

// MARK: - SkillInfo（PromptBuilder 向けの簡易説明）

struct SkillInfo {
    let name: String        // スキルID（例: "clipboard"）
    let description: String
    var displayName: String = ""
    var icon: String = "wrench"
    var samplePrompt: String = ""
}
