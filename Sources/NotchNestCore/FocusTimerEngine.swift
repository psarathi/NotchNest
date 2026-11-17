import Foundation
import Observation

public enum TimerPhase: String, Codable, Sendable {
    case focus
    case shortBreak

    public var label: String {
        switch self {
        case .focus: return "Focus"
        case .shortBreak: return "Break"
        }
    }
}

public enum TimerRunState: String, Codable, Sendable {
    case idle
    case running
    case paused
}

@MainActor
@Observable
public final class FocusTimerEngine {
    public private(set) var phase: TimerPhase = .focus
    public private(set) var state: TimerRunState = .idle
    public private(set) var totalDuration: TimeInterval
    public private(set) var remainingSeconds: TimeInterval

    private var endDate: Date?
    private var tickTimer: Timer?
    private let now: @Sendable () -> Date
    public var onPhaseComplete: ((TimerPhase, Int) -> Void)?

    public init(
        focusMinutes: Int = 25,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        let seconds = TimeInterval(max(1, focusMinutes) * 60)
        self.totalDuration = seconds
        self.remainingSeconds = seconds
        self.now = now
    }

    public var progress: Double {
        guard totalDuration > 0 else { return 0 }
        let elapsed = totalDuration - remainingSeconds
        return min(max(elapsed / totalDuration, 0), 1)
    }

    public var formattedRemaining: String {
        let total = max(0, Int(ceil(remainingSeconds)))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    public func configure(minutes: Int, phase: TimerPhase) {
        let seconds = TimeInterval(max(1, minutes) * 60)
        configure(totalSeconds: seconds, remainingSeconds: seconds, phase: phase)
    }

    public func configure(totalSeconds: TimeInterval, remainingSeconds: TimeInterval, phase: TimerPhase) {
        stopTicking()
        self.phase = phase
        let safeTotal = max(1, totalSeconds)
        let safeRemaining = min(max(0, remainingSeconds), safeTotal)
        self.totalDuration = safeTotal
        self.remainingSeconds = safeRemaining > 0 ? safeRemaining : safeTotal
        self.endDate = nil
        self.state = (self.remainingSeconds < safeTotal - 0.5) ? .paused : .idle
    }

    public func start(minutes: Int? = nil, phase: TimerPhase? = nil) {
        if let phase {
            self.phase = phase
        }
        if let minutes {
            let seconds = TimeInterval(max(1, minutes) * 60)
            self.totalDuration = seconds
            self.remainingSeconds = seconds
        } else if state == .idle && remainingSeconds <= 0 {
            remainingSeconds = totalDuration
        }

        endDate = now().addingTimeInterval(remainingSeconds)
        state = .running
        startTicking()
    }

    public func pause() {
        guard state == .running else { return }
        syncRemaining()
        endDate = nil
        state = .paused
        stopTicking()
    }

    public func resume() {
        guard state == .paused else { return }
        endDate = now().addingTimeInterval(remainingSeconds)
        state = .running
        startTicking()
    }

    public func togglePlayPause() {
        switch state {
        case .idle:
            start()
        case .running:
            pause()
        case .paused:
            resume()
        }
    }

    public func reset(minutes: Int? = nil) {
        stopTicking()
        if let minutes {
            totalDuration = TimeInterval(max(1, minutes) * 60)
        }
        remainingSeconds = totalDuration
        endDate = nil
        state = .idle
    }

    /// Recomputes remaining time against wall clock; exposed for deterministic testing.
    public func tick() {
        guard state == .running else { return }
        syncRemaining()
        if remainingSeconds <= 0 {
            let completedPhase = phase
            let completedMinutes = max(1, Int(round(totalDuration / 60)))
            stopTicking()
            state = .idle
            endDate = nil
            remainingSeconds = 0
            onPhaseComplete?(completedPhase, completedMinutes)
        }
    }

    private func syncRemaining() {
        guard let endDate else { return }
        remainingSeconds = max(0, endDate.timeIntervalSince(now()))
    }

    private func startTicking() {
        stopTicking()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }
}
