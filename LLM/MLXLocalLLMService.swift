import Foundation
import CoreImage
import MLX
import MLXLLM
import MLXLMCommon
import MLXVLM
#if canImport(UIKit)
import UIKit
#endif

// MARK: - MLX Local LLM Service

extension UserInput: @unchecked Sendable {}

public struct BundledModelOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let directoryName: String
    public let displayName: String
    public let repositoryID: String
    public let requiredFiles: [String]
    public let estimatedSizeGB: Double
    public let supportsImage: Bool
}

public enum ModelInstallState: Equatable, Sendable {
    case notInstalled
    case checkingSource
    case downloading(completedFiles: Int, totalFiles: Int, currentFile: String)
    case downloaded
    case bundled
    case failed(String)
}

public enum ModelHealthState: Equatable, Sendable {
    case healthy
    case missingFiles([String])
}

public struct DeviceStorageInfo: Sendable {
    public let totalBytes: Int64
    public let freeBytes: Int64
    public let usedBytes: Int64
}

/// MLX GPU inference service for Gemma 4.
/// Forces MLX Metal GPU path — no CPU fallback.
@Observable
public class MLXLocalLLMService: LLMEngine {
    private final class GenerationState: @unchecked Sendable {
        var resolvedMaxOutputTokens: Int
        var firstTokenTime: Double?
        var tokenCount: Int = 0
        var hitTokenCap: Bool = false

        init(resolvedMaxOutputTokens: Int) {
            self.resolvedMaxOutputTokens = resolvedMaxOutputTokens
        }
    }
    // MARK: - Custom Model Support
    /// ユーザーが「ファイルを選択」でインポートしたモデルのパス
    ///
    /// - Note: LiveContainer などの環境では MainActor の分離が厳密に検証され、
    ///   `MainActor.assumeIsolated` の誤用がプロセスを SIGTRAP で落とすことがある。
    ///   ここは UI 状態ではなく永続ストレージ(UserDefaults)へのアクセスなので、
    ///   MainActor への隔離を外して同期的に扱う。
    public static var customModelPaths: [String: URL] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "customModelPaths"),
                  let decoded = try? JSONDecoder().decode([String: String].self, from: data)
            else { return [:] }
            return decoded.compactMapValues { URL(string: $0) }
        }
        set {
            let encoded = newValue.compactMapValues { $0.absoluteString }
            let data = try? JSONEncoder().encode(encoded)
            UserDefaults.standard.set(data, forKey: "customModelPaths")
        }
    }

    public static func registerCustomModel(name: String, url: URL) {
        var paths = customModelPaths
        paths[name] = url
        customModelPaths = paths
    }

    public static func unregisterCustomModel(name: String) {
        var paths = customModelPaths
        paths.removeValue(forKey: name)
        customModelPaths = paths
    }

    public static func huggingFaceURL(for model: BundledModelOption) -> URL? {
        URL(string: "https://huggingface.co/\(model.repositoryID)")
    }
    static let availableModels: [BundledModelOption] = [
        .init(
            id: "gemma-4-e2b-it-4bit",
            directoryName: "gemma-4-e2b-it-4bit",
            displayName: "Gemma 4 E2B",
            repositoryID: "mlx-community/gemma-4-e2b-it-4bit",
            requiredFiles: [
                "config.json",
                "generation_config.json",
                "model.safetensors",
                "model.safetensors.index.json",
                "processor_config.json",
                "tokenizer.json",
                "tokenizer_config.json",
                "chat_template.jinja"
            ],
            estimatedSizeGB: 3.58,
            supportsImage: true
        ),
        .init(
            id: "gemma-4-e4b-it-4bit",
            directoryName: "gemma-4-e4b-it-4bit",
            displayName: "Gemma 4 E4B",
            repositoryID: "mlx-community/gemma-4-e4b-it-4bit",
            requiredFiles: [
                "config.json",
                "generation_config.json",
                "model.safetensors",
                "model.safetensors.index.json",
                "processor_config.json",
                "tokenizer.json",
                "tokenizer_config.json",
                "chat_template.jinja"
            ],
            estimatedSizeGB: 5.22,
            supportsImage: true
        )
    ]
    static let defaultModel = availableModels[0]
    private static let multimodalMaxOutputTokens = 512
    private static let e4bThinkingMaxOutputTokens = 1_024
    private static let e2bThinkingMaxOutputTokens = 768
    private static let e4bModelID = "gemma-4-e4b-it-4bit"
    private static let e2bModelID = "gemma-4-e2b-it-4bit"
    private static let e4bMultimodalCriticalHeadroomMB = 320

    private struct MultimodalRuntimeBudget {
        let imageSoftTokenCap: Int?
        let maxOutputTokens: Int
        let headroomMB: Int
    }

    private struct ThinkingRuntimeBudget {
        let maxOutputTokens: Int
        let headroomMB: Int
    }

    private struct TextRuntimeBudget {
        let maxOutputTokens: Int
        let headroomMB: Int
    }

    // MARK: - State

    public private(set) var isLoaded = false
    public private(set) var isLoading = false
    public private(set) var isGenerating = false
    public private(set) var stats = LLMStats()
    public var statusMessage = "モデルの読み込みを待っています..."
    public private(set) var selectedModel = defaultModel
    public private(set) var loadedModel: BundledModelOption?
    public var modelDisplayName: String { loadedModel?.displayName ?? selectedModel.displayName }
    public var selectedModelID: String { selectedModel.id }
    public var loadedModelID: String? { loadedModel?.id }
    public private(set) var modelInstallStates: [String: ModelInstallState] = [:]

    // MARK: - Compatibility Settings

    public var useGPU = true
    public var samplingTopK: Int = 40
    public var samplingTopP: Float = 0.95
    public var samplingTemperature: Float = 1.0
    public var maxOutputTokens: Int = 4000

    private var modelContainer: ModelContainer?
    private var cancelled = false
    private var currentLoadTask: Task<Void, Never>?
    private var currentGenerationTask: Task<Void, Never>?
    private var currentDownloadTasks: [String: Task<Void, Never>] = [:]
    private let foregroundStateLock = NSLock()
    private var foregroundGPUAllowed = true
    private var lifecycleObserverTokens: [NSObjectProtocol] = []
    private var audioCapabilityEnabled = false

    /// Local path to the model directory
    private var modelPath: URL {
        Self.resolveModelPath(for: selectedModel)
    }

    // MARK: - Init

    public init(selectedModelID: String? = nil) {
        if let selectedModelID,
           let option = Self.availableModels.first(where: { $0.id == selectedModelID }) {
            self.selectedModel = option
        }
        self.stats.backend = "mlx-gpu"
        configureLifecycleObservers()
        cleanupStalePartialDirectories()
        refreshModelInstallStates()
    }

    deinit {
        for token in lifecycleObserverTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    /// Convenience init with default model location
    public convenience init() {
        self.init(selectedModelID: nil)
    }

    public func selectModel(id: String) -> Bool {
        guard let option = Self.availableModels.first(where: { $0.id == id }),
              option != selectedModel else {
            return false
        }

        selectedModel = option
        statusMessage = isLoaded
            ? "「\(option.displayName)」を選択しました。再読み込みの準備中..."
            : "「\(option.displayName)」を選択しました。読み込み待機中..."
        return true
    }

    private static func resolveModelPath(for model: BundledModelOption) -> URL {
        // 1. ユーザー登録のカスタムパスを最優先で確認
        if let customURL = customModelPaths[model.id] {
            return customURL
        }
        // 2. バンドル内蔵
        if let bundledPath = bundledModelPath(for: model) {
            return bundledPath
        }
        // 3. ダウンロード済み
        return downloadedModelPath(for: model)
    }

    private static func documentsModelsRoot() -> URL {
        let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        return documentsPath.appendingPathComponent("models", isDirectory: true)
    }

    private static func downloadedModelPath(for model: BundledModelOption) -> URL {
        documentsModelsRoot().appendingPathComponent(model.directoryName, isDirectory: true)
    }

    private static func partialModelPath(for model: BundledModelOption) -> URL {
        documentsModelsRoot().appendingPathComponent("\(model.directoryName).partial", isDirectory: true)
    }

    private static func bundledModelPath(for model: BundledModelOption) -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }

        let directBundleDir = resourceURL.appendingPathComponent(
            model.directoryName,
            isDirectory: true
        )
        if hasRequiredFiles(for: model, at: directBundleDir) {
            return directBundleDir
        }

        let nestedBundleDir = resourceURL
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(model.directoryName, isDirectory: true)
        if hasRequiredFiles(for: model, at: nestedBundleDir) {
            return nestedBundleDir
        }

        return nil
    }

    private static func hasRequiredFiles(for model: BundledModelOption, at directory: URL) -> Bool {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        return model.requiredFiles.allSatisfy { file in
            fm.fileExists(atPath: directory.appendingPathComponent(file).path)
        }
    }

    private static func directorySize(at root: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                values.isRegularFile == true,
                let fileSize = values.fileSize
            else { continue }
            total += Int64(fileSize)
        }
        return total
    }

    public func isModelAvailable(_ model: BundledModelOption) -> Bool {
        Self.bundledModelPath(for: model) != nil
            || Self.hasRequiredFiles(for: model, at: Self.downloadedModelPath(for: model))
    }

    public func installState(for model: BundledModelOption) -> ModelInstallState {
        if Self.bundledModelPath(for: model) != nil {
            return .bundled
        }
        if Self.hasRequiredFiles(for: model, at: Self.downloadedModelPath(for: model)) {
            return .downloaded
        }
        return modelInstallStates[model.id] ?? .notInstalled
    }

    public func modelHealth(for model: BundledModelOption) -> ModelHealthState {
        let path = Self.resolveModelPath(for: model)
        let missing = model.requiredFiles.filter { file in
            !FileManager.default.fileExists(atPath: path.appendingPathComponent(file).path)
        }
        return missing.isEmpty ? .healthy : .missingFiles(missing)
    }

    public func modelDirectorySizeBytes(_ model: BundledModelOption) -> Int64 {
        Self.directorySize(at: Self.resolveModelPath(for: model))
    }

    public func deleteModel(_ model: BundledModelOption) throws {
        guard Self.bundledModelPath(for: model) == nil else {
            throw MLXError.bundledModelRemovalNotAllowed(model.displayName)
        }
        let path = Self.downloadedModelPath(for: model)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
        refreshModelInstallStates()
    }

    @discardableResult
    public func injectModel(id: String) -> Bool {
        guard selectModel(id: id) else { return false }
        loadModel()
        return true
    }

    public func rejectCurrentModel() {
        unload()
    }

    public func deviceStorageInfo() -> DeviceStorageInfo? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        guard let values = try? documents.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]) else {
            return nil
        }
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let free = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        guard total > 0 else { return nil }
        return DeviceStorageInfo(totalBytes: total, freeBytes: free, usedBytes: max(total - free, 0))
    }

    public func recommendedModelID() -> String {
        availableHeadroomMB >= 1400 ? Self.e4bModelID : Self.e2bModelID
    }

    public func refreshModelInstallStates() {
        cleanupStalePartialDirectories()
        for model in Self.availableModels {
            if Self.bundledModelPath(for: model) != nil {
                modelInstallStates[model.id] = .bundled
            } else if Self.hasRequiredFiles(for: model, at: Self.downloadedModelPath(for: model)) {
                modelInstallStates[model.id] = .downloaded
            } else if case .checkingSource = modelInstallStates[model.id] {
                continue
            } else if case .downloading = modelInstallStates[model.id] {
                continue
            } else {
                modelInstallStates[model.id] = .notInstalled
            }
        }
    }

    private func cleanupStalePartialDirectories() {
        let fm = FileManager.default
        for model in Self.availableModels {
            let partialDirectory = Self.partialModelPath(for: model)
            if fm.fileExists(atPath: partialDirectory.path) {
                try? fm.removeItem(at: partialDirectory)
            }
        }
    }

    private func huggingFaceURL(for model: BundledModelOption, file: String) -> URL? {
        let rawPath = "\(model.repositoryID)/resolve/main/\(file)"
        return URL(string: "https://huggingface.co/" + rawPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!.replacingOccurrences(of: "%2F", with: "/"))
    }

    public func downloadModel(id: String) async {
        guard let model = Self.availableModels.first(where: { $0.id == id }) else { return }
        if isModelAvailable(model) {
            refreshModelInstallStates()
            return
        }
        if currentDownloadTasks[id] != nil {
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            let modelsRoot = Self.documentsModelsRoot()
            let finalDirectory = Self.downloadedModelPath(for: model)
            let partialDirectory = Self.partialModelPath(for: model)

            await MainActor.run {
                self.modelInstallStates[id] = .checkingSource
            }

            do {
                if !fm.fileExists(atPath: modelsRoot.path) {
                    try fm.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
                }
                if fm.fileExists(atPath: partialDirectory.path) {
                    try fm.removeItem(at: partialDirectory)
                }
                try fm.createDirectory(at: partialDirectory, withIntermediateDirectories: true)

                let totalFiles = model.requiredFiles.count
                for (index, file) in model.requiredFiles.enumerated() {
                    guard let url = huggingFaceURL(for: model, file: file) else {
                        throw DownloadError.invalidURL(file)
                    }

                    await MainActor.run {
                        self.modelInstallStates[id] = .downloading(
                            completedFiles: index,
                            totalFiles: totalFiles,
                            currentFile: file
                        )
                    }

                    let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 1800)
                    let (temporaryURL, response) = try await URLSession.shared.download(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw DownloadError.invalidResponse
                    }
                    guard (200...299).contains(http.statusCode) else {
                        throw DownloadError.httpStatus(http.statusCode)
                    }

                    let destinationURL = partialDirectory.appendingPathComponent(file)
                    let parentDirectory = destinationURL.deletingLastPathComponent()
                    if !fm.fileExists(atPath: parentDirectory.path) {
                        try fm.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
                    }
                    if fm.fileExists(atPath: destinationURL.path) {
                        try fm.removeItem(at: destinationURL)
                    }
                    try fm.moveItem(at: temporaryURL, to: destinationURL)
                }

                if fm.fileExists(atPath: finalDirectory.path) {
                    try fm.removeItem(at: finalDirectory)
                }
                try fm.moveItem(at: partialDirectory, to: finalDirectory)

                await MainActor.run {
                    self.modelInstallStates[id] = .downloaded
                    self.refreshModelInstallStates()
                }
            } catch {
                try? fm.removeItem(at: partialDirectory)
                await MainActor.run {
                    self.modelInstallStates[id] = .failed(error.localizedDescription)
                }
            }

            await MainActor.run {
                self.currentDownloadTasks[id] = nil
            }
        }

        currentDownloadTasks[id] = task
        await task.value
    }

    func loadModel() {
        currentLoadTask?.cancel()
        currentLoadTask = Task { [weak self] in
            guard let self else { return }
            defer { self.currentLoadTask = nil }
            do {
                if self.isLoading {
                    return
                }
                try await load()
                try await warmup()
            } catch is CancellationError {
                await MainActor.run {
                    if self.statusMessage.contains("読み込") || self.statusMessage.contains("初期化") {
                        self.statusMessage = "モデルの切り替えをキャンセルしました"
                    }
                }
            } catch {
                if let mlxError = error as? MLXError,
                   case .modelDirectoryMissing = mlxError {
                    statusMessage = "設定から\(self.selectedModel.displayName)モデルをダウンロードしてください"
                } else {
                    statusMessage = "❌ \(error.localizedDescription)"
                }
                self.isLoaded = false
                self.loadedModel = nil
                self.refreshModelInstallStates()
                print("[MLX] Load failed: \(error.localizedDescription)")
            }
        }
    }

    func generateStream(
        prompt: String,
        images: [CIImage] = [],
        audios: [UserInput.Audio] = [],
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        Task {
            var fullResponse = ""

            do {
                for try await token in generateStream(prompt: prompt, images: images, audios: audios) {
                    fullResponse += token
                    await MainActor.run {
                        onToken(token)
                    }
                }
                let response = fullResponse

                await MainActor.run {
                    onComplete(.success(response))
                }
            } catch {
                await MainActor.run {
                    onComplete(.failure(error))
                }
            }
        }
    }

    func generateStream(
        chat: [Chat.Message],
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        Task {
            var fullResponse = ""

            do {
                for try await token in generateStream(chat: chat) {
                    fullResponse += token
                    await MainActor.run {
                        onToken(token)
                    }
                }
                let response = fullResponse

                await MainActor.run {
                    onComplete(.success(response))
                }
            } catch {
                await MainActor.run {
                    onComplete(.failure(error))
                }
            }
        }
    }

    func generateStream(
        chat: [Chat.Message],
        additionalContext: [String: any Sendable]?,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        Task {
            var fullResponse = ""

            do {
                for try await token in generateStream(chat: chat, additionalContext: additionalContext) {
                    fullResponse += token
                    await MainActor.run {
                        onToken(token)
                    }
                }
                let response = fullResponse

                await MainActor.run {
                    onComplete(.success(response))
                }
            } catch {
                await MainActor.run {
                    onComplete(.failure(error))
                }
            }
        }
    }

    // MARK: - LLMEngine Protocol

    public func load() async throws {
        if isLoading {
            return
        }
        let model = selectedModel
        let path = Self.resolveModelPath(for: model)
        isLoading = true
        defer {
            isLoading = false
        }
        statusMessage = "モデルを初期化中..."
        Gemma4Registration.setAudioCapabilityEnabled(audioCapabilityEnabled)
        await Gemma4Registration.register()

        guard Self.hasRequiredFiles(for: model, at: path) else {
            throw MLXError.modelDirectoryMissing(model.displayName)
        }

        statusMessage = "\(model.displayName)を読み込んでいます..."
        let loadStart = CFAbsoluteTimeGetCurrent()
        print("[MLX] load capability — audio=\(audioCapabilityEnabled ? 1 : 0)")

        // ── Memory diagnostics (read before load) ──────────────────────────────
        let physMB = Double(ProcessInfo.processInfo.physicalMemory) / 1_048_576
        let (footprintBefore, limitBefore) = appMemoryFootprintMB()
        print("[MEM] Physical RAM: \(Int(physMB)) MB")
        print("[MEM] Before load — footprint: \(Int(footprintBefore)) MB, jetsam limit: \(Int(limitBefore)) MB")
        print("[MEM] MLX before — active: \(MLX.GPU.activeMemory / 1_048_576) MB, cache: \(MLX.GPU.cacheMemory / 1_048_576) MB")

        let container = try await VLMModelFactory.shared.loadContainer(
            from: path,
            using: MLXTokenizersLoader()
        )

        try Task.checkCancellation()
        self.modelContainer = container
        self.isLoaded = true
        self.loadedModel = model

        // ── Memory diagnostics (read after load) ───────────────────────────────
        let (footprintAfter, _) = appMemoryFootprintMB()
        print("[MEM] After load  — footprint: \(Int(footprintAfter)) MB")
        print("[MEM] MLX after   — active: \(MLX.GPU.activeMemory / 1_048_576) MB, cache: \(MLX.GPU.cacheMemory / 1_048_576) MB")

        let elapsed = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000
        stats.loadTimeMs = elapsed
        statusMessage = "モデルの準備完了 ✅ (\(Int(elapsed))ms)"

        print("[MLX] Model loaded in \(Int(elapsed))ms — backend: mlx-gpu — model: \(model.displayName)")
    }

    private func ensureAudioCapability(hasAudio: Bool) async throws {
        guard hasAudio != audioCapabilityEnabled || !isLoaded || modelContainer == nil else {
            return
        }

        audioCapabilityEnabled = hasAudio
        print("[MLX] capability switch requested — audio=\(hasAudio ? 1 : 0)")

        if isLoaded || modelContainer != nil {
            await prepareForReload(cancelCurrentGeneration: false, cancelCurrentLoad: false)
        }

        try await load()
    }

    /// Returns (footprint MB, jetsam limit MB) via task_info.
    private func appMemoryFootprintMB() -> (Double, Double) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, 0) }
        let footprint = Double(info.phys_footprint) / 1_048_576
        let limit     = Double(info.limit_bytes_remaining) / 1_048_576 + footprint
        return (footprint, limit)
    }

    /// 当前可用内存 headroom（MB）。Agent 用来动态调整 history 深度。
    public var availableHeadroomMB: Int {
        let (footprint, limit) = appMemoryFootprintMB()
        return max(0, Int(limit - footprint))
    }

    /// 根据当前剩余内存推荐安全的 history 深度（消息条数）。
    /// E4B 在 1 GB 左右 headroom 时对文本 KV cache 非常敏感，因此需要更激进地收紧历史。
    public var safeHistoryDepth: Int {
        let h = availableHeadroomMB
        let model = loadedModel ?? Self.availableModels.first(where: { $0.id == selectedModel.id })

        if model?.id == Self.e4bModelID {
            switch h {
            case 1_700...: return 4
            case 1_100..<1_700: return 2
            default: return 0
            }
        } else {
            switch h {
            case 1_500...: return 4
            case  900..<1_500: return 2
            default: return 0
            }
        }
    }


    public func warmup() async throws {
        // Warmup skipped for E2B.
        //
        // E2B has 26 layers (E4B has 42). Running MLXLMCommon.generate() for the first time
        // triggers Metal JIT shader compilation across all unique kernel variants
        // (attention, MLP, PLE, RoPE ...). This compilation adds a temporary
        // memory spike on top of the already-loaded 4.9 GB weights, which pushes
        // the process past the jetsam limit on iPhone 17 Pro Max.
        //
        // Skipping warmup means the first user inference compiles shaders lazily
        // (first response is ~2-3s slower) but avoids the OOM kill on startup.
        print("[MLX] Warmup skipped — shaders will compile on first inference")
        statusMessage = "モデルの準備完了 ✅"
    }

    public func generateStream(
        prompt: String,
        images: [CIImage],
        audios: [UserInput.Audio]
    ) -> AsyncThrowingStream<String, Error> {
        let input: UserInput
        if images.isEmpty, audios.isEmpty {
            input = UserInput(prompt: prompt)
        } else {
            input = UserInput(
                chat: [
                    .user(
                        prompt,
                        images: images.map { .ciImage($0) },
                        audios: audios
                    )
                ]
            )
        }
        return generateStream(input: input, isMultimodal: !images.isEmpty || !audios.isEmpty)
    }

    public func generateStream(chat: [Chat.Message]) -> AsyncThrowingStream<String, Error> {
        generateStream(chat: chat, additionalContext: nil)
    }

    public func generateStream(
        chat: [Chat.Message],
        additionalContext: [String: any Sendable]?
    ) -> AsyncThrowingStream<String, Error> {
        let input = UserInput(chat: chat, additionalContext: additionalContext)
        let hasMedia = !input.images.isEmpty || !input.audios.isEmpty
        return generateStream(input: input, isMultimodal: hasMedia)
    }

    private func dynamicMultimodalBudget(
        hasImages: Bool,
        hasAudio: Bool
    ) throws -> MultimodalRuntimeBudget? {
        guard hasImages || hasAudio else { return nil }
        guard let model = loadedModel ?? Self.availableModels.first(where: { $0.id == selectedModel.id }) else {
            return nil
        }
        let headroom = availableHeadroomMB

        guard model.id == Self.e4bModelID else {
            return MultimodalRuntimeBudget(
                imageSoftTokenCap: hasImages ? 160 : nil,
                maxOutputTokens: Self.multimodalMaxOutputTokens,
                headroomMB: headroom
            )
        }

        guard headroom > Self.e4bMultimodalCriticalHeadroomMB else {
            let recommendation = "请关闭后台应用后重试，或减少附件数量。\(currentMultimodalFallbackRecommendation())"
            throw MLXError.multimodalMemoryRisk(
                model: model.displayName,
                headroomMB: headroom,
                recommendation: recommendation
            )
        }

        let imageSoftTokenCap: Int?
        let maxOutputTokens: Int

        // Budget calibration (E4B, measured on-device):
        //   Actual activation cost ≈ 1 MB/output token
        //   (observed: 160 tokens consumed 167 MB headroom = 5311-5144 MB footprint delta)
        //   Safety margin formula: headroom − (imageSoftTokens × 2 MB) − (maxOut × 1 MB) > 300 MB
        switch headroom {
        case ..<500:
            imageSoftTokenCap = hasImages ? 48 : nil
            maxOutputTokens = 120           // was 64 — 48×2 + 120×1 + 300 = 516, fits <500 boundary
        case ..<700:
            imageSoftTokenCap = hasImages ? 64 : nil
            maxOutputTokens = 200           // was 128 — 64×2 + 200 + 300 = 628 < 700 ✓
        case ..<900:
            imageSoftTokenCap = hasImages ? 80 : nil
            maxOutputTokens = 340           // was 192 — 80×2 + 340 + 300 = 800 < 900 ✓
        case ..<1_100:
            imageSoftTokenCap = hasImages ? 96 : nil
            maxOutputTokens = Self.multimodalMaxOutputTokens   // 512: 96×2 + 512 + 300 = 1004 < 1100 ✓
        case ..<1_300:
            imageSoftTokenCap = hasImages ? 128 : nil
            maxOutputTokens = Self.multimodalMaxOutputTokens
        default:
            imageSoftTokenCap = hasImages ? 160 : nil
            maxOutputTokens = Self.multimodalMaxOutputTokens
        }

        print(
            "[MEM] multimodal runtime budget — model=\(model.displayName), "
                + "headroom=\(headroom) MB, "
                + "imageSoftTokenCap=\(imageSoftTokenCap.map(String.init) ?? "n/a"), "
                + "maxOutputTokens=\(maxOutputTokens), "
                + "audio=\(hasAudio ? 1 : 0)"
        )

        return MultimodalRuntimeBudget(
            imageSoftTokenCap: imageSoftTokenCap,
            maxOutputTokens: maxOutputTokens,
            headroomMB: headroom
        )
    }

    private func isThinkingEnabled(for input: UserInput) -> Bool {
        if let enabled = input.additionalContext?["enable_thinking"] as? Bool, enabled {
            return true
        }

        switch input.prompt {
        case .text(let text):
            return text.contains("<|think|>")
        case .chat(let messages):
            return messages.contains { $0.content.contains("<|think|>") }
        case .messages(let messages):
            return messages.contains { message in
                if let content = message["content"] as? String {
                    return content.contains("<|think|>")
                }
                if let content = message["content"] as? [[String: any Sendable]] {
                    return content.contains { item in
                        (item["text"] as? String)?.contains("<|think|>") == true
                    }
                }
                return false
            }
        }
    }

    private func dynamicThinkingBudget(
        enabled: Bool
    ) -> ThinkingRuntimeBudget? {
        guard enabled else { return nil }
        guard let model = loadedModel ?? Self.availableModels.first(where: { $0.id == selectedModel.id }) else {
            return nil
        }

        let headroom = availableHeadroomMB
        let maxOutputTokens: Int

        if model.id == Self.e4bModelID {
            switch headroom {
            case ..<500:
                maxOutputTokens = 128
            case ..<700:
                maxOutputTokens = 192
            case ..<900:
                maxOutputTokens = 256
            case ..<1_100:
                maxOutputTokens = 384
            case ..<1_300:
                maxOutputTokens = 512
            default:
                maxOutputTokens = Self.e4bThinkingMaxOutputTokens
            }
        } else {
            switch headroom {
            case ..<500:
                maxOutputTokens = 192
            case ..<800:
                maxOutputTokens = 384
            case ..<1_200:
                maxOutputTokens = 512
            default:
                maxOutputTokens = Self.e2bThinkingMaxOutputTokens
            }
        }

        print(
            "[MEM] thinking runtime budget — model=\(model.displayName), "
                + "headroom=\(headroom) MB, "
                + "maxOutputTokens=\(maxOutputTokens)"
        )

        return ThinkingRuntimeBudget(
            maxOutputTokens: maxOutputTokens,
            headroomMB: headroom
        )
    }

    private func dynamicTextBudget(
        enabled: Bool
    ) -> TextRuntimeBudget? {
        guard enabled else { return nil }
        guard let model = loadedModel ?? Self.availableModels.first(where: { $0.id == selectedModel.id }) else {
            return nil
        }

        let headroom = availableHeadroomMB
        let maxOutputTokens: Int

        if model.id == Self.e4bModelID {
            switch headroom {
            case ..<500:
                maxOutputTokens = 256
            case ..<700:
                maxOutputTokens = 384
            case ..<900:
                maxOutputTokens = 512
            case ..<1_100:
                maxOutputTokens = 768
            case ..<1_300:
                maxOutputTokens = 1_024
            default:
                maxOutputTokens = 1_280
            }
        } else {
            switch headroom {
            case ..<500:
                maxOutputTokens = 384
            case ..<800:
                maxOutputTokens = 768
            case ..<1_200:
                maxOutputTokens = 1_024
            default:
                maxOutputTokens = 1_536
            }
        }

        print(
            "[MEM] text runtime budget — model=\(model.displayName), "
                + "headroom=\(headroom) MB, "
                + "maxOutputTokens=\(maxOutputTokens)"
        )

        return TextRuntimeBudget(
            maxOutputTokens: maxOutputTokens,
            headroomMB: headroom
        )
    }

    private func adjustedTextOutputTokens(
        baseMaxOutputTokens: Int,
        preparedSequenceLength: Int,
        thinkingEnabled: Bool
    ) -> Int? {
        guard let model = loadedModel ?? Self.availableModels.first(where: { $0.id == selectedModel.id }) else {
            return nil
        }

        let headroom = availableHeadroomMB
        let totalSequenceBudget: Int

        if model.id == Self.e4bModelID {
            if thinkingEnabled {
                switch headroom {
                case ..<500:
                    totalSequenceBudget = 320
                case ..<700:
                    totalSequenceBudget = 448
                case ..<900:
                    totalSequenceBudget = 576
                case ..<1_100:
                    totalSequenceBudget = 896
                case ..<1_300:
                    totalSequenceBudget = 1_152
                default:
                    totalSequenceBudget = 1_280
                }
            } else {
                switch headroom {
                case ..<500:
                    totalSequenceBudget = 384
                case ..<700:
                    totalSequenceBudget = 512
                case ..<900:
                    totalSequenceBudget = 640
                case ..<1_100:
                    totalSequenceBudget = 768
                case ..<1_300:
                    totalSequenceBudget = 896
                default:
                    totalSequenceBudget = 1_024
                }
            }
        } else {
            if thinkingEnabled {
                switch headroom {
                case ..<500:
                    totalSequenceBudget = 448
                case ..<800:
                    totalSequenceBudget = 640
                case ..<1_200:
                    totalSequenceBudget = 896
                default:
                    totalSequenceBudget = 1_152
                }
            } else {
                switch headroom {
                case ..<500:
                    totalSequenceBudget = 512
                case ..<800:
                    totalSequenceBudget = 768
                case ..<1_200:
                    totalSequenceBudget = 1_024
                default:
                    totalSequenceBudget = 1_280
                }
            }
        }

        let minimumOutputTokens = thinkingEnabled ? 96 : 128
        let adjustedMaxOutputTokens = min(
            baseMaxOutputTokens,
            max(minimumOutputTokens, totalSequenceBudget - preparedSequenceLength)
        )

        print(
            "[MEM] text sequence budget — model=\(model.displayName), "
                + "headroom=\(headroom) MB, "
                + "preparedTokens=\(preparedSequenceLength), "
                + "totalSequenceBudget=\(totalSequenceBudget), "
                + "adjustedMaxOutputTokens=\(adjustedMaxOutputTokens)"
        )

        return adjustedMaxOutputTokens
    }

    private func currentMultimodalFallbackRecommendation() -> String {
        if let e2b = Self.availableModels.first(where: { $0.id == Self.e2bModelID }) {
            if isModelAvailable(e2b) {
                return "如仍失败，可手动切换到 \(e2b.displayName) 处理图片或音频。"
            }
            return "如仍失败，可先下载并手动切换到 \(e2b.displayName)。"
        } else {
            return "如仍失败，请改用更轻量的模型处理图片或音频。"
        }
    }

    private func ensureForegroundGPUExecution() async throws {
        #if canImport(UIKit)
        let isActive = await MainActor.run {
            UIApplication.shared.applicationState == .active
        }
        setForegroundGPUAllowed(isActive)
        guard isActive else {
            throw MLXError.gpuExecutionRequiresForeground
        }
        #endif
    }

    private func configureLifecycleObservers() {
        #if canImport(UIKit)
        let center = NotificationCenter.default
        lifecycleObserverTokens = [
            center.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.handleApplicationLeavingForeground()
            },
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.handleApplicationLeavingForeground()
            },
            center.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.setForegroundGPUAllowed(true)
            },
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.setForegroundGPUAllowed(true)
            }
        ]

        Task { [weak self] in
            guard let self else { return }
            let isActive = await MainActor.run {
                UIApplication.shared.applicationState == .active
            }
            self.setForegroundGPUAllowed(isActive)
        }
        #endif
    }

    private func handleApplicationLeavingForeground() {
        setForegroundGPUAllowed(false)
        cancelled = true
        currentGenerationTask?.cancel()
        currentLoadTask?.cancel()
    }

    private func setForegroundGPUAllowed(_ allowed: Bool) {
        foregroundStateLock.lock()
        foregroundGPUAllowed = allowed
        foregroundStateLock.unlock()
    }

    private func isForegroundGPUAllowed() -> Bool {
        foregroundStateLock.lock()
        let allowed = foregroundGPUAllowed
        foregroundStateLock.unlock()
        return allowed
    }

    private func generateStream(
        input: UserInput,
        isMultimodal: Bool
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: MLXError.modelNotLoaded)
                    return
                }
                do {
                    try await self.ensureAudioCapability(hasAudio: !input.audios.isEmpty)
                } catch {
                    continuation.finish(throwing: error)
                    return
                }

                guard let container = modelContainer else {
                    continuation.finish(throwing: MLXError.modelNotLoaded)
                    return
                }

                // Free Metal buffers cached from previous inference before
                // allocating the new computation graph. Critical on low-headroom devices:
                // the follow-up prompt is longer than the first inference,
                // and without clearing, residual cache + new activations
                // exceed the 6GB jetsam limit on iPhone.
                MLX.GPU.clearCache()

                let thinkingEnabled = self.isThinkingEnabled(for: input)
                let textBudget = self.dynamicTextBudget(enabled: !isMultimodal)
                let runtimeBudget: MultimodalRuntimeBudget?
                do {
                    runtimeBudget = try self.dynamicMultimodalBudget(
                        hasImages: !input.images.isEmpty,
                        hasAudio: !input.audios.isEmpty
                    )
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
                let thinkingBudget = self.dynamicThinkingBudget(enabled: thinkingEnabled)
                Gemma4Processor.setRuntimeImageSoftTokenCap(runtimeBudget?.imageSoftTokenCap)
                defer {
                    Gemma4Processor.setRuntimeImageSoftTokenCap(nil)
                }
                let effectiveMaxOutputTokens: Int = {
                    let multimodalCap = isMultimodal
                        ? runtimeBudget?.maxOutputTokens ?? Self.multimodalMaxOutputTokens
                        : self.maxOutputTokens
                    let thinkingCap = thinkingBudget?.maxOutputTokens ?? self.maxOutputTokens
                    let textCap = textBudget?.maxOutputTokens ?? self.maxOutputTokens
                    return min(self.maxOutputTokens, multimodalCap, thinkingCap, textCap)
                }()
                let generationState = GenerationState(resolvedMaxOutputTokens: effectiveMaxOutputTokens)

                self.isGenerating = true
                self.cancelled = false
                let genStart = CFAbsoluteTimeGetCurrent()
                let (fp, _) = appMemoryFootprintMB()
                print("[MEM] generateStream start — footprint: \(Int(fp)) MB, MLX active: \(MLX.GPU.activeMemory / 1_048_576) MB")

                do {
                    try await self.ensureForegroundGPUExecution()
                    _ = try await container.perform { context in
                        try await self.ensureForegroundGPUExecution()
                        if isMultimodal {
                            print("[VLM] multimodal budget — maxOutputTokens=\(generationState.resolvedMaxOutputTokens)")
                        } else if thinkingEnabled {
                            print("[LLM] thinking budget — baseMaxOutputTokens=\(generationState.resolvedMaxOutputTokens)")
                        }
                        let preparedInput = try await context.processor.prepare(input: input)
                        if isMultimodal {
                            print("[VLM] prepared sequence length=\(preparedInput.text.tokens.dim(1))")
                        } else {
                            let preparedSequenceLength = preparedInput.text.tokens.dim(1)
                            print("[LLM] prepared sequence length=\(preparedSequenceLength)")
                            generationState.resolvedMaxOutputTokens =
                                self.adjustedTextOutputTokens(
                                    baseMaxOutputTokens: generationState.resolvedMaxOutputTokens,
                                    preparedSequenceLength: preparedSequenceLength,
                                    thinkingEnabled: thinkingEnabled
                                ) ?? generationState.resolvedMaxOutputTokens
                            if textBudget != nil {
                                print("[LLM] text budget — maxOutputTokens=\(generationState.resolvedMaxOutputTokens)")
                            } else if thinkingEnabled {
                                print("[LLM] thinking budget — maxOutputTokens=\(generationState.resolvedMaxOutputTokens)")
                            }
                        }
                        try await self.ensureForegroundGPUExecution()

                        _ = try MLXLMCommon.generate(
                            input: preparedInput,
                            parameters: .init(
                                maxTokens: generationState.resolvedMaxOutputTokens,
                                temperature: self.samplingTemperature,
                                topP: self.samplingTopP,
                                topK: self.samplingTopK
                            ),
                            context: context
                        ) { tokens in
                            if self.cancelled || !self.isForegroundGPUAllowed() {
                                return .stop
                            }

                            generationState.tokenCount = tokens.count
                            if generationState.firstTokenTime == nil {
                                generationState.firstTokenTime = (CFAbsoluteTimeGetCurrent() - genStart) * 1000
                            }

                            // Stream the latest token
                            if let lastToken = tokens.last {
                                let text = context.tokenizer.decode(tokenIds: [lastToken])
                                continuation.yield(text)
                            }

                            // Multimodal path uses a tighter generation budget on iPhone.
                            // If we hit the cap, signal truncation so the caller can append a notice.
                            if tokens.count >= generationState.resolvedMaxOutputTokens {
                                generationState.hitTokenCap = true
                                return .stop
                            }
                            return .more
                        }
                        return ()
                    }

                    let elapsed = CFAbsoluteTimeGetCurrent() - genStart
                    self.stats.ttftMs = generationState.firstTokenTime ?? 0
                    self.stats.tokensPerSec = elapsed > 0
                        ? Double(generationState.tokenCount) / elapsed : 0
                    self.stats.totalTokens = generationState.tokenCount

                    print(
                        "[MLX] Generated \(generationState.tokenCount) tokens in \(String(format: "%.1f", elapsed))s"
                    )
                    print(
                        "[MLX] TTFT: \(String(format: "%.0f", self.stats.ttftMs))ms, "
                            + "Speed: \(String(format: "%.1f", self.stats.tokensPerSec)) tok/s")

                    // 推理结束后立即释放 Metal activation 缓存，
                    // 确保下一轮有最大可用 headroom。
                    MLX.GPU.clearCache()
                    let (fpEnd, _) = appMemoryFootprintMB()
                    print("[MEM] generateStream end  — footprint: \(Int(fpEnd)) MB, headroom: \(self.availableHeadroomMB) MB")

                    // If we hit the token cap mid-sentence, append a visible notice.
                    // This makes truncation explicit rather than silently dropping content.
                    if generationState.hitTokenCap {
                        let isChinese = Locale.preferredLanguages.contains { $0.hasPrefix("zh") }
                        let modeLabel = isChinese
                            ? (thinkingEnabled ? "思考" : "输出")
                            : (thinkingEnabled ? "Thinking" : "Output")
                        continuation.yield("\n\n> ⚠️ \(modeLabel)已达内存安全上限（\(generationState.resolvedMaxOutputTokens) tokens），内容可能不完整。")
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }

                self.isGenerating = false
                self.currentGenerationTask = nil
            }

            currentGenerationTask = task
            continuation.onTermination = { [weak self] _ in
                task.cancel()
                if self?.currentGenerationTask?.isCancelled == true {
                    self?.currentGenerationTask = nil
                }
            }
        }
    }

    public func cancel() {
        cancelled = true
        currentGenerationTask?.cancel()
        currentLoadTask?.cancel()
    }

    public func prepareForReload(
        cancelCurrentGeneration: Bool = true,
        cancelCurrentLoad: Bool = true
    ) async {
        cancelled = true
        if cancelCurrentGeneration {
            currentGenerationTask?.cancel()
        }
        if cancelCurrentLoad {
            currentLoadTask?.cancel()
        }

        while isGenerating || isLoading {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        unload(
            cancelCurrentGeneration: cancelCurrentGeneration,
            cancelCurrentLoad: cancelCurrentLoad
        )
        MLX.GPU.clearCache()
        try? await Task.sleep(nanoseconds: 150_000_000)
    }

    public func unload() {
        unload(cancelCurrentGeneration: true, cancelCurrentLoad: true)
    }

    public func unload(
        cancelCurrentGeneration: Bool = true,
        cancelCurrentLoad: Bool = true
    ) {
        if cancelCurrentGeneration {
            currentGenerationTask?.cancel()
        }
        if cancelCurrentLoad {
            currentLoadTask?.cancel()
        }
        modelContainer = nil
        isLoaded = false
        isLoading = false
        isGenerating = false
        loadedModel = nil
        cancelled = false
        stats = LLMStats()
        stats.backend = "mlx-gpu"
        MLX.GPU.clearCache()
        statusMessage = "モデルのアンロード完了"
        print("[MLX] Model unloaded")
    }
}

// MARK: - Errors

enum MLXError: LocalizedError {
    case modelNotLoaded
    case modelDirectoryMissing(String)
    case gpuExecutionRequiresForeground
    case multimodalMemoryRisk(model: String, headroomMB: Int, recommendation: String)
    case bundledModelRemovalNotAllowed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "MLX model not loaded. Call load() first."
        case .modelDirectoryMissing(let modelName):
            return "\(modelName)のモデルファイルが見つかりません。設定からダウンロードまたは再インストールしてください。"
        case .gpuExecutionRequiresForeground:
            return "アプリがバックグラウンドに移行すると、GPU推論タスクを継続できません。"
        case .multimodalMemoryRisk(let model, let headroomMB, let recommendation):
            return "\(model) の剩りメモリは約 \(headroomMB) MBです。畫像/音声を処理続けるとシステムに強制終了される可能性があります。\(recommendation)"
        case .bundledModelRemovalNotAllowed(let modelName):
            return "同梱モデル「\(modelName)」は削除できません。"
        }
    }
}

enum DownloadError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let file):
            return "ダウンロードURLを構築できません：\(file)"
        case .invalidResponse:
            return "ダウンロード元のレスポンスが無効です"
        case .httpStatus(let statusCode):
            switch statusCode {
            case 401, 403:
                return "ダウンロード元へのアクセスが拒否されました（\(statusCode)）"
            case 404:
                return "モデルファイルが見つかりません（404）"
            case 429:
                return "ダウンロードが多すぎます。しばらく待ってから再試行してください（429）"
            default:
                return "ダウンロードに失敗しました。HTTP \(statusCode)"
            }
        }
    }
}
