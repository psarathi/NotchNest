import Foundation
import Observation

public enum BreathingPhase: String, Sendable {
    case inhale = "Inhale"
    case hold = "Hold"
    case exhale = "Exhale"
    case rest = "Hold Empty"

    public var durationSeconds: Int { 4 }

    public var next: BreathingPhase {
        switch self {
        case .inhale: return .hold
        case .hold: return .exhale
        case .exhale: return .rest
        case .rest: return .inhale
        }
    }

    public var targetScale: Double {
        switch self {
        case .inhale, .hold: return 1.0
        case .exhale, .rest: return 0.56
        }
    }
}

public struct DeskStretchPrompt: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let durationSeconds: Int
    public let instruction: String

    public static let library: [DeskStretchPrompt] = [
        DeskStretchPrompt(
            id: "neck-release",
            title: "Cervical Neck Release",
            durationSeconds: 30,
            instruction: "Drop your shoulders away from your ears and gently tilt each ear toward your shoulder for 15s."
        ),
        DeskStretchPrompt(
            id: "chest-opener",
            title: "Open-Chest Reach",
            durationSeconds: 30,
            instruction: "Clasp hands behind your lower back, roll shoulders down, and lift your sternum cleanly."
        ),
        DeskStretchPrompt(
            id: "wrist-flex",
            title: "Typing Wrist Reset",
            durationSeconds: 25,
            instruction: "Extend one arm palm-forward and gently draw fingertips back for 12s per hand."
        ),
        DeskStretchPrompt(
            id: "spinal-twist",
            title: "Seated Spinal Twist",
            durationSeconds: 30,
            instruction: "Sit tall, inhale to lengthen your spine, and rotate gently toward each backrest side."
        ),
        DeskStretchPrompt(
            id: "eye-palming",
            title: "20-20-20 Horizon Gaze",
            durationSeconds: 20,
            instruction: "Look at an object at least 20 feet away for 20 seconds and blink slowly 5 times."
        )
    ]
}

@MainActor
@Observable
public final class HealthWellbeingService {
    public private(set) var stats: DailyHealthStats
    public private(set) var isEyeBreakReminderEnabled: Bool = false
    public private(set) var eyeBreakSecondsRemaining: Int = 20 * 60
    public private(set) var isEyeBreakDue: Bool = false
    public private(set) var eyeRestSecondsRemaining: Int = 20

    public private(set) var isBreathingActive: Bool = false
    public private(set) var breathingPhase: BreathingPhase = .inhale
    public private(set) var breathingPhaseSecondsRemaining: Int = 4
    public private(set) var breathingCyclesCompleted: Int = 0

    public var currentStretchIndex: Int = 0
    private var breathingElapsedSeconds: Int = 0
    private let persistence: PersistenceStore
    private var tickTimer: Timer?
    public var onEyeBreakDue: (@MainActor () -> Void)?

    public static let eyeWorkIntervalSeconds = 20 * 60
    public static let eyeRestDurationSeconds = 20

    public static let quotes: [String] = [
        "Calm focus beats frantic multitasking.",
        "Small deliberate breaks keep sharp decisions steady.",
        "Unclench your jaw, drop your shoulders, breathe slow.",
        "Progress compounds in quiet, uninterrupted blocks.",
        "Protect deep work first; answer pings second."
    ]

    public init(
        persistence: PersistenceStore,
        onEyeBreakDue: (@MainActor () -> Void)? = nil
    ) {
        self.persistence = persistence
        self.onEyeBreakDue = onEyeBreakDue
        self.stats = persistence.loadHealthStats()
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        self.currentStretchIndex = dayOfYear % DeskStretchPrompt.library.count
    }

    public func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    public var currentStretch: DeskStretchPrompt {
        let items = DeskStretchPrompt.library
        return items[abs(currentStretchIndex) % items.count]
    }

    public var dailyQuote: String {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return Self.quotes[dayOfYear % Self.quotes.count]
    }

    public var waterProgress: Double {
        min(1.0, Double(stats.waterGlasses) / Double(max(1, stats.waterGoal)))
    }

    public var breaksProgress: Double {
        min(1.0, Double(stats.breaksTaken) / Double(max(1, stats.breaksGoal)))
    }

    public var mindfulProgress: Double {
        min(1.0, Double(stats.mindfulMinutes) / Double(max(1, stats.mindfulGoal)))
    }

    public func lastBreakSummary(now: Date = Date()) -> String {
        guard let last = stats.lastBreakAt else { return "No breaks yet" }
        let minutes = max(0, Int(now.timeIntervalSince(last) / 60))
        if minutes < 1 { return "Just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        let rem = minutes % 60
        return rem == 0 ? "\(hours)h ago" : "\(hours)h \(rem)m ago"
    }

    public var eyeBreakCountdownText: String {
        let secs = isEyeBreakDue ? eyeRestSecondsRemaining : eyeBreakSecondsRemaining
        let m = secs / 60
        let s = secs % 60
        return String(format: "%02d:%02d", m, s)
    }

    public func adjustWater(_ delta: Int, now: Date = Date()) {
        rollOverIfNeeded(now: now)
        stats.waterGlasses = max(0, min(24, stats.waterGlasses + delta))
        persistence.saveHealthStats(stats)
    }

    public func recordBreak(mindfulMinutes: Int = 0, now: Date = Date()) {
        rollOverIfNeeded(now: now)
        stats.breaksTaken += 1
        stats.lastBreakAt = now
        if stats.streakDays == 0 {
            stats.streakDays = 1
        }
        if mindfulMinutes > 0 {
            stats.mindfulMinutes += mindfulMinutes
        }
        persistence.saveHealthStats(stats)
    }

    public func addMindfulMinutes(_ minutes: Int, now: Date = Date()) {
        guard minutes > 0 else { return }
        rollOverIfNeeded(now: now)
        stats.mindfulMinutes += minutes
        persistence.saveHealthStats(stats)
    }

    public func nextStretch() {
        currentStretchIndex = (currentStretchIndex + 1) % DeskStretchPrompt.library.count
    }

    public func setEyeBreakReminder(enabled: Bool) {
        isEyeBreakReminderEnabled = enabled
        if !enabled {
            isEyeBreakDue = false
            eyeBreakSecondsRemaining = Self.eyeWorkIntervalSeconds
            eyeRestSecondsRemaining = Self.eyeRestDurationSeconds
        }
        ensureTimerState()
    }

    public func completeEyeBreak(now: Date = Date()) {
        isEyeBreakDue = false
        eyeBreakSecondsRemaining = Self.eyeWorkIntervalSeconds
        eyeRestSecondsRemaining = Self.eyeRestDurationSeconds
        recordBreak(now: now)
        ensureTimerState()
    }

    public func snoozeEyeBreak(minutes: Int = 5) {
        isEyeBreakDue = false
        eyeBreakSecondsRemaining = max(60, minutes * 60)
        eyeRestSecondsRemaining = Self.eyeRestDurationSeconds
        ensureTimerState()
    }

    public func triggerEyeBreakNow() {
        isEyeBreakDue = true
        eyeRestSecondsRemaining = Self.eyeRestDurationSeconds
        onEyeBreakDue?()
        ensureTimerState()
    }

    public func toggleBreathing() {
        if isBreathingActive {
            stopBreathing()
        } else {
            startBreathing()
        }
    }

    public func startBreathing() {
        isBreathingActive = true
        breathingPhase = .inhale
        breathingPhaseSecondsRemaining = breathingPhase.durationSeconds
        breathingElapsedSeconds = 0
        ensureTimerState()
    }

    public func stopBreathing() {
        if isBreathingActive, breathingElapsedSeconds >= 30 {
            let earnedMinutes = max(1, breathingElapsedSeconds / 60)
            addMindfulMinutes(earnedMinutes)
        }
        isBreathingActive = false
        breathingElapsedSeconds = 0
        breathingPhase = .inhale
        breathingPhaseSecondsRemaining = breathingPhase.durationSeconds
        ensureTimerState()
    }

    private func rollOverIfNeeded(now: Date) {
        let today = DailyFocusStats.todayKey(for: now)
        if stats.dayKey != today {
            let continuedStreak = stats.breaksTaken > 0 ? stats.streakDays + 1 : 0
            stats = DailyHealthStats(dayKey: today, streakDays: continuedStreak)
            persistence.saveHealthStats(stats)
        }
    }

    private func ensureTimerState() {
        let needsTimer = isEyeBreakReminderEnabled || isEyeBreakDue || isBreathingActive
        if needsTimer, tickTimer == nil {
            let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.tick()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            tickTimer = timer
        } else if !needsTimer {
            tickTimer?.invalidate()
            tickTimer = nil
        }
    }

    private func tick() {
        rollOverIfNeeded(now: Date())

        if isBreathingActive {
            breathingElapsedSeconds += 1
            if breathingPhaseSecondsRemaining > 1 {
                breathingPhaseSecondsRemaining -= 1
            } else {
                let nextPhase = breathingPhase.next
                if nextPhase == .inhale {
                    breathingCyclesCompleted += 1
                }
                breathingPhase = nextPhase
                breathingPhaseSecondsRemaining = nextPhase.durationSeconds
                if breathingElapsedSeconds % 60 == 0 {
                    addMindfulMinutes(1)
                }
            }
        }

        if isEyeBreakDue {
            if eyeRestSecondsRemaining > 1 {
                eyeRestSecondsRemaining -= 1
            } else {
                completeEyeBreak()
            }
        } else if isEyeBreakReminderEnabled {
            if eyeBreakSecondsRemaining > 1 {
                eyeBreakSecondsRemaining -= 1
            } else {
                triggerEyeBreakNow()
            }
        }
    }
}
