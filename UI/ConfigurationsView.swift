import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ConfigurationsView: View {
    enum Tab: Int, CaseIterable {
        case model, prompt, local, permission
        var title: String {
            switch self {
            case .model: return "モデル設定"
            case .prompt: return "プロンプト"
            case .local: return "ローカル"
            case .permission: return "権限"
            }
        }
    }

    @Bindable var engine: AgentEngine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var selectedTab: Tab = .model
    @State private var selectedModelID = MLXLocalLLMService.defaultModel.id
    @State private var maxTokens: Double = 4000
    @State private var topK: Double = 64
    @State private var topP: Double = 0.95
    @State private var temperature: Double = 1.0
    @State private var systemPrompt: String = ""
    @State private var permissionStatuses: [AppPermissionKind: AppPermissionStatus] = [:]
    @State private var requestingPermission: AppPermissionKind?

    @State private var showFilePicker = false
    @State private var customModelPaths: [String: URL] = [:]
    @State private var customModelNameInput = ""
    @State private var showCustomModelAlert = false
    @State private var pendingCustomURL: URL?

    @State private var selectedPromptIDs: Set<UUID> = []
    @State private var promptEditorTarget: PromptPreset?
    @State private var promptEditorTitle = ""
    @State private var promptEditorBody = ""
    @State private var showPromptEditor = false

    @State private var modelToDelete: BundledModelOption?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(Tab.allCases, id: \.rawValue) { tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTab = tab
                            }
                        } label: {
                            Text(tab.title)
                                .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .medium))
                                .foregroundStyle(selectedTab == tab ? Theme.bg : Theme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .background(
                                    Group {
                                        if selectedTab == tab {
                                            RoundedRectangle(cornerRadius: 10).fill(Theme.accent)
                                        } else {
                                            RoundedRectangle(cornerRadius: 10).fill(Theme.bgElevated)
                                        }
                                    }
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)

                Rectangle().fill(Theme.border).frame(height: 1)

                Group {
                    switch selectedTab {
                    case .model: modelTab
                    case .prompt: promptTab
                    case .local: localModelTab
                    case .permission: permissionsTab
                    }
                }

                Rectangle().fill(Theme.border).frame(height: 1)

                HStack(spacing: 14) {
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
            .background(Theme.bgElevated)
        }
        .preferredColorScheme(.dark)
        .onAppear { loadCurrentSettings() }
        #if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            engine.llm.refreshModelInstallStates()
            refreshPermissionStatuses()
            customModelPaths = MLXLocalLLMService.customModelPaths
        }
        #endif
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                pendingCustomURL = url
                showCustomModelAlert = true
            }
        }
        .alert("モデル名を入力", isPresented: $showCustomModelAlert) {
            TextField("例: my-model-4bit", text: $customModelNameInput)
            Button("追加") {
                if let url = pendingCustomURL, !customModelNameInput.isEmpty {
                    MLXLocalLLMService.registerCustomModel(name: customModelNameInput, url: url)
                    customModelPaths = MLXLocalLLMService.customModelPaths
                    customModelNameInput = ""
                    pendingCustomURL = nil
                }
            }
            Button("キャンセル", role: .cancel) {
                customModelNameInput = ""
                pendingCustomURL = nil
            }
        }
        .alert("モデルを削除しますか？", isPresented: Binding(
            get: { modelToDelete != nil },
            set: { if !$0 { modelToDelete = nil } }
        )) {
            Button("削除", role: .destructive) {
                guard let target = modelToDelete else { return }
                do {
                    try engine.llm.deleteModel(target)
                } catch {
                    engine.llm.statusMessage = "削除に失敗: \(error.localizedDescription)"
                }
                modelToDelete = nil
            }
            Button("キャンセル", role: .cancel) { modelToDelete = nil }
        } message: {
            Text("ダウンロード済みのモデルファイルを削除します。")
        }
        .sheet(isPresented: $showPromptEditor) {
            NavigationStack {
                VStack(spacing: 12) {
                    TextField("タイトル", text: $promptEditorTitle)
                        .textFieldStyle(.roundedBorder)
                    TextEditor(text: $promptEditorBody)
                        .padding(10)
                        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 10))
                    Spacer()
                }
                .padding()
                .navigationTitle(promptEditorTarget == nil ? "新規プロンプト" : "プロンプト編集")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if let target = promptEditorTarget {
                            Button(role: .destructive) {
                                engine.deletePromptPreset(id: target.id)
                                showPromptEditor = false
                            } label: { Image(systemName: "trash") }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("適用") {
                            if let target = promptEditorTarget {
                                engine.updatePromptPreset(id: target.id, title: promptEditorTitle, body: promptEditorBody)
                                engine.applyPromptPreset(target.id)
                            } else {
                                engine.savePromptAsPreset(title: promptEditorTitle, body: promptEditorBody)
                            }
                            syncPromptFromEngine()
                            showPromptEditor = false
                        }
                    }
                }
            }
        }
    }

    // MARK: - タブボタン

    private var modelTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                storageSection
                modelSection
                configSlider(title: "最大トークン数", value: $maxTokens, range: 128...8192, displayValue: "\(Int(maxTokens))")
                configSlider(title: "サンプリング TopK", value: $topK, range: 1...128, displayValue: "\(Int(topK))")
                configSlider(title: "サンプリング TopP", value: $topP, range: 0...1, displayValue: String(format: "%.2f", topP))
                configSlider(title: "温度", value: $temperature, range: 0...2, displayValue: String(format: "%.2f", temperature))
            }
            .padding()
        }
    }

    private var promptTab: some View {
        VStack(spacing: 12) {
            HStack {
                Button("新規") {
                    promptEditorTarget = nil
                    promptEditorTitle = ""
                    promptEditorBody = systemPrompt
                    showPromptEditor = true
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.accent.opacity(0.15), in: Capsule())

                Button("一括削除") {
                    engine.deletePromptPresets(ids: selectedPromptIDs)
                    selectedPromptIDs.removeAll()
                    syncPromptFromEngine()
                }
                .disabled(selectedPromptIDs.isEmpty)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.bgElevated, in: Capsule())

                Spacer()
            }
            .padding(.horizontal)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(engine.promptPresets.presets) { preset in
                        HStack(spacing: 12) {
                            Button {
                                if selectedPromptIDs.contains(preset.id) {
                                    selectedPromptIDs.remove(preset.id)
                                } else {
                                    selectedPromptIDs.insert(preset.id)
                                }
                            } label: {
                                Image(systemName: selectedPromptIDs.contains(preset.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedPromptIDs.contains(preset.id) ? Theme.accent : Theme.textTertiary)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(preset.title).font(.subheadline.weight(.semibold))
                                Text(preset.body).font(.caption).foregroundStyle(Theme.textTertiary).lineLimit(2)
                            }
                            Spacer()
                            Button("適用") {
                                engine.applyPromptPreset(preset.id)
                                syncPromptFromEngine()
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            Button {
                                promptEditorTarget = preset
                                promptEditorTitle = preset.title
                                promptEditorBody = preset.body
                                showPromptEditor = true
                            } label: { Image(systemName: "square.and.pencil") }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border, lineWidth: 1))
                    }
                }
                .padding()
            }
        }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ストレージ").font(.headline)
            if let storage = engine.llm.deviceStorageInfo() {
                ProgressView(value: Double(storage.usedBytes), total: Double(storage.totalBytes))
                    .tint(Theme.accent)
                Text("使用 \(formatBytes(storage.usedBytes)) / 総容量 \(formatBytes(storage.totalBytes))（空き \(formatBytes(storage.freeBytes))）")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("ストレージ情報を取得できません").font(.caption).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(14)
        .background(Theme.bgElevated, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border, lineWidth: 1))
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
                                    HStack(spacing: 6) {
                                        Text("画像対応")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(Theme.accentGreen)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Theme.accentGreen.opacity(0.16), in: Capsule())
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
                    if let url = URL(string: "https://huggingface.co/mlx-community") {
                        Button("Hugging Face からモデルを探す") { openURL(url) }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .padding(14)
                .background(Theme.bgElevated, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border, lineWidth: 1))

                VStack(alignment: .leading, spacing: 10) {
                    Text("ローカルAPI")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)

                    Toggle("サーバーを有効化", isOn: Binding(
                        get: { engine.localAPIServerEnabled },
                        set: { enabled in
                            if enabled {
                                engine.startLocalAPIServer()
                            } else {
                                engine.stopLocalAPIServer()
                            }
                        }
                    ))
                    .toggleStyle(.switch)

                    Text("URL: \(engine.localAPIBaseURL())")
                        .font(.caption.monospaced())
                        .foregroundStyle(Theme.textSecondary)
                    Text("Token: \(engine.localAPIToken)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(Theme.textTertiary)
                        .textSelection(.enabled)

                    Button("トークン再生成") {
                        engine.regenerateLocalAPIToken()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)

                    Text("同一LANのみで利用し、Authorization: Bearer <token> ヘッダを必須にしてください。")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
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
            Text("推奨: \(engine.llm.recommendedModelID() == selectedModelID ? "このモデル" : engine.llm.recommendedModelID())")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)

            Text(engine.llm.isLoaded
                 ? "読み込み済み：" + engine.llm.modelDisplayName
                 : engine.llm.statusMessage)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

            VStack(spacing: 10) {
                ForEach(engine.availableModels) { model in
                    let state = engine.llm.installState(for: model)
                    let health = engine.llm.modelHealth(for: model)
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
                                Toggle("", isOn: Binding(
                                    get: { selectedModelID == model.id },
                                    set: { if $0 { selectedModelID = model.id } }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                            }
                        }

                        HStack(spacing: 8) {
                            Text("容量: \(formatBytes(engine.llm.modelDirectorySizeBytes(model)))")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                            Text("推定 \(String(format: "%.2f", model.estimatedSizeGB))GB")
                                .font(.caption2)
                                .foregroundStyle(Theme.textTertiary)
                            if model.supportsImage {
                                Text("画像対応")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Theme.accentGreen)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Theme.accentGreen.opacity(0.14), in: Capsule())
                            }
                        }

                        switch health {
                        case .healthy:
                            Text("状態: 正常")
                                .font(.caption2)
                                .foregroundStyle(Theme.accentGreen)
                        case .missingFiles(let files):
                            Text("不足ファイル: \(files.joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundStyle(Theme.accent)
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

            HStack(spacing: 10) {
                Button("Inject") {
                    _ = engine.llm.injectModel(id: selectedModelID)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.accent.opacity(0.15), in: Capsule())

                Button("Reject") { engine.llm.rejectCurrentModel() }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.bg, in: Capsule())

                Spacer()

                if let target = engine.availableModels.first(where: { $0.id == selectedModelID }) {
                    Button("削除") { modelToDelete = target }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }

                if let target = engine.availableModels.first(where: { $0.id == selectedModelID }),
                   let hf = MLXLocalLLMService.huggingFaceURL(for: target) {
                    Button("HF") { openURL(hf) }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
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
        syncPromptFromEngine()
        refreshPermissionStatuses()
        customModelPaths = MLXLocalLLMService.customModelPaths
    }

    private func applySettings() -> Bool {
        let modelChanged = engine.config.selectedModelID != selectedModelID

        engine.config.maxTokens = Int(maxTokens)
        engine.config.topK = Int(topK)
        engine.config.topP = topP
        engine.config.temperature = temperature
        engine.config.systemPrompt = systemPrompt
        if let selectedPreset = engine.promptPresets.selectedPresetID {
            engine.updatePromptPreset(id: selectedPreset, title: engine.promptPresets.selectedPreset?.title ?? "現在のプロンプト", body: systemPrompt)
        }

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

    private func syncPromptFromEngine() {
        engine.syncSystemPromptFromSelectedPreset()
        systemPrompt = engine.config.systemPrompt
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

private extension ModelInstallState {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
