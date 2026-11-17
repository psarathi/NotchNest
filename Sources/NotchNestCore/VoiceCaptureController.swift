@preconcurrency import AVFoundation
import Foundation
import Observation
@preconcurrency import Speech

public enum VoiceAuthState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
}

/// Captures microphone speech locally via Apple's Speech framework for quick task dictation.
@MainActor
@Observable
public final class VoiceCaptureController {
    public private(set) var authState: VoiceAuthState = .notDetermined
    public private(set) var isRecording = false
    public private(set) var liveTranscript = ""
    public private(set) var audioLevel: Double = 0
    public private(set) var errorMessage: String?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

    public var onTranscriptUpdated: ((String) -> Void)?

    public init() {
        refreshAuthorizationStatus()
    }

    public func refreshAuthorizationStatus() {
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if speechStatus == .authorized && micStatus == .authorized {
            authState = .authorized
        } else if speechStatus == .denied || speechStatus == .restricted || micStatus == .denied || micStatus == .restricted {
            authState = .denied
        } else {
            authState = .notDetermined
        }
    }

    public func requestPermissions() async -> Bool {
        let speechGranted = await Self.requestSpeechAuthorization()
        let micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        refreshAuthorizationStatus()
        return speechGranted && micGranted
    }

    public func toggleRecording() async {
        if isRecording {
            stopRecording()
        } else {
            await startRecording()
        }
    }

    public func startRecording() async {
        errorMessage = nil
        refreshAuthorizationStatus()
        if authState != .authorized {
            let granted = await requestPermissions()
            guard granted else {
                errorMessage = "Enable Microphone & Speech Recognition in System Settings."
                return
            }
        }

        stopRecording()

        let speechRecognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognition unavailable right now."
            return
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13.0, *), speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            errorMessage = "No active microphone input detected."
            return
        }

        liveTranscript = ""
        audioLevel = 0
        self.recognizer = speechRecognizer
        self.recognitionRequest = request
        self.audioEngine = engine

        Self.installAudioTap(on: inputNode, format: format, request: request) { [weak self] level in
            Task { @MainActor [weak self] in
                self?.audioLevel = level
            }
        }

        do {
            engine.prepare()
            try engine.start()
            isRecording = true

            recognitionTask = Self.startRecognitionTask(
                recognizer: speechRecognizer,
                request: request
            ) { [weak self] text, shouldStop in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let text, !text.isEmpty {
                        self.liveTranscript = text
                        self.onTranscriptUpdated?(text)
                    }
                    if shouldStop {
                        self.stopRecording()
                    }
                }
            }
        } catch {
            stopRecording()
            errorMessage = "Could not start microphone input."
        }
    }

    public func stopRecording() {
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            engine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        recognizer = nil
        isRecording = false
        audioLevel = 0
    }

    // Constructed nonisolated so CoreAudio / Speech callbacks never inherit MainActor executor assertions.
    nonisolated private static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    nonisolated private static func installAudioTap(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest,
        onLevel: @escaping @Sendable (Double) -> Void
    ) {
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }
            var sum: Float = 0
            for i in stride(from: 0, to: frameLength, by: 4) {
                let s = channelData[i]
                sum += s * s
            }
            let rms = sqrt(sum / Float(max(1, frameLength / 4)))
            let normalized = min(1.0, Double(rms * 14.0))
            onLevel(normalized)
        }
    }

    nonisolated private static func startRecognitionTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onUpdate: @escaping @Sendable (String?, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let shouldStop = (result?.isFinal ?? false) || (error != nil)
            onUpdate(text, shouldStop)
        }
    }
}
