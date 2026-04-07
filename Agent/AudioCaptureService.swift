import AVFoundation
import Foundation
import Observation

struct AudioCaptureSnapshot: Sendable {
    let pcm: [Float]
    let sampleRate: Double
    let channelCount: Int
    let duration: TimeInterval
}

@MainActor
@Observable
final class AudioCaptureService {
    private static let preferredSampleRate: Double = 16_000
    private static let maxStoredSeconds: Double = 30

    var permissionStatus: AppPermissionStatus = .notDetermined
    var isCapturing = false
    var sampleRate: Double = 0
    var channelCount: Int = 0
    var capturedSampleCount = 0
    var bufferedSampleCount = 0
    var duration: TimeInterval = 0
    var peakLevel: Float = 0
    var statusText = ""
    var lastErrorMessage: String?

    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private let audioSession = AVAudioSession.sharedInstance()
    @ObservationIgnored private let pcmLock = NSLock()
    @ObservationIgnored private var rollingPCM: [Float] = []

    init() {
        refreshPermissionStatus()
    }

    func refreshPermissionStatus() {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                permissionStatus = .granted
            case .denied:
                permissionStatus = .denied
            case .undetermined:
                permissionStatus = .notDetermined
            @unknown default:
                permissionStatus = .restricted
            }
        } else {
            switch audioSession.recordPermission {
            case .granted:
                permissionStatus = .granted
            case .denied:
                permissionStatus = .denied
            case .undetermined:
                permissionStatus = .notDetermined
            @unknown default:
                permissionStatus = .restricted
            }
        }
    }

    @discardableResult
    func toggleCapture() async -> Bool {
        if isCapturing {
            stopCapture()
            return true
        } else {
            return await startCapture()
        }
    }

    @discardableResult
    func startCapture() async -> Bool {
        refreshPermissionStatus()
        if permissionStatus == .notDetermined {
            let granted = await requestPermission()
            guard granted else {
                lastErrorMessage = "マイクの権限が付与されていないため、録音を開始できません。"
                return false
            }
        }

        guard permissionStatus.isGranted else {
            lastErrorMessage = "マイクの権限が利用できません。設定アプリから許可してください。"
            return false
        }

        guard !isCapturing else { return true }

        resetCaptureState()
        lastErrorMessage = nil
        statusText = "録音の準備中..."

        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            try audioSession.setPreferredSampleRate(Self.preferredSampleRate)
            try audioSession.setActive(true)

            let inputNode = audioEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            sampleRate = inputFormat.sampleRate
            channelCount = Int(inputFormat.channelCount)

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
                self?.handleIncomingPCM(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            isCapturing = true
            updateStatusText()
            return true
        } catch {
            stopCapture(deactivateSession: false)
            lastErrorMessage = "録音の開始に失敗しました：\(error.localizedDescription)"
            statusText = lastErrorMessage ?? ""
            return false
        }
    }

    @discardableResult
    func stopCapture(deactivateSession: Bool = true) -> AudioCaptureSnapshot? {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        if deactivateSession {
            try? audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
        }

        let snapshot = latestSnapshot()
        isCapturing = false
        peakLevel = 0

        if let snapshot, snapshot.duration > 0 {
            statusText = String(
                format: "%.1f 秒の音声を録音しました（%.0f Hz、%d チャンネル）。モデルに送信できます。",
                snapshot.duration,
                snapshot.sampleRate,
                snapshot.channelCount
            )
        } else if lastErrorMessage == nil {
            statusText = ""
        }

        return snapshot
    }

    func clearStatus() {
        statusText = ""
        lastErrorMessage = nil
    }

    func consumeLatestSnapshot() -> AudioCaptureSnapshot? {
        let snapshot = latestSnapshot()
        resetCaptureState()
        clearStatus()
        return snapshot
    }

    func latestSnapshot() -> AudioCaptureSnapshot? {
        pcmLock.lock()
        let pcm = rollingPCM
        pcmLock.unlock()

        guard !pcm.isEmpty, sampleRate > 0 else { return nil }
        return AudioCaptureSnapshot(
            pcm: pcm,
            sampleRate: sampleRate,
            channelCount: 1,
            duration: Double(pcm.count) / sampleRate
        )
    }

    private func requestPermission() async -> Bool {
        let granted = await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                audioSession.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        refreshPermissionStatus()
        return granted
    }

    private func resetCaptureState() {
        pcmLock.lock()
        rollingPCM.removeAll(keepingCapacity: true)
        pcmLock.unlock()

        capturedSampleCount = 0
        bufferedSampleCount = 0
        duration = 0
        peakLevel = 0
        sampleRate = 0
        channelCount = 0
    }

    private func handleIncomingPCM(_ buffer: AVAudioPCMBuffer) {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        let formatChannelCount = Int(buffer.format.channelCount)
        guard let channelData = buffer.floatChannelData else { return }

        let samples: [Float]
        if formatChannelCount <= 1 {
            samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        } else {
            // 複数チャンネルをモノラルにミックスダウン
            var mixed = Array(repeating: Float.zero, count: frameCount)
            let scale = 1.0 / Float(formatChannelCount)
            for channel in 0 ..< formatChannelCount {
                let channelSamples = UnsafeBufferPointer(start: channelData[channel], count: frameCount)
                for index in 0 ..< frameCount {
                    mixed[index] += channelSamples[index] * scale
                }
            }
            samples = mixed
        }
        let rms = sqrt(samples.reduce(0) { $0 + ($1 * $1) } / Float(max(frameCount, 1)))
        let peak = samples.map { abs($0) }.max() ?? 0

        pcmLock.lock()
        rollingPCM.append(contentsOf: samples)
        // ローリングバッファの最大サイズを制限
        let maxStoredSamples = Int(max(sampleRate, Self.preferredSampleRate) * Self.maxStoredSeconds)
        if rollingPCM.count > maxStoredSamples {
            rollingPCM.removeFirst(rollingPCM.count - maxStoredSamples)
        }
        let bufferedCount = rollingPCM.count
        pcmLock.unlock()

        Task { @MainActor [weak self] in
            guard let self else { return }
            capturedSampleCount += frameCount
            bufferedSampleCount = bufferedCount
            if sampleRate == 0 {
                sampleRate = buffer.format.sampleRate
            }
            if channelCount == 0 {
                channelCount = 1
            }
            if sampleRate > 0 {
                duration = Double(capturedSampleCount) / sampleRate
            }
            peakLevel = max(rms, peak)
            updateStatusText()
        }
    }

    private func updateStatusText() {
        guard isCapturing else { return }
        statusText = String(
            format: "録音中 %.1f 秒 · %.0f Hz · バッファ %.1f 秒 PCM",
            duration,
            max(sampleRate, Self.preferredSampleRate),
            sampleRate > 0 ? Double(bufferedSampleCount) / sampleRate : 0
        )
    }
}
