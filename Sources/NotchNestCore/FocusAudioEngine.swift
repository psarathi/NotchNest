import AVFoundation
import Foundation
import Observation

/// Synthesizes distinct procedural ambient focus soundscapes locally using AVAudioEngine (no bundled audio assets required).
@MainActor
@Observable
public final class FocusAudioEngine {
    public private(set) var isPlaying = false
    public private(set) var activeSoundscape: FocusSoundscape = .none

    private let stateBox = AudioDSPState()
    private var audioEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var fadeOutStopTask: Task<Void, Never>?

    public init() {}

    public func update(soundscape: FocusSoundscape, shouldPlay: Bool, volume: Double) {
        activeSoundscape = soundscape
        let effectivePlay = shouldPlay && soundscape != .none
        let clampedVolume = Float(min(max(volume, 0), 1))

        stateBox.configure(
            mode: Self.modeCode(for: soundscape),
            targetGain: effectivePlay ? clampedVolume * 0.48 : 0.0
        )

        if effectivePlay {
            fadeOutStopTask?.cancel()
            fadeOutStopTask = nil
            ensureStarted()
        } else {
            isPlaying = false
            fadeOutStopTask?.cancel()
            fadeOutStopTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self, !self.isPlaying else { return }
                self.stopEngine()
            }
        }
    }

    public func stop() {
        fadeOutStopTask?.cancel()
        fadeOutStopTask = nil
        stateBox.configure(mode: 0, targetGain: 0)
        isPlaying = false
        stopEngine()
    }

    private func ensureStarted() {
        if let engine = audioEngine, engine.isRunning {
            isPlaying = true
            return
        }

        let engine = AVAudioEngine()
        let mixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        let sampleRate = mixerFormat.sampleRate > 0 ? mixerFormat.sampleRate : 44_100
        let channels = max(1, min(2, Int(mixerFormat.channelCount)))
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels)) else {
            isPlaying = false
            return
        }

        let node = Self.makeSourceNode(
            sampleRate: Float(sampleRate),
            format: format,
            stateBox: stateBox
        )

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            self.audioEngine = engine
            self.sourceNode = node
            self.isPlaying = true
        } catch {
            self.audioEngine = nil
            self.sourceNode = nil
            self.isPlaying = false
        }
    }

    // Constructed nonisolated so CoreAudio's real-time IO thread never triggers a MainActor assertion.
    nonisolated private static func makeSourceNode(
        sampleRate: Float,
        format: AVAudioFormat,
        stateBox: AudioDSPState
    ) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let frames = Int(frameCount)
            let snapshot = stateBox.snapshot()

            let leftPtr = buffers.count > 0 ? buffers[0].mData?.assumingMemoryBound(to: Float.self) : nil
            let rightPtr = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
            guard leftPtr != nil || rightPtr != nil else {
                return noErr
            }

            for frame in 0..<frames {
                let sample = stateBox.nextStereoSample(mode: snapshot.mode, targetGain: snapshot.targetGain, sampleRate: sampleRate)
                leftPtr?[frame] = sample.left
                rightPtr?[frame] = sample.right
            }
            return noErr
        }
    }

    private func stopEngine() {
        audioEngine?.stop()
        if let sourceNode {
            audioEngine?.detach(sourceNode)
        }
        audioEngine = nil
        sourceNode = nil
    }

    private static func modeCode(for soundscape: FocusSoundscape) -> Int {
        switch soundscape {
        case .none: return 0
        case .rain: return 1
        case .brownNoise: return 2
        case .ocean: return 3
        case .cafe: return 4
        }
    }
}

private final class AudioDSPState: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var mode: Int = 0
    private var targetGain: Float = 0

    // Audio-thread-only DSP state
    private var activeMode: Int = 0
    private var currentGain: Float = 0
    private var rngLeft: UInt64 = 0x9E37_79B9_7F4A_7C15
    private var rngRight: UInt64 = 0xD1B5_4A32_D192_ED03
    private var rngEvents: UInt64 = 0x94D0_49BB_1331_11EB

    // Filter memory
    private var lp1L: Float = 0
    private var lp2L: Float = 0
    private var lp1R: Float = 0
    private var lp2R: Float = 0
    private var hpPrevL: Float = 0
    private var hpOutL: Float = 0
    private var hpPrevR: Float = 0
    private var hpOutR: Float = 0

    // Ocean & modulation phases
    private var wavePhase: Float = 0
    private var cafePhaseA: Float = 0
    private var cafePhaseB: Float = 0
    private var chordPhase: Float = 0

    // Stochastic droplet / ceramic ping voices (L & R)
    private var dropEnvL: Float = 0
    private var dropPhaseL: Float = 0
    private var dropFreqL: Float = 1800
    private var dropEnvR: Float = 0
    private var dropPhaseR: Float = 0
    private var dropFreqR: Float = 2200

    private var clinkEnv: Float = 0
    private var clinkPhaseA: Float = 0
    private var clinkPhaseB: Float = 0
    private var clinkPan: Float = 0.5

    func configure(mode: Int, targetGain: Float) {
        os_unfair_lock_lock(&lock)
        self.mode = mode
        self.targetGain = targetGain
        os_unfair_lock_unlock(&lock)
    }

    func snapshot() -> (mode: Int, targetGain: Float) {
        os_unfair_lock_lock(&lock)
        let m = mode
        let g = targetGain
        os_unfair_lock_unlock(&lock)
        return (m, g)
    }

    private func nextWhite(state: inout UInt64) -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let bits = Int32(bitPattern: UInt32(truncatingIfNeeded: state >> 32))
        return Float(bits) / Float(Int32.max)
    }

    private func nextUnitRandom() -> Float {
        rngEvents = rngEvents &* 6364136223846793005 &+ 1442695040888963407
        let top = UInt32(truncatingIfNeeded: rngEvents >> 40)
        return Float(top) / Float(1 << 24)
    }

    func nextStereoSample(mode: Int, targetGain: Float, sampleRate: Float) -> (left: Float, right: Float) {
        if mode != activeMode {
            activeMode = mode
            // Brief soft cross-reset when switching soundscapes so changes sound crisp without clicks
            currentGain *= 0.2
            dropEnvL = 0
            dropEnvR = 0
            clinkEnv = 0
            wavePhase = 0.9
        }

        currentGain += (targetGain - currentGain) * 0.0025
        if currentGain < 0.0001 && targetGain == 0 {
            return (0, 0)
        }

        let wL = nextWhite(state: &rngLeft)
        let wR = nextWhite(state: &rngRight)

        var outL: Float = 0
        var outR: Float = 0

        switch mode {
        case 1:
            // Rain: bright rainfall patter bed + distinct stereo micro-droplet splashes
            lp1L = 0.92 * lp1L + 0.08 * wL
            lp1R = 0.92 * lp1R + 0.08 * wR
            // High-pass sheen to keep rain crisp and airy
            hpOutL = 0.85 * (hpOutL + wL - hpPrevL)
            hpPrevL = wL
            hpOutR = 0.85 * (hpOutR + wR - hpPrevR)
            hpPrevR = wR

            if dropEnvL < 0.01 && nextUnitRandom() < (14.0 / sampleRate) {
                dropEnvL = 0.35 + 0.35 * nextUnitRandom()
                dropFreqL = 1200 + 2200 * nextUnitRandom()
                dropPhaseL = 0
            }
            if dropEnvR < 0.01 && nextUnitRandom() < (14.0 / sampleRate) {
                dropEnvR = 0.35 + 0.35 * nextUnitRandom()
                dropFreqR = 1300 + 2100 * nextUnitRandom()
                dropPhaseR = 0
            }

            dropPhaseL += (2 * .pi * dropFreqL) / sampleRate
            dropPhaseR += (2 * .pi * dropFreqR) / sampleRate
            dropEnvL *= 0.9965
            dropEnvR *= 0.9965

            let dropL = sinf(dropPhaseL) * dropEnvL * 0.22
            let dropR = sinf(dropPhaseR) * dropEnvR * 0.22

            outL = lp1L * 0.55 + hpOutL * 0.16 + dropL + dropR * 0.25
            outR = lp1R * 0.55 + hpOutR * 0.16 + dropR + dropL * 0.25

        case 2:
            // Brown noise: smooth 2-pole sub-bass blanket (~180 Hz cutoff, zero harsh high hiss)
            lp1L = 0.992 * lp1L + 0.032 * wL
            lp2L = 0.980 * lp2L + 0.020 * lp1L
            lp1R = 0.992 * lp1R + 0.032 * wR
            lp2R = 0.980 * lp2R + 0.020 * lp1R
            outL = lp2L * 3.8
            outR = lp2R * 3.8

        case 3:
            // Ocean waves: 6.5s swelling surf that rises into bright white foam and recedes smoothly
            wavePhase += (2 * .pi * 0.155) / sampleRate
            if wavePhase > 2 * .pi { wavePhase -= 2 * .pi }
            let rawSwell = 0.5 - 0.5 * cosf(wavePhase)
            let crest = rawSwell * rawSwell
            let bodyLevel = 0.16 + 0.84 * crest
            let foamLevel = crest * crest

            lp1L = 0.986 * lp1L + 0.04 * wL
            lp1R = 0.986 * lp1R + 0.04 * wR
            lp2L = 0.90 * lp2L + 0.10 * wL
            lp2R = 0.90 * lp2R + 0.10 * wR

            outL = lp1L * 1.45 * bodyLevel + lp2L * 0.52 * foamLevel
            outR = lp1R * 1.45 * bodyLevel + lp2R * 0.52 * foamLevel

        case 4:
            // Cafe ambience: modulated warm room chatter cadence + cozy low-chord hum + soft cup clinks
            cafePhaseA += (2 * .pi * 1.15) / sampleRate
            cafePhaseB += (2 * .pi * 2.40) / sampleRate
            chordPhase += (2 * .pi * 146.83) / sampleRate
            if cafePhaseA > 2 * .pi { cafePhaseA -= 2 * .pi }
            if cafePhaseB > 2 * .pi { cafePhaseB -= 2 * .pi }
            if chordPhase > 2 * .pi { chordPhase -= 2 * .pi }

            let murmurL = 0.65 + 0.35 * sinf(cafePhaseA) * cosf(cafePhaseB * 0.7)
            let murmurR = 0.65 + 0.35 * cosf(cafePhaseA * 0.9) * sinf(cafePhaseB)

            // Band-limited warm chatter noise
            lp1L = 0.96 * lp1L + 0.04 * wL
            lp2L = 0.992 * lp2L + 0.008 * lp1L
            let midNoiseL = (lp1L - lp2L) * 2.4

            lp1R = 0.96 * lp1R + 0.04 * wR
            lp2R = 0.992 * lp2R + 0.008 * lp1R
            let midNoiseR = (lp1R - lp2R) * 2.4

            // Subtle warm room chord resonance
            let warmHum = (sinf(chordPhase) * 0.65 + sinf(chordPhase * 1.5) * 0.35) * 0.035

            // Occasional gentle porcelain / spoon clink
            if clinkEnv < 0.004 && nextUnitRandom() < (0.42 / sampleRate) {
                clinkEnv = 0.28 + 0.18 * nextUnitRandom()
                clinkPan = 0.2 + 0.6 * nextUnitRandom()
                clinkPhaseA = 0
                clinkPhaseB = 0
            }
            clinkPhaseA += (2 * .pi * 2420.0) / sampleRate
            clinkPhaseB += (2 * .pi * 3680.0) / sampleRate
            clinkEnv *= 0.99945
            let clink = (sinf(clinkPhaseA) * 0.6 + sinf(clinkPhaseB) * 0.4) * clinkEnv * 0.28

            outL = lp2L * 0.9 + midNoiseL * murmurL + warmHum + clink * (1.0 - clinkPan)
            outR = lp2R * 0.9 + midNoiseR * murmurR + warmHum + clink * clinkPan

        default:
            outL = 0
            outR = 0
        }

        return (
            left: max(-0.85, min(0.85, outL * currentGain)),
            right: max(-0.85, min(0.85, outR * currentGain))
        )
    }
}
