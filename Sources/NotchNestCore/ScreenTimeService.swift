import AppKit
import Foundation
import Observation

public struct AppScreenTimeRow: Identifiable, Equatable, Sendable {
    public var id: String { bundleID }
    public var bundleID: String
    public var name: String
    public var category: String
    public var seconds: Int

    public var formattedDuration: String {
        let mins = seconds / 60
        let hrs = mins / 60
        let remMins = mins % 60
        if hrs > 0 { return "\(hrs)h \(remMins)m" }
        if mins > 0 { return "\(mins)m" }
        return "\(seconds)s"
    }
}

/// Tracks active frontmost macOS app time locally with category grouping and app-switch counters.
@MainActor
@Observable
public final class ScreenTimeService {
    public private(set) var stats: ScreenTimeDailyStats
    public private(set) var currentFrontmostBundleID: String?
    public private(set) var currentFrontmostAppName: String?
    public private(set) var currentFrontmostCategory: String?
    public private(set) var currentFrontmostEnteredAt: Date?

    public var onSampleRecorded: (@MainActor () -> Void)?

    private let persistence: PersistenceStore
    private var lastBundleID: String?
    private var lastSampleDate: Date?
    private var timer: Timer?
    @ObservationIgnored private nonisolated(unsafe) var activateObserver: NSObjectProtocol?

    public init(persistence: PersistenceStore) {
        self.persistence = persistence
        self.stats = persistence.loadScreenTimeStats()
    }

    deinit {
        if let activateObserver {
            NotificationCenter.default.removeObserver(activateObserver)
        }
    }

    public func startTracking() {
        recordSample(isSwitch: false)
        activateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recordSample(isSwitch: true)
            }
        }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recordSample(isSwitch: false)
            }
        }
    }

    public func stopTracking() {
        recordSample(isSwitch: false)
        timer?.invalidate()
        timer = nil
    }

    public func recordSample(isSwitch: Bool, now: Date = Date()) {
        let todayKey = DailyFocusStats.todayKey(for: now)
        if stats.dayKey != todayKey {
            stats = ScreenTimeDailyStats(dayKey: todayKey)
        }

        guard let front = NSWorkspace.shared.frontmostApplication,
              let bundleID = front.bundleIdentifier
        else {
            lastSampleDate = now
            return
        }

        let appName = front.localizedName ?? bundleID
        let category = Self.classifyCategory(bundleID: bundleID, name: appName)

        if let prevID = lastBundleID, let prevDate = lastSampleDate {
            let delta = max(0, min(60, Int(round(now.timeIntervalSince(prevDate)))))
            if delta > 0 {
                stats.secondsByBundleID[prevID, default: 0] += delta
            }
            if isSwitch && prevID != bundleID {
                stats.appSwitches += 1
            }
        }

        if lastBundleID != bundleID {
            currentFrontmostEnteredAt = now
        } else if currentFrontmostEnteredAt == nil {
            currentFrontmostEnteredAt = now
        }
        currentFrontmostBundleID = bundleID
        currentFrontmostAppName = appName
        currentFrontmostCategory = category

        stats.appNamesByBundleID[bundleID] = appName
        stats.categoriesByBundleID[bundleID] = category
        lastBundleID = bundleID
        lastSampleDate = now
        persistence.saveScreenTimeStats(stats)
        onSampleRecorded?()
    }

    public nonisolated static func shouldTriggerFocusGuard(
        bundleID: String,
        appName: String,
        category: String,
        dwellSeconds: TimeInterval,
        isFocusing: Bool,
        settings: AppSettings,
        now: Date = Date(),
        snoozedUntil: Date? = nil,
        lastNudgedAtByBundle: [String: Date] = [:],
        cooldownSeconds: TimeInterval = 180
    ) -> Bool {
        guard settings.focusGuardEnabled, isFocusing else { return false }
        if let snoozedUntil, snoozedUntil > now { return false }

        let lowerBundle = bundleID.lowercased()
        let lowerApp = appName.lowercased()
        if lowerBundle.contains("notchnest") { return false }

        // Allowlist matches app names or bundle fragments (comma-separated)
        let allowTokens = settings.focusGuardAllowlist
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        if allowTokens.contains(where: { lowerApp.contains($0) || lowerBundle.contains($0) }) {
            return false
        }

        let isDistractingCategory: Bool
        switch category {
        case "Communication", "Media & Design", "Other":
            isDistractingCategory = true
        case "Browser":
            isDistractingCategory = settings.focusGuardIncludeBrowsers
        default:
            isDistractingCategory = false
        }
        guard isDistractingCategory else { return false }

        let threshold = TimeInterval(max(10, settings.focusGuardDelaySeconds))
        guard dwellSeconds >= threshold else { return false }

        if let lastNudge = lastNudgedAtByBundle[bundleID],
           now.timeIntervalSince(lastNudge) < cooldownSeconds {
            return false
        }
        return true
    }

    public var rankedApps: [AppScreenTimeRow] {
        stats.secondsByBundleID.map { bundleID, secs in
            AppScreenTimeRow(
                bundleID: bundleID,
                name: stats.appNamesByBundleID[bundleID] ?? bundleID,
                category: stats.categoriesByBundleID[bundleID] ?? "Other",
                seconds: secs
            )
        }
        .sorted { $0.seconds > $1.seconds }
    }

    public var categoryTotals: [(category: String, seconds: Int)] {
        var map: [String: Int] = [:]
        for (bundleID, secs) in stats.secondsByBundleID {
            let cat = stats.categoriesByBundleID[bundleID] ?? "Other"
            map[cat, default: 0] += secs
        }
        return map.map { ($0.key, $0.value) }.sorted { $0.seconds > $1.seconds }
    }

    public nonisolated static func classifyCategory(bundleID: String, name: String) -> String {
        let lower = (bundleID + " " + name).lowercased()
        if lower.contains("xcode") || lower.contains("vscode") || lower.contains("cursor")
            || lower.contains("terminal") || lower.contains("iterm") || lower.contains("warp")
            || lower.contains("antigravity") || lower.contains("github") {
            return "Development"
        }
        if lower.contains("safari") || lower.contains("chrome") || lower.contains("arc")
            || lower.contains("firefox") || lower.contains("brave") || lower.contains("edge") {
            return "Browser"
        }
        if lower.contains("slack") || lower.contains("zoom") || lower.contains("teams")
            || lower.contains("messages") || lower.contains("mail") || lower.contains("discord")
            || lower.contains("facetime") {
            return "Communication"
        }
        if lower.contains("music") || lower.contains("spotify") || lower.contains("vlc")
            || lower.contains("figma") || lower.contains("photos") {
            return "Media & Design"
        }
        if lower.contains("notes") || lower.contains("notion") || lower.contains("calendar")
            || lower.contains("reminders") || lower.contains("finder") || lower.contains("notchnest") {
            return "Productivity"
        }
        return "Other"
    }
}
