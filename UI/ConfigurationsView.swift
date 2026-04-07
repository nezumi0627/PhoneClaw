import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 設定画面（iOS 版、Themeに合わせたダークカラー）

struct ConfigurationsView: View {
    @Bindable var engine: AgentEngine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    // 0=モデル設定, 1=システムプロンプト, 2=ローカルモデル, 3=権限
    @State private var selectedTab = 0

    // ローカル編集状態（確定後に適用）
    @State private var selectedModelID = MLXLocalLLMService.defaultModel.id
    @State private var maxTokens: Double = 4000
    @State private var topK: Double = 64
    @State private var topP: Double = 0.95
    @State private var temperature: Double = 1.0
    @State private var systemPrompt: String = ""
    @State private var permissionStatuses: [AppPermissionKind: AppPermissionStatus] = [:]
    @State private var requestingPermission: AppPermissionKind?

    // カスタムモデル関連
    @State private var showFilePicker = false
    @State private var customModelPaths: [String: URL] = [:]
    @State private var customModelNameInput = ""
    @State private var showCustomModelAlert = false
    @State private var pendingCustomURL: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // タブ切り替え
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        tabButton("モデル設定", tag: 0)
                        tabButton("システムプロンプト", tag: 1)
                        tabButton("ローカルモデル", tag: 2)
                        tabButton("権限", tag: 3)
                    }
                    .padding(.horizontal)
                }

                Rectangle().fill(Theme.border).frame(height: 1)

                Group {
                    if selectedTab == 0 {
                        modelConfigsTab
                    } else if selectedTab == 1 {
                        systemPromptTab
                    } else if selectedTab == 2 {
                        localModelTab
                    } else {
                        permissionsTab
                    }
                }

                Rectangle().fill(Theme.border).frame(height: 1)

                // 下部ボタン
                HStack(spacing: 20) {
                    Spacer()
                    Button("キャンセル") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                    Button("OK") {
                        if applySettings() { dismiss() }
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(Theme.accent.opacity(0.15), in: Capsule())
                }
                .padding()
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .background(Theme.bgElevated)
        }
        .preferredColorScheme(.dark)
        .onAppear { loadCurrentSettings() }
        #if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            engine.llm.refreshModelInstallStates()
            refreshPermissionStatuses()
        }
        #endif
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    pendingCustomURL = url
                    showCustomModelAlert = true
                }
            case .failure:
                break
            }
        }
        .alert("モデル名を入力", isPresented: $showCustomModelAlert) {
            TextField("例: my-model-4bit", text: $customModelNameInput)
            Button("追加") {
                if let url = pendingCustomURL, !customModelNameInput.isEmpty {
                    // セキュリティスコープ付きアクセスを開始
                    let accessed = url.startAccessingSecurityScopedResource()
                    Task { @MainActor in
                        MLXLocalLLMService.registerCustomModel(name: customModelNameInput, url: url)
                        customModelPaths = MLXLocalLLMService.customModelPaths
                        if accessed { url.stopAccessingSecurityScopedResource() }
                    }
                    customModelNameInput = ""
                    pendingCustomURL = nil
                }
            }
            Button("キャンセル", role: .cancel) {
                customModelNameInput = ""
                pendingCustomURL = nil
            }
        } message: {
            Text("このフォルダに登録する名前（モデルID）を入力してください。\n例: gemma-4-e2b-it-4bit")
        }
    }

    // MARK: - タブボタン

    private func tabButton(_ title: String, tag: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tag }
        } label: {
            VStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(selectedTab == tag ? .semibold : .regular))
                    .foregroundStyle(selectedTab == tag ? Theme.textPrimary : Theme.textTertiary)
                    .lineLimit(1)

                Rectangle()
                    .fill(selectedTab == tag ? Theme.accent : .clear)
                    .frame(height: 2)
            }
        }
        .frame(minWidth: 80)
    }

    // MARK: - モデル設定タブ

    private var modelConfigsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                modelSection
                configSlider(title: "最大トークン数", value: $maxTokens, range: 128...8192, displayValue: "\(Int(maxTokens))")
                configSlider(title: "サンプリング TopK", value: $topK, range: 1...128, displayValue: "\(Int(topK))")
                configSlider(title: "サンプリング TopP", value: $topP, range: 0...1, displayValue: String(format: "%.2f", topP))
                configSlider(title: "温度", value: $temperature, range: 0...2, displayValue: String(format: "%.2f", temperature))
            }
            .padding()
        }
    }

    // MARK: - システムプロンプトタブ

    private var systemPromptTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $systemPrompt)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )

            Button("デフォルトに戻す") {
                systemPrompt = engine.defaultSystemPrompt
            }
            .font(.subheadline)
            .foregroundStyle(Theme.accent)
        }
        .padding()
    }

    // MARK: - ローカルモデルタブ（カスタムモデルフォルダ指定）

    private var localModelTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 説明セクション
                VStack(alignment: .leading, spacing: 8) {
                    Text("ローカルモデルの指定")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)

                    Text("iPhone/iPad のファイルアプリ（または PC から転送した）モデルフォルダを直接指定して使用できます。フォルダには config.json や tokenizer.json などの必要ファイルが含まれている必要があります。")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(14)
                .background(Theme.bgElevated, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border, lineWidth: 1))

                // 登録済みカスタムモデル一覧
                if !customModelPaths.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("登録済みモデル")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)

                        ForEach(Array(customModelPaths.keys.sorted()), id: \.self) { modelName in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(modelName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    if let url = customModelPaths[modelName] {
                                        Text(url.lastPathComponent)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(Theme.textTertiary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                Button {
                                    Task { @MainActor in
                                        MLXLocalLLMService.unregisterCustomModel(name: modelName)
                                        customModelPaths = MLXLocalLLMService.customModelPaths
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.accent)
                                        .frame(width: 32, height: 32)
                                        .background(Theme.accent.opacity(0.1), in: Circle())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(12)
                            .background(Theme.bg, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border, lineWidth: 1))
                        }
                    }
                    .padding(14)
                    .background(Theme.bgElevated, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border, lineWidth: 1))
                }

                // フォルダ追加ボタン
                Button {
                    showFilePicker = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 16, weight: .semibold))
                        Text("モデルフォルダを選択して追加")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Theme.bg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                // 使い方メモ
                VStack(alignment: .leading, spacing: 6) {
                    Text("使い方")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("1. PCからiPhone/iPadへファイルアプリ経由でモデルフォルダを転送する")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text("2. 「モデルフォルダを選択して追加」をタップし、フォルダを選択")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text("3. モデル名（ID）を入力して登録（例: gemma-4-e2b-it-4bit）")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text("4. モデル設定タブでそのIDのモデルを選択してOKを押す")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(14)
                .background(Theme.bgElevated, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border, lineWidth: 1))
            }
            .padding()
        }
    }

    // MARK: - 権限タブ

    private var permissionsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                permissionsSection
            }
            .padding()
        }
    }

    // MARK: - スライダー

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("モデル")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            Text(engine.llm.isLoaded
                 ? "読み込み済み：" + engine.llm.modelDisplayName
                 : engine.llm.statusMessage)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

            VStack(spacing: 10) {
                ForEach(engine.availableModels) { model in
                    let state = engine.llm.installState(for: model)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(model.id)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(Theme.textTertiary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 8) {
                                modelStateControl(for: model, state: state)

                                if selectedModelID == model.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.accent)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }
                        }

                        if let detail = modelStateDetail(state) {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(state.isFailure ? Theme.accent : Theme.textTertiary)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(selectedModelID == model.id ? Theme.accentSubtle : Theme.bg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                selectedModelID == model.id ? Theme.accent : Theme.border,
                                lineWidth: 1
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { selectedModelID = model.id }
                }
            }

            Text(modelFooterText)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(14)
        .background(Theme.bgElevated, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border, lineWidth: 1))
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("権限")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            ForEach(AppPermissionKind.allCases) { kind in
                permissionRow(for: kind)
            }
        }
        .padding(14)
        .background(Theme.bgElevated, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border, lineWidth: 1))
    }

    private func permissionRow(for kind: AppPermissionKind) -> some View {
        let status = permissionStatuses[kind] ?? .notDetermined

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: kind.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28, height: 28)
                    .background(Theme.bg, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(permissionTitle(kind))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(permissionStatusLabel(status))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(status.isGranted ? Theme.accentGreen : Theme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                (status.isGranted ? Theme.accentGreen : Theme.accent).opacity(0.14),
                                in: Capsule()
                            )
                    }

                    Text(permissionDescription(kind))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)

                    Text(permissionStatusDetail(status))
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            HStack(spacing: 10) {
                if !status.isGranted {
                    Button(requestingPermission == kind ? "リクエスト中..." : "権限をリクエスト") {
                        requestPermission(kind)
                    }
                    .disabled(requestingPermission != nil)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.accent.opacity(0.15), in: Capsule())
                }

                Button("設定を開く") { openAppSettings() }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.bg, in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    private func configSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        displayValue: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 12) {
                Slider(value: value, in: range).tint(Theme.accent)

                Text(displayValue)
                    .font(.body.monospaced())
                    .foregroundStyle(Theme.textPrimary.opacity(0.8))
                    .frame(width: 56)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.bg, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    @ViewBuilder
    private func modelStateControl(for model: BundledModelOption, state: ModelInstallState) -> some View {
        switch state {
        case .notInstalled:
            Button("ダウンロード") {
                selectedModelID = model.id
                Task {
                    await engine.llm.downloadModel(id: model.id)
                    if engine.llm.isModelAvailable(model),
                       selectedModelID == model.id,
                       (!engine.llm.isLoaded || engine.llm.loadedModelID != model.id) {
                        engine.config.selectedModelID = model.id
                        engine.reloadModel()
                    }
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.accent.opacity(0.15), in: Capsule())

        case .checkingSource:
            modelBadge("確認中")

        case .downloading(let completedFiles, let totalFiles, _):
            modelBadge("ダウンロード中 \(completedFiles)/\(totalFiles)")

        case .downloaded:
            modelBadge("ダウンロード済み", color: Theme.accentGreen)

        case .bundled:
            modelBadge("バンドル済み", color: Theme.accentGreen)

        case .failed:
            Button("再試行") {
                selectedModelID = model.id
                Task { await engine.llm.downloadModel(id: model.id) }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.accent.opacity(0.15), in: Capsule())
        }
    }

    private func modelBadge(_ text: String, color: Color = Theme.textTertiary) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.14), in: Capsule())
    }

    private func modelStateDetail(_ state: ModelInstallState) -> String? {
        switch state {
        case .notInstalled:    return "未インストール"
        case .checkingSource:  return "ダウンロード元を確認しています。"
        case .downloading(_, _, let currentFile): return "ダウンロード中：\(currentFile)"
        case .downloaded:      return "デバイスにダウンロード済みで、すぐに読み込めます。"
        case .bundled:         return "このモデルはアプリに同梱されています。"
        case .failed(let message): return message
        }
    }

    private var modelFooterText: String {
        guard let selectedModel = engine.availableModels.first(where: { $0.id == selectedModelID }) else {
            return "モデルをダウンロードしてからOKをタップしてください。"
        }

        if !engine.llm.isModelAvailable(selectedModel) {
            return "選択したモデルをダウンロードしてからOKをタップして読み込んでください。"
        }

        if selectedModelID == engine.llm.selectedModelID,
           engine.llm.loadedModelID == selectedModelID,
           engine.llm.isLoaded {
            return "OKをタップすると現在のモデルを維持します。"
        }

        return "OKをタップすると現在のモデルをアンロードして新しいモデルを読み込みます。"
    }

    // MARK: - 設定の読み込み / 適用

    private func permissionTitle(_ kind: AppPermissionKind) -> String {
        switch kind {
        case .microphone: return "マイク"
        case .calendar:   return "カレンダー"
        case .reminders:  return "リマインダー"
        case .contacts:   return "連絡先"
        }
    }

    private func permissionDescription(_ kind: AppPermissionKind) -> String {
        switch kind {
        case .microphone: return "録音とリアルタイム音声入力を許可します"
        case .calendar:   return "カレンダーイベントの作成と書き込みを許可します"
        case .reminders:  return "リマインダーと ToDo の作成を許可します"
        case .contacts:   return "連絡先の保存と更新を許可します"
        }
    }

    private func permissionStatusLabel(_ status: AppPermissionStatus) -> String {
        switch status {
        case .notDetermined: return "未リクエスト"
        case .denied:        return "拒否済み"
        case .restricted:    return "制限あり"
        case .granted:       return "許可済み"
        }
    }

    private func permissionStatusDetail(_ status: AppPermissionStatus) -> String {
        switch status {
        case .notDetermined: return "初回使用時にシステム許可ダイアログが表示されます"
        case .denied:        return "設定アプリから手動で許可を有効にしてください"
        case .restricted:    return "このデバイスでは権限が制限されています"
        case .granted:       return "関連スキルを直接実行できます"
        }
    }

    private func loadCurrentSettings() {
        engine.llm.refreshModelInstallStates()
        selectedModelID = engine.llm.loadedModelID ?? engine.config.selectedModelID
        maxTokens = Double(engine.config.maxTokens)
        topK = Double(engine.config.topK)
        topP = engine.config.topP
        temperature = engine.config.temperature
        systemPrompt = engine.config.systemPrompt
        refreshPermissionStatuses()
        Task { @MainActor in
            customModelPaths = MLXLocalLLMService.customModelPaths
        }
    }

    private func applySettings() -> Bool {
        let modelChanged = engine.config.selectedModelID != selectedModelID

        engine.config.maxTokens = Int(maxTokens)
        engine.config.topK = Int(topK)
        engine.config.topP = topP
        engine.config.temperature = temperature
        engine.config.systemPrompt = systemPrompt

        // サンプリングパラメータを LLM に同期（次の生成から即反映）
        engine.applySamplingConfig()

        guard let selectedModel = engine.availableModels.first(where: { $0.id == selectedModelID }),
              engine.llm.isModelAvailable(selectedModel) else {
            if let missingModel = engine.availableModels.first(where: { $0.id == selectedModelID }) {
                engine.llm.statusMessage = "設定から「\(missingModel.displayName)」モデルをダウンロードしてください"
            }
            return false
        }

        engine.config.selectedModelID = selectedModelID
        let needsLoad = !engine.llm.isLoaded || engine.llm.loadedModelID != selectedModelID
        if modelChanged || needsLoad {
            engine.reloadModel()
        }
        return true
    }

    private func refreshPermissionStatuses() {
        permissionStatuses = engine.permissionStatuses()
    }

    private func requestPermission(_ kind: AppPermissionKind) {
        requestingPermission = kind
        Task {
            _ = await engine.requestPermission(kind)
            await MainActor.run {
                refreshPermissionStatuses()
                requestingPermission = nil
            }
        }
    }

    private func openAppSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
        #endif
    }
}

private extension ModelInstallState {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
