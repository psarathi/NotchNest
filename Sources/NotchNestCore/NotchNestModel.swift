import AppKit
import Foundation
import Observation
import ServiceManagement
@preconcurrency import UserNotifications

public enum UtilityOverlay: String, Sendable, Equatable {
    case wrapUp
    case diagnostics
}

@MainActor
@Observable
public final class NotchNestModel {
    public var isExpanded = false
    public var isPinned = false
    public var activeTab: NotchTab = .today
    public var isHoveringNotch = false
    public var lastTaskCompletedPulse = false

    public var tasks: [TaskItem]
    public var notes: [NoteEntry]
    public var selectedNoteID: UUID
    public var clips: [ClipItem] = []
    public var settings: AppSettings {
        didSet {
            persistence.saveSettings(settings)
            applySettingsSideEffects(from: oldValue)
        }
    }
    public var focusStats: DailyFocusStats
    public var activityHistory: [DailyActivityRecord]

    /// Task currently linked to a Focus session or pinned as a Live Activity nudge.
    public var activeFocusTaskID: UUID?
    public var taskRemainingSeconds: [UUID: TimeInterval] = [:]
    public var microTimers: [MicroTimerItem] = []
    public var focusGuardSnoozedUntil: Date?
    public var nudgeClockRevision: Int = 0
    public var autoTriggeredReminderTaskIDs: Set<UUID> = []
    public var activeCountdownSourceIsReminder = false
    public var pinnedLiveActivityTaskID: UUID?
    public var dismissedEventIDs: Set<String> = []
    public var isAmbientPreviewActive = false
    public var activeUtilityOverlay: UtilityOverlay?
    public var selectedHubSection: HubSection = .overview
    public var isDraggingFileOverNotch = false
    public var pendingActionURLs: [URL] = []
    public var dropActionFeedback: String?
    public var autoConvertedNoteBanner: String?
    public var transientLiveActivity: TransientLiveActivity?
    public var workspaceFocusRequestNonce: Int = 0
    public var pendingWorkspaceTypedSeed: String = ""

    public let persistence: PersistenceStore
    public let timer: FocusTimerEngine
    public let eventKit: EventKitService
    public let cameraMirror: CameraMirrorController
    public let audioEngine: FocusAudioEngine
    public let voiceCapture: VoiceCaptureController
    public let travelTimeService: TravelTimeService
    public let systemService: SystemAndPowerService
    public let clipboardService: ClipboardHistoryService
    public let mediaService: MediaPlaybackService
    public let weatherService: WeatherService
    public let screenTimeService: ScreenTimeService
    public let healthService: HealthWellbeingService
    public let snapService: WindowSnapService
    public let devHubService: DeveloperHubService

    private var clipsWatcher: ClipsWatcher?
    private var hotKeyManager: GlobalHotKeyManager?
    private var watchedScreenshots: [ClipItem] = []
    private var pinnedOrDroppedClips: [ClipItem]
    private var lastObservedTimerState: TimerRunState = .idle
    private var lastEnsuredDailyNoteKey: String = ""
    private var nudgeRefreshTimer: Timer?
    private var nudgeWakeTimer: Timer?
    private var microTimerTickTimer: Timer?
    private let enableSystemIntegrationsFlag: Bool
    private var focusGuardLastNudgeByBundle: [String: Date] = [:]
    private var scrollGestureRecognizer = NotchScrollGestureRecognizer()
    private var lastWeatherRefreshAt: Date?
    private var transientDismissTask: Task<Void, Never>?
    private var autoConvertedBannerTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var screenUnlockObserver: NSObjectProtocol?

    public var onRequestPanelToggle: (() -> Void)?
    public var onRequestPanelExpand: ((NotchTab?) -> Void)?
    public var onLayoutSettingsChanged: (() -> Void)?
    public var onHitRectNeedsUpdate: (() -> Void)?
    public var onPrivacyModeChanged: ((Bool) -> Void)?

    public init(persistence: PersistenceStore = PersistenceStore(), enableSystemIntegrations: Bool = true) {
        self.persistence = persistence
        self.enableSystemIntegrationsFlag = enableSystemIntegrations
        let loadedSettings = persistence.loadSettings()
        self.settings = loadedSettings
        self.tasks = persistence.loadTasks()
        let loadedNotes = persistence.loadNotes()
        self.notes = loadedNotes
        self.selectedNoteID = loadedNotes.first?.id ?? UUID()
        self.pinnedOrDroppedClips = persistence.loadPinnedClips()
        self.focusStats = persistence.loadStats()
        self.activityHistory = persistence.loadActivityHistory()
        self.timer = FocusTimerEngine(focusMinutes: loadedSettings.focusMinutes)
        self.eventKit = EventKitService()
        self.cameraMirror = CameraMirrorController()
        self.audioEngine = FocusAudioEngine()
        self.voiceCapture = VoiceCaptureController()
        self.travelTimeService = TravelTimeService()
        self.systemService = SystemAndPowerService()
        self.clipboardService = ClipboardHistoryService(persistence: persistence)
        self.mediaService = MediaPlaybackService()
        self.weatherService = WeatherService()
        self.screenTimeService = ScreenTimeService(persistence: persistence)
        self.healthService = HealthWellbeingService(persistence: persistence)
        self.snapService = WindowSnapService()
        self.devHubService = DeveloperHubService()

        self.ensureTodayDailyNote()
        self.loadPersistedMicroTimers()
        self.clips = mergeClips()

        self.timer.onPhaseComplete = { [weak self] phase, minutes in
            self?.handleTimerCompleted(phase: phase, minutes: minutes)
        }

        if enableSystemIntegrations {
            Task { @MainActor [weak self] in
                self?.setupIntegrations()
            }
        }
    }

    // MARK: - Task Computed Views

    public var openTaskCount: Int {
        tasks.filter { !$0.isCompleted }.count
    }

    public var todayTasks: [TaskItem] {
        tasks(forDayOffset: 0)
    }

    public var todayOpenCount: Int {
        todayTasks.filter { !$0.isCompleted }.count
    }

    public var todayCompletedCount: Int {
        todayTasks.filter { $0.isCompleted }.count
    }

    public func tasks(in bucket: TaskBucket) -> [TaskItem] {
        tasks.filter { $0.scheduledBucket == bucket }
    }

    public func bucket(forDayOffset offset: Int) -> TaskBucket {
        switch offset {
        case ..<0: return .inbox
        case 0: return .today
        case 1: return .tomorrow
        default: return .upcoming
        }
    }

    public func dayKey(forDayOffset offset: Int, calendar: Calendar = .current) -> String? {
        guard offset >= 0,
              let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date()))
        else {
            return nil
        }
        return DailyFocusStats.todayKey(for: date)
    }

    public func weekPlanColumns(days: Int = 7, referenceDate: Date = Date(), calendar: Calendar = .current) -> [WeekPlanColumn] {
        var cols: [WeekPlanColumn] = [.inbox]
        let startToday = calendar.startOfDay(for: referenceDate)
        for offset in 0..<days {
            if let date = calendar.date(byAdding: .day, value: offset, to: startToday) {
                cols.append(.day(dayKey: DailyFocusStats.todayKey(for: date), date: date, offset: offset))
            }
        }
        cols.append(.later)
        return cols
    }

    public func tasks(
        forColumn column: WeekPlanColumn,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [TaskItem] {
        let startToday = calendar.startOfDay(for: referenceDate)
        let sevenDayKeys: Set<String> = Set((0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: startToday).map { DailyFocusStats.todayKey(for: $0) }
        })

        switch column {
        case .inbox:
            return tasks.filter { $0.scheduledBucket == .inbox && $0.scheduledDayKey == nil && $0.dueDate == nil }

        case .day(let targetKey, let targetDate, let offset):
            return tasks.filter { item in
                if let explicitKey = item.scheduledDayKey {
                    return explicitKey == targetKey
                }
                if let due = item.dueDate {
                    return calendar.isDate(due, inSameDayAs: targetDate)
                }
                if offset == 0 && item.scheduledBucket == .today {
                    return true
                }
                if offset == 1 && item.scheduledBucket == .tomorrow {
                    return true
                }
                return false
            }

        case .later:
            return tasks.filter { item in
                if item.scheduledBucket == .inbox && item.scheduledDayKey == nil && item.dueDate == nil {
                    return false
                }
                if let key = item.scheduledDayKey ?? item.dueDate.map({ DailyFocusStats.todayKey(for: $0) }) {
                    if sevenDayKeys.contains(key) {
                        return false
                    }
                    if let d = DailyFocusStats.date(fromDayKey: key), d < startToday {
                        // Past tasks without completion fall under Today/backlog or Inbox rather than future Later unless upcoming
                        return item.scheduledBucket == .upcoming
                    }
                    return true
                }
                return item.scheduledBucket == .upcoming
            }
        }
    }

    public func tasks(forDayOffset offset: Int, calendar: Calendar = .current) -> [TaskItem] {
        if offset < 0 {
            return tasks(forColumn: .inbox, calendar: calendar)
        }
        guard let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date())) else {
            return tasks(forColumn: .later, calendar: calendar)
        }
        let key = DailyFocusStats.todayKey(for: date)
        if offset < 7 {
            return tasks(forColumn: .day(dayKey: key, date: date, offset: offset), calendar: calendar)
        }
        return tasks.filter { item in
            if let explicitKey = item.scheduledDayKey {
                return explicitKey == key
            }
            if let due = item.dueDate {
                return calendar.isDate(due, inSameDayAs: date)
            }
            return false
        }
    }

    public func events(on day: Date, calendar: Calendar = .current) -> [CalendarEventItem] {
        let startDay = calendar.startOfDay(for: day)
        guard let endDay = calendar.date(byAdding: .day, value: 1, to: startDay) else { return [] }
        return eventKit.upcomingEvents.filter { event in
            event.endDate > startDay && event.startDate < endDay
        }
    }

    public func timedTasks(on day: Date, calendar: Calendar = .current) -> [TaskItem] {
        let targetKey = DailyFocusStats.todayKey(for: day)
        return tasks.filter { item in
            guard let due = item.dueDate else { return false }
            if let key = item.scheduledDayKey {
                return key == targetKey
            }
            return calendar.isDate(due, inSameDayAs: day)
        }
        .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    public func dayHasActivity(_ day: Date, calendar: Calendar = .current) -> Bool {
        if !events(on: day, calendar: calendar).isEmpty {
            return true
        }
        return !timedTasks(on: day, calendar: calendar).isEmpty
    }

    @discardableResult
    public func moveIncompleteTodayToTomorrow() -> Int {
        var moved = 0
        let tmrKey = dayKey(forDayOffset: 1)
        for idx in tasks.indices where !tasks[idx].isCompleted && isTaskInToday(tasks[idx]) {
            tasks[idx].scheduledBucket = .tomorrow
            tasks[idx].scheduledDayKey = tmrKey
            moved += 1
        }
        if moved > 0 {
            sortAndSaveTasks()
            onHitRectNeedsUpdate?()
        }
        return moved
    }

    private func isTaskInToday(_ item: TaskItem, calendar: Calendar = .current) -> Bool {
        let todayKey = DailyFocusStats.todayKey()
        if let key = item.scheduledDayKey {
            return key == todayKey
        }
        if let due = item.dueDate {
            return calendar.isDateInToday(due)
        }
        return item.scheduledBucket == .today
    }

    public var activeFocusTask: TaskItem? {
        guard let activeFocusTaskID else { return nil }
        return tasks.first(where: { $0.id == activeFocusTaskID })
    }

    public var selectedNoteIndex: Int? {
        notes.firstIndex(where: { $0.id == selectedNoteID })
    }

    public var launchAtLoginEnabled: Bool {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    // MARK: - Live Activity Nudge State

    public var activeLiveNudgeTask: TaskItem? {
        _ = nudgeClockRevision
        return activeLiveNudgeTask(at: Date())
    }

    public func activeLiveNudgeTask(at now: Date) -> TaskItem? {
        if let pinnedID = pinnedLiveActivityTaskID,
           let pinned = tasks.first(where: { $0.id == pinnedID && !$0.isCompleted }) {
            if let snoozed = pinned.snoozedUntil, snoozed > now {
                return nil
            }
            return pinned
        }

        return tasks.first { task in
            guard !task.isCompleted, let due = task.dueDate else { return false }
            if let snoozed = task.snoozedUntil, snoozed > now {
                return false
            }
            // Surface tasks due within the next 15 minutes or overdue by up to 4 hours today
            let delta = due.timeIntervalSince(now)
            return delta <= 15 * 60 && delta >= -4 * 3600
        }
    }

    public var activeLiveNudgeEvent: CalendarEventItem? {
        _ = nudgeClockRevision
        return activeLiveNudgeEvent(at: Date())
    }

    public func activeLiveNudgeEvent(at now: Date) -> CalendarEventItem? {
        eventKit.upcomingEvents.first { event in
            guard !event.isAllDay, !dismissedEventIDs.contains(event.id) else { return false }
            let leadMinutes = Double(max(10, (event.travelTimeMinutes ?? 0) + 10)) * 60
            let delta = event.startDate.timeIntervalSince(now)
            return delta <= leadMinutes && event.endDate > now
        }
    }

    public var showsLiveActivityPill: Bool {
        _ = nudgeClockRevision
        return showsLiveActivityPill(at: Date())
    }

    public func showsLiveActivityPill(at now: Date) -> Bool {
        healthService.isEyeBreakDue
            || transientLiveActivity != nil
            || (settings.showLiveActivityNudge && (activeLiveNudgeTask(at: now) != nil || activeLiveNudgeEvent(at: now) != nil))
    }

    // MARK: - Insights Computed Metrics

    public var recent7DayRecords: [DailyActivityRecord] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lookup = Dictionary(uniqueKeysWithValues: activityHistory.map { ($0.dayKey, $0) })
        return (0..<7).reversed().compactMap { offset -> DailyActivityRecord? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = DailyFocusStats.todayKey(for: day)
            return lookup[key] ?? DailyActivityRecord(dayKey: key)
        }
    }

    public var totalCompletedTasksMetric: Int {
        let historySum = activityHistory.reduce(0) { $0 + $1.completedTasks }
        let currentCompleted = tasks.filter { $0.isCompleted }.count
        return max(historySum, currentCompleted)
    }

    public var totalFocusedMinutesMetric: Int {
        max(focusStats.focusedMinutes, activityHistory.reduce(0) { $0 + $1.focusedMinutes })
    }

    public var currentStreakDays: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lookup = Dictionary(uniqueKeysWithValues: activityHistory.map { ($0.dayKey, $0) })

        var streak = 0
        for offset in 0..<30 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { break }
            let key = DailyFocusStats.todayKey(for: day)
            let record = lookup[key]
            let active = (record?.completedTasks ?? 0) > 0 || (record?.focusedMinutes ?? 0) > 0
            if active {
                streak += 1
            } else if offset > 0 {
                break
            }
        }
        return streak
    }

    public var bestFocusHourRangeLabel: String {
        var hourlyTotals: [Int: Int] = [:]
        for record in activityHistory {
            for (hour, mins) in record.hourlyFocusMinutes {
                hourlyTotals[hour, default: 0] += mins
            }
        }
        guard let best = hourlyTotals.max(by: { $0.value < $1.value }), best.value > 0 else {
            return "—"
        }
        return "\(formatHour(best.key)) – \(formatHour((best.key + 1) % 24))"
    }

    private func formatHour(_ hour: Int) -> String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        let period = hour < 12 ? "AM" : "PM"
        return "\(h12) \(period)"
    }

    // MARK: - Login Item

    public func setLaunchAtLogin(_ enabled: Bool) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Ignored when unbundled
        }
    }

    // MARK: - Tasks

    public func addTask(
        title: String,
        priority: TaskPriority = .normal,
        bucket: TaskBucket = .today,
        scheduledDayKey: String? = nil,
        dueDate: Date? = nil,
        projectTag: String? = nil,
        recurrence: TaskRecurrence = .none,
        targetMinutes: Int? = nil,
        reminderLeadMinutes: Int? = nil
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let resolvedDayKey: String?
        if let scheduledDayKey {
            resolvedDayKey = scheduledDayKey
        } else if let dueDate {
            resolvedDayKey = DailyFocusStats.todayKey(for: dueDate)
        } else if bucket == .today {
            resolvedDayKey = dayKey(forDayOffset: 0)
        } else if bucket == .tomorrow {
            resolvedDayKey = dayKey(forDayOffset: 1)
        } else {
            resolvedDayKey = nil
        }

        var item = TaskItem(
            title: trimmed,
            priority: priority,
            scheduledBucket: bucket,
            scheduledDayKey: resolvedDayKey,
            dueDate: dueDate,
            projectTag: projectTag,
            recurrence: recurrence,
            targetMinutes: targetMinutes,
            reminderLeadMinutes: reminderLeadMinutes
        )
        if settings.syncReminders && eventKit.reminderAuth == .authorized {
            item.reminderIdentifier = eventKit.upsertReminder(for: item)
        }
        tasks.insert(item, at: 0)
        sortAndSaveTasks()
        evaluatePreDueReminders()
        nudgeClockRevision &+= 1
        onHitRectNeedsUpdate?()
        scheduleNextNudgeWakeup()
    }

    public func addParsedTask(
        _ rawInput: String,
        defaultBucket: TaskBucket = .today,
        defaultDayKey: String? = nil,
        priorityOverride: TaskPriority = .normal
    ) {
        let fallbackKey = defaultDayKey ?? (defaultBucket == .today ? dayKey(forDayOffset: 0) : (defaultBucket == .tomorrow ? dayKey(forDayOffset: 1) : nil))
        let parsed = NaturalLanguageTaskParser.parse(
            rawInput,
            defaultBucket: defaultBucket,
            defaultDayKey: fallbackKey
        )
        guard !parsed.title.isEmpty else { return }
        let finalPriority: TaskPriority = (priorityOverride == .high || parsed.priority == .high) ? .high : .normal
        addTask(
            title: parsed.title,
            priority: finalPriority,
            bucket: parsed.scheduledBucket,
            scheduledDayKey: parsed.scheduledDayKey,
            dueDate: parsed.dueDate,
            projectTag: parsed.projectTag,
            recurrence: parsed.recurrence,
            targetMinutes: parsed.targetMinutes,
            reminderLeadMinutes: parsed.reminderLeadMinutes
        )
    }

    public func toggleTask(_ id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].isCompleted.toggle()
        tasks[idx].completedAt = tasks[idx].isCompleted ? Date() : nil

        if tasks[idx].isCompleted {
            triggerMascotPulse()
            recordTaskCompletion(delta: 1)
            taskRemainingSeconds.removeValue(forKey: id)
            autoTriggeredReminderTaskIDs.remove(id)
            if pinnedLiveActivityTaskID == id {
                pinnedLiveActivityTaskID = nil
            }
            if activeFocusTaskID == id {
                activeFocusTaskID = nil
                activeCountdownSourceIsReminder = false
            }
        } else {
            recordTaskCompletion(delta: -1)
        }

        if settings.syncReminders && eventKit.reminderAuth == .authorized {
            tasks[idx].reminderIdentifier = eventKit.upsertReminder(for: tasks[idx])
        }
        sortAndSaveTasks()
        nudgeClockRevision &+= 1
        onHitRectNeedsUpdate?()
        scheduleNextNudgeWakeup()
    }

    public func toggleTaskPriority(_ id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].priority = tasks[idx].priority == .high ? .normal : .high
        sortAndSaveTasks()
    }

    public func updateTask(
        _ id: UUID,
        title: String,
        priority: TaskPriority? = nil,
        bucket: TaskBucket? = nil,
        dayKey: String? = nil,
        updateTargetMinutes: Bool = false,
        targetMinutes: Int? = nil,
        updateDueDate: Bool = false,
        dueDate: Date? = nil,
        updateReminderLeadMinutes: Bool = false,
        reminderLeadMinutes: Int? = nil
    ) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        tasks[idx].title = trimmed
        if let priority {
            tasks[idx].priority = priority
        }
        if updateTargetMinutes {
            tasks[idx].targetMinutes = targetMinutes.map { min(max(1, $0), 240) }
            taskRemainingSeconds.removeValue(forKey: id)
            if activeFocusTaskID == id && timer.state == .idle {
                timer.configure(minutes: effectiveFocusMinutes(for: tasks[idx]), phase: .focus)
            }
        }
        if updateDueDate {
            tasks[idx].dueDate = dueDate
            autoTriggeredReminderTaskIDs.remove(id)
            if let dueDate {
                let key = DailyFocusStats.todayKey(for: dueDate)
                tasks[idx].scheduledDayKey = key
                if Calendar.current.isDateInToday(dueDate) {
                    tasks[idx].scheduledBucket = .today
                } else if Calendar.current.isDateInTomorrow(dueDate) {
                    tasks[idx].scheduledBucket = .tomorrow
                } else {
                    tasks[idx].scheduledBucket = .upcoming
                }
            }
        }
        if updateReminderLeadMinutes {
            tasks[idx].reminderLeadMinutes = reminderLeadMinutes.map { min(max(0, $0), 180) }
            autoTriggeredReminderTaskIDs.remove(id)
        }
        if !updateDueDate, let dayKey {
            tasks[idx].scheduledDayKey = dayKey
            if let bucket {
                tasks[idx].scheduledBucket = bucket
            } else if let targetDate = DailyFocusStats.date(fromDayKey: dayKey) {
                if Calendar.current.isDateInToday(targetDate) {
                    tasks[idx].scheduledBucket = .today
                } else if Calendar.current.isDateInTomorrow(targetDate) {
                    tasks[idx].scheduledBucket = .tomorrow
                } else {
                    tasks[idx].scheduledBucket = .upcoming
                }
            }
            if let existingDue = tasks[idx].dueDate,
               let targetDate = DailyFocusStats.date(fromDayKey: dayKey) {
                tasks[idx].dueDate = Self.combining(day: targetDate, timeFrom: existingDue)
            }
        } else if !updateDueDate, let bucket {
            applyBucketTransition(at: idx, to: bucket)
        }
        if settings.syncReminders && eventKit.reminderAuth == .authorized {
            tasks[idx].reminderIdentifier = eventKit.upsertReminder(for: tasks[idx])
        }
        sortAndSaveTasks()
        evaluatePreDueReminders()
        nudgeClockRevision &+= 1
        onHitRectNeedsUpdate?()
        scheduleNextNudgeWakeup()
    }

    public func moveTask(_ id: UUID, to bucket: TaskBucket) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        applyBucketTransition(at: idx, to: bucket)
        sortAndSaveTasks()
        nudgeClockRevision &+= 1
        onHitRectNeedsUpdate?()
        scheduleNextNudgeWakeup()
    }

    public func moveTask(_ id: UUID, toColumn column: WeekPlanColumn, calendar: Calendar = .current) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        switch column {
        case .inbox:
            tasks[idx].scheduledBucket = .inbox
            tasks[idx].scheduledDayKey = nil
            tasks[idx].dueDate = nil
        case .day(let key, let date, _):
            tasks[idx].scheduledBucket = column.bucket
            tasks[idx].scheduledDayKey = key
            if let existingDue = tasks[idx].dueDate {
                tasks[idx].dueDate = Self.combining(day: date, timeFrom: existingDue, calendar: calendar)
            }
        case .later:
            tasks[idx].scheduledBucket = .upcoming
            tasks[idx].scheduledDayKey = nil
            tasks[idx].dueDate = nil
        }
        sortAndSaveTasks()
        nudgeClockRevision &+= 1
        onHitRectNeedsUpdate?()
        scheduleNextNudgeWakeup()
    }

    private func applyBucketTransition(at idx: Int, to bucket: TaskBucket) {
        tasks[idx].scheduledBucket = bucket
        switch bucket {
        case .inbox:
            tasks[idx].scheduledDayKey = nil
            tasks[idx].dueDate = nil
        case .today:
            let key = dayKey(forDayOffset: 0)
            tasks[idx].scheduledDayKey = key
            if let existingDue = tasks[idx].dueDate {
                tasks[idx].dueDate = Self.combining(day: Date(), timeFrom: existingDue)
            }
        case .tomorrow:
            let key = dayKey(forDayOffset: 1)
            tasks[idx].scheduledDayKey = key
            if let existingDue = tasks[idx].dueDate,
               let tmr = Calendar.current.date(byAdding: .day, value: 1, to: Date()) {
                tasks[idx].dueDate = Self.combining(day: tmr, timeFrom: existingDue)
            }
        case .upcoming:
            tasks[idx].scheduledDayKey = nil
        }
    }

    private static func combining(day: Date, timeFrom timeDate: Date, calendar: Calendar = .current) -> Date? {
        var comps = calendar.dateComponents([.year, .month, .day], from: day)
        let timeComps = calendar.dateComponents([.hour, .minute, .second], from: timeDate)
        comps.hour = timeComps.hour
        comps.minute = timeComps.minute
        comps.second = timeComps.second
        return calendar.date(from: comps)
    }

    public func pinTaskAsLiveNudge(_ id: UUID) {
        guard tasks.contains(where: { $0.id == id && !$0.isCompleted }) else { return }
        if let idx = tasks.firstIndex(where: { $0.id == id }) {
            tasks[idx].snoozedUntil = nil
        }
        pinnedLiveActivityTaskID = (pinnedLiveActivityTaskID == id) ? nil : id
        persistence.saveTasks(tasks)
        nudgeClockRevision &+= 1
        onHitRectNeedsUpdate?()
        scheduleNextNudgeWakeup()
    }

    public func snoozeActiveNudge(minutes: Int = 5, now: Date = Date()) {
        if healthService.isEyeBreakDue {
            healthService.snoozeEyeBreak(minutes: minutes)
            nudgeClockRevision &+= 1
            onHitRectNeedsUpdate?()
            return
        }
        let snoozeDate = now.addingTimeInterval(TimeInterval(minutes * 60))
        if let task = activeLiveNudgeTask(at: now),
           let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx].snoozedUntil = snoozeDate
            persistence.saveTasks(tasks)
        } else if let event = activeLiveNudgeEvent(at: now) {
            dismissedEventIDs.insert(event.id)
        }
        nudgeClockRevision &+= 1
        onHitRectNeedsUpdate?()
        scheduleNextNudgeWakeup(now: now)
    }

    /// Computes the earliest upcoming timestamp when a snoozed task, scheduled nudge/reminder window,
    /// calendar event lead window, or Focus Guard snooze should wake up automatically.
    public func nextScheduledNudgeWakeDate(now: Date = Date()) -> Date? {
        var candidates: [Date] = []

        for task in tasks where !task.isCompleted {
            if let snoozed = task.snoozedUntil, snoozed > now {
                candidates.append(snoozed)
            }
            if let due = task.dueDate {
                let isSnoozed = task.snoozedUntil.map { $0 > now } ?? false
                if !isSnoozed {
                    let nudgeStart = due.addingTimeInterval(-15 * 60)
                    if nudgeStart > now {
                        candidates.append(nudgeStart)
                    }
                }
                if !autoTriggeredReminderTaskIDs.contains(task.id),
                   let windowStart = task.reminderWindowStartDate(),
                   windowStart > now {
                    candidates.append(windowStart)
                }
            }
        }

        for event in eventKit.upcomingEvents where !event.isAllDay && !dismissedEventIDs.contains(event.id) {
            let leadMinutes = Double(max(10, (event.travelTimeMinutes ?? 0) + 10)) * 60
            let triggerAt = event.startDate.addingTimeInterval(-leadMinutes)
            if triggerAt > now {
                candidates.append(triggerAt)
            }
        }

        if let guardSnooze = focusGuardSnoozedUntil, guardSnooze > now {
            candidates.append(guardSnooze)
        }

        return candidates.min()
    }

    /// Refreshes snooze expiry, pre-due reminders, Focus Guard, and SwiftUI live-activity invalidation.
    @discardableResult
    public func refreshLiveActivityState(now: Date = Date()) -> Bool {
        var wokeTasks: [TaskItem] = []
        var didMutateTasks = false
        for idx in tasks.indices where !tasks[idx].isCompleted {
            if let snoozed = tasks[idx].snoozedUntil, snoozed <= now {
                tasks[idx].snoozedUntil = nil
                didMutateTasks = true
                let withinDueWindow = tasks[idx].dueDate.map { due in
                    let delta = due.timeIntervalSince(now)
                    return delta <= 15 * 60 && delta >= -4 * 3600
                } ?? false
                if pinnedLiveActivityTaskID == tasks[idx].id || withinDueWindow {
                    wokeTasks.append(tasks[idx])
                }
            }
        }
        if didMutateTasks {
            persistence.saveTasks(tasks)
        }

        if let guardSnooze = focusGuardSnoozedUntil, guardSnooze <= now {
            focusGuardSnoozedUntil = nil
        }

        evaluatePreDueReminders(now: now)
        evaluateFocusGuard(now: now)
        nudgeClockRevision &+= 1
        onHitRectNeedsUpdate?()
        scheduleNextNudgeWakeup(now: now)

        if !wokeTasks.isEmpty {
            if settings.soundEnabled {
                NSSound(named: NSSound.Name("Tink"))?.play()
            }
            if let firstWoke = wokeTasks.first {
                sendNotification(title: "Task Reminder", body: firstWoke.title)
            }
        }
        return !wokeTasks.isEmpty
    }

    private func scheduleNextNudgeWakeup(now: Date = Date()) {
        nudgeWakeTimer?.invalidate()
        nudgeWakeTimer = nil
        guard enableSystemIntegrationsFlag,
              let nextWake = nextScheduledNudgeWakeDate(now: now) else {
            return
        }
        // Pad slightly past target timestamp so wall-clock Date() checks compare >= target.
        let delay = max(0.25, nextWake.timeIntervalSince(now) + 0.2)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshLiveActivityState()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        nudgeWakeTimer = timer
    }

    public func completeActiveNudge() {
        if healthService.isEyeBreakDue {
            healthService.completeEyeBreak()
            nudgeClockRevision &+= 1
            onHitRectNeedsUpdate?()
            return
        }
        if let task = activeLiveNudgeTask {
            toggleTask(task.id)
        } else if let event = activeLiveNudgeEvent {
            dismissedEventIDs.insert(event.id)
            nudgeClockRevision &+= 1
            onHitRectNeedsUpdate?()
            scheduleNextNudgeWakeup()
        }
    }

    public func deleteTask(_ id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        let removed = tasks.remove(at: idx)
        taskRemainingSeconds.removeValue(forKey: id)
        autoTriggeredReminderTaskIDs.remove(id)
        if pinnedLiveActivityTaskID == id { pinnedLiveActivityTaskID = nil }
        if activeFocusTaskID == id {
            activeFocusTaskID = nil
            activeCountdownSourceIsReminder = false
        }
        if settings.syncReminders && eventKit.reminderAuth == .authorized {
            eventKit.deleteReminder(identifier: removed.reminderIdentifier)
        }
        persistence.saveTasks(tasks)
        nudgeClockRevision &+= 1
        onHitRectNeedsUpdate?()
        scheduleNextNudgeWakeup()
    }

    public func clearCompletedTasks() {
        let completed = tasks.filter { $0.isCompleted }
        if settings.syncReminders && eventKit.reminderAuth == .authorized {
            for item in completed {
                eventKit.deleteReminder(identifier: item.reminderIdentifier)
            }
        }
        tasks.removeAll { $0.isCompleted }
        persistence.saveTasks(tasks)
    }

    @discardableResult
    public func carryOverIncompleteToToday() -> Int {
        var moved = 0
        let calendar = Calendar.current
        let startToday = calendar.startOfDay(for: Date())
        let todayKey = dayKey(forDayOffset: 0)
        for idx in tasks.indices {
            if !tasks[idx].isCompleted,
               !isTaskInToday(tasks[idx], calendar: calendar),
               tasks[idx].createdAt < startToday {
                tasks[idx].scheduledBucket = .today
                tasks[idx].scheduledDayKey = todayKey
                moved += 1
            }
        }
        if moved > 0 {
            sortAndSaveTasks()
        }
        return moved
    }

    public func syncWithReminders() async {
        if eventKit.reminderAuth == .notDetermined {
            _ = await eventKit.requestRemindersAccess()
        }
        guard eventKit.reminderAuth == .authorized else { return }

        let remote = await eventKit.fetchRemindersFromNotchNestList()
        var byReminderID: [String: Int] = [:]
        for (index, item) in tasks.enumerated() {
            if let rid = item.reminderIdentifier {
                byReminderID[rid] = index
            }
        }

        for remoteItem in remote {
            guard let rid = remoteItem.reminderIdentifier else { continue }
            if let existingIdx = byReminderID[rid] {
                tasks[existingIdx].title = remoteItem.title
                tasks[existingIdx].isCompleted = remoteItem.isCompleted
                tasks[existingIdx].completedAt = remoteItem.completedAt
            } else {
                tasks.append(remoteItem)
            }
        }

        for index in tasks.indices where tasks[index].reminderIdentifier == nil {
            tasks[index].reminderIdentifier = eventKit.upsertReminder(for: tasks[index])
        }
        sortAndSaveTasks()
    }

    private func sortAndSaveTasks() {
        tasks.sort { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted
            }
            if lhs.priority != rhs.priority {
                return lhs.priority == .high
            }
            if let lDue = lhs.dueDate, let rDue = rhs.dueDate, lDue != rDue {
                return lDue < rDue
            }
            return lhs.createdAt > rhs.createdAt
        }
        persistence.saveTasks(tasks)
    }

    // MARK: - Focus & Ambient Audio

    public func effectiveFocusMinutes(for task: TaskItem? = nil) -> Int {
        max(1, task?.targetMinutes ?? settings.focusMinutes)
    }

    public func selectFocusTask(_ taskID: UUID?) {
        if let previousID = activeFocusTaskID,
           previousID != taskID,
           timer.phase == .focus,
           timer.state != .idle {
            timer.pause()
            let rem = timer.remainingSeconds
            if rem > 1 && rem < timer.totalDuration - 0.5 {
                taskRemainingSeconds[previousID] = rem
            } else {
                taskRemainingSeconds.removeValue(forKey: previousID)
            }
        }

        activeFocusTaskID = taskID
        activeCountdownSourceIsReminder = false
        let targetTask = taskID.flatMap { id in tasks.first(where: { $0.id == id }) }
        let total = TimeInterval(effectiveFocusMinutes(for: targetTask) * 60)
        let rem = taskID.flatMap { taskRemainingSeconds[$0] } ?? total
        timer.configure(totalSeconds: total, remainingSeconds: rem, phase: .focus)
        syncAmbientAudio()
        onHitRectNeedsUpdate?()
    }

    @discardableResult
    public func evaluatePreDueReminders(now: Date = Date()) -> TaskItem? {
        guard timer.state == .idle else { return nil }

        let candidates = tasks
            .filter { !$0.isCompleted && !autoTriggeredReminderTaskIDs.contains($0.id) }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }

        for task in candidates {
            guard let due = task.dueDate,
                  let lead = task.reminderLeadMinutes,
                  let windowStart = task.reminderWindowStartDate(),
                  now >= windowStart,
                  now < due.addingTimeInterval(600) else {
                continue
            }

            autoTriggeredReminderTaskIDs.insert(task.id)
            let seconds: TimeInterval
            if lead > 0 && due > now {
                seconds = max(15, due.timeIntervalSince(now))
            } else {
                seconds = TimeInterval(effectiveFocusMinutes(for: task) * 60)
            }

            isAmbientPreviewActive = false
            activeFocusTaskID = task.id
            activeCountdownSourceIsReminder = true
            timer.configure(totalSeconds: seconds, remainingSeconds: seconds, phase: .focus)
            timer.start()
            syncAmbientAudio()

            let displayMins = max(1, Int(ceil(seconds / 60)))
            postTransientLiveActivity(
                TransientLiveActivity(
                    category: .notifications,
                    title: "Reminder: \(task.title)",
                    subtitle: lead == 0 ? "Task is due now" : "Due in \(displayMins)m — countdown active",
                    badgeText: "\(displayMins)m",
                    symbolName: "bell.badge.fill",
                    accentHex: "#FAC03D",
                    targetTab: .today
                ),
                durationSeconds: 4.5
            )
            onHitRectNeedsUpdate?()
            return task
        }
        return nil
    }

    public func startFocus(on taskID: UUID? = nil) {
        if let taskID {
            let switchingTasks = activeFocusTaskID != taskID
            if switchingTasks || timer.state == .idle {
                selectFocusTask(taskID)
            }
        } else if timer.state == .idle, let linked = activeFocusTask {
            let total = TimeInterval(effectiveFocusMinutes(for: linked) * 60)
            let rem = taskRemainingSeconds[linked.id] ?? total
            timer.configure(totalSeconds: total, remainingSeconds: rem, phase: .focus)
        }

        isAmbientPreviewActive = false
        if timer.state == .running {
            syncAmbientAudio()
            return
        }
        if timer.state == .paused {
            timer.resume()
        } else {
            timer.start()
            let displayedMins = max(1, Int(ceil(timer.remainingSeconds / 60)))
            postTransientLiveActivity(
                TransientLiveActivity(
                    category: .pomodoro,
                    title: "Focus · \(displayedMins)m",
                    subtitle: activeFocusTask?.title ?? settings.focusSoundscape.label,
                    badgeText: "FOCUS",
                    symbolName: "flame.fill",
                    accentHex: "#EE9E5B",
                    targetTab: .timer
                )
            )
        }
        syncAmbientAudio()
    }

    public func toggleFocus(on taskID: UUID) {
        if activeFocusTaskID == taskID && timer.state == .running {
            timer.pause()
            if timer.phase == .focus {
                taskRemainingSeconds[taskID] = timer.remainingSeconds
            }
            syncAmbientAudio()
            onHitRectNeedsUpdate?()
        } else {
            startFocus(on: taskID)
        }
    }

    public func setFocusDuration(minutes: Int, for taskID: UUID? = nil) {
        let clamped = min(max(1, minutes), 240)
        let resolvedID = taskID ?? activeFocusTaskID
        if let targetID = resolvedID,
           let idx = tasks.firstIndex(where: { $0.id == targetID }) {
            tasks[idx].targetMinutes = clamped
            taskRemainingSeconds.removeValue(forKey: targetID)
            sortAndSaveTasks()
            if targetID == activeFocusTaskID {
                timer.configure(minutes: clamped, phase: .focus)
            }
        } else {
            settings.focusMinutes = clamped
            timer.configure(minutes: clamped, phase: .focus)
        }
        syncAmbientAudio()
        onHitRectNeedsUpdate?()
    }

    public func completeActiveFocusTask() {
        let linkedID = activeFocusTaskID
        let elapsedSeconds = (timer.phase == .focus && timer.state != .idle)
            ? max(0, timer.totalDuration - timer.remainingSeconds)
            : 0
        let elapsedMins = Int(elapsedSeconds / 60)

        if let linkedID, let idx = tasks.firstIndex(where: { $0.id == linkedID }) {
            if elapsedMins > 0 {
                tasks[idx].focusedMinutes += elapsedMins
                let today = DailyFocusStats.todayKey()
                if focusStats.dayKey != today {
                    focusStats = DailyFocusStats(dayKey: today)
                }
                focusStats.focusedMinutes += elapsedMins
                persistence.saveStats(focusStats)
                let currentHour = Calendar.current.component(.hour, from: Date())
                updateTodayActivityRecord { record in
                    record.focusedMinutes += elapsedMins
                    record.hourlyFocusMinutes[currentHour, default: 0] += elapsedMins
                }
            }
            taskRemainingSeconds.removeValue(forKey: linkedID)
            activeCountdownSourceIsReminder = false
            timer.configure(minutes: settings.focusMinutes, phase: .focus)
            syncAmbientAudio()
            if !tasks[idx].isCompleted {
                toggleTask(linkedID)
            } else {
                activeFocusTaskID = nil
                sortAndSaveTasks()
            }
        } else {
            resetFocusTimer()
        }
    }

    public func toggleFocusPlayPause() {
        isAmbientPreviewActive = false
        timer.togglePlayPause()
        if timer.state == .paused, timer.phase == .focus, let id = activeFocusTaskID {
            taskRemainingSeconds[id] = timer.remainingSeconds
        }
        syncAmbientAudio()
    }

    public func resetFocusTimer() {
        isAmbientPreviewActive = false
        activeCountdownSourceIsReminder = false
        if let id = activeFocusTaskID {
            taskRemainingSeconds.removeValue(forKey: id)
        }
        let mins = effectiveFocusMinutes(for: activeFocusTask)
        timer.configure(minutes: mins, phase: .focus)
        syncAmbientAudio()
        onHitRectNeedsUpdate?()
    }

    public func toggleAmbientPreview() {
        isAmbientPreviewActive.toggle()
        syncAmbientAudio()
    }

    public func selectSoundscape(_ sound: FocusSoundscape) {
        settings.focusSoundscape = sound
        if sound == .none {
            isAmbientPreviewActive = false
        } else if timer.state != .running {
            isAmbientPreviewActive = true
        }
        syncAmbientAudio()
    }

    public func syncAmbientAudio() {
        let shouldPlay = (timer.state == .running || isAmbientPreviewActive)
        audioEngine.update(
            soundscape: settings.focusSoundscape,
            shouldPlay: shouldPlay,
            volume: settings.focusSoundVolume
        )
    }

    // MARK: - Notes

    private static let dailyNoteTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()

    public static func dailyNoteTitle(for date: Date = Date()) -> String {
        "Daily \(dailyNoteTitleFormatter.string(from: date))"
    }

    @discardableResult
    public func ensureTodayDailyNote(now: Date = Date(), calendar: Calendar = .current) -> NoteEntry {
        let todayKey = DailyFocusStats.todayKey(for: now)
        var changed = false

        // Remove untouched empty daily/scratchpad shells from previous days
        let beforeCount = notes.count
        notes.removeAll { note in
            let isEmpty = note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard isEmpty else { return false }
            if let key = note.dailyDayKey {
                return key != todayKey
            }
            let isDefaultShell = note.title == "Scratchpad" || note.title == "Daily Notepad" || note.title.hasPrefix("Daily ")
            return isDefaultShell && !calendar.isDate(note.updatedAt, inSameDayAs: now)
        }
        if notes.count != beforeCount {
            changed = true
        }

        let ensured: NoteEntry
        if let existingToday = notes.first(where: { $0.dailyDayKey == todayKey }) {
            ensured = existingToday
            if lastEnsuredDailyNoteKey != todayKey {
                selectedNoteID = existingToday.id
            }
        } else if let sameDayIdx = notes.firstIndex(where: {
            $0.dailyDayKey == nil &&
            !$0.title.hasPrefix("[") &&
            calendar.isDate($0.updatedAt, inSameDayAs: now)
        }) {
            notes[sameDayIdx].dailyDayKey = todayKey
            if notes[sameDayIdx].title == "Scratchpad" || notes[sameDayIdx].title == "Daily Notepad" {
                notes[sameDayIdx].title = Self.dailyNoteTitle(for: now)
            }
            changed = true
            ensured = notes[sameDayIdx]
            if lastEnsuredDailyNoteKey != todayKey {
                selectedNoteID = ensured.id
            }
        } else {
            let freshDaily = NoteEntry(
                title: Self.dailyNoteTitle(for: now),
                body: "",
                updatedAt: now,
                dailyDayKey: todayKey
            )
            notes.insert(freshDaily, at: 0)
            selectedNoteID = freshDaily.id
            changed = true
            ensured = freshDaily
        }

        lastEnsuredDailyNoteKey = todayKey
        if !notes.contains(where: { $0.id == selectedNoteID }) {
            selectedNoteID = ensured.id
        }
        if changed {
            persistence.saveNotes(notes)
        }
        return ensured
    }

    public func addNote() {
        let note = NoteEntry(title: "Note \(notes.count + 1)", body: "")
        notes.insert(note, at: 0)
        selectedNoteID = note.id
        persistence.saveNotes(notes)
    }

    @discardableResult
    public func openOrCreateMeetingNote(
        title: String,
        date: Date = Date(),
        switchToNotes: Bool = true
    ) -> NoteEntry {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTitle = cleanTitle.isEmpty ? "Meeting Notes" : cleanTitle
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let prefix = "[\(formatter.string(from: date))] \(effectiveTitle)"

        let chosen: NoteEntry
        if let existing = notes.first(where: { $0.title == prefix }) {
            chosen = existing
        } else {
            let template = """
            # \(effectiveTitle)

            ## Agenda
            - 

            ## Notes
            - 

            ## Action Items
            - 
            """
            let created = NoteEntry(title: prefix, body: template, updatedAt: date)
            notes.insert(created, at: 0)
            persistence.saveNotes(notes)
            chosen = created
        }

        if switchToNotes {
            selectedNoteID = chosen.id
            activeTab = .notes
            onRequestPanelExpand?(.notes)
        }
        return chosen
    }

    @discardableResult
    public func updateNoteBody(
        _ id: UUID,
        body: String,
        rtfData: Data? = nil,
        commitTodoPrefixes: Bool = false
    ) -> Int {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return 0 }

        let extraction = NoteTodoPrefixExtractor.extract(from: body, commitLastLine: commitTodoPrefixes)
        let finalBody: String
        let finalRTF: Data?

        if extraction.replacements.isEmpty {
            finalBody = body
            finalRTF = rtfData
        } else {
            finalBody = extraction.updatedBody
            if let rtfData,
               let mutable = NSMutableAttributedString(rtf: rtfData, documentAttributes: nil) {
                for rep in extraction.replacements.reversed() {
                    let nsRange = NSRange(location: rep.location, length: rep.length)
                    if nsRange.location >= 0, nsRange.location + nsRange.length <= mutable.length {
                        mutable.replaceCharacters(in: nsRange, with: rep.replacement)
                    }
                }
                finalRTF = try? mutable.data(
                    from: NSRange(location: 0, length: mutable.length),
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
                )
            } else {
                finalRTF = nil
            }
        }

        notes[idx].body = finalBody
        notes[idx].rtfData = finalRTF
        notes[idx].updatedAt = Date()
        if notes[idx].title.hasPrefix("Scratchpad") || notes[idx].title.hasPrefix("Daily") || notes[idx].title.hasPrefix("Note ") {
            let firstLine = finalBody.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces)
            if let firstLine, !firstLine.isEmpty {
                notes[idx].title = String(firstLine.prefix(24))
            }
        }
        persistence.saveNotes(notes)

        let extractedCount = extraction.extractedItems.count
        if extractedCount > 0 {
            let noteDayKey = notes[idx].dailyDayKey ?? dayKey(forDayOffset: 0) ?? DailyFocusStats.todayKey()
            let defaultBucket: TaskBucket
            if let dayDate = DailyFocusStats.date(fromDayKey: noteDayKey),
               Calendar.current.isDateInTomorrow(dayDate) {
                defaultBucket = .tomorrow
            } else {
                defaultBucket = .today
            }
            for item in extraction.extractedItems {
                addParsedTask(
                    item.taskInput,
                    defaultBucket: defaultBucket,
                    defaultDayKey: noteDayKey,
                    priorityOverride: item.priority
                )
            }

            let summary = extractedCount == 1
                ? "+Todo: \(extraction.extractedItems[0].taskInput)"
                : "+\(extractedCount) todos added"
            autoConvertedNoteBanner = summary
            autoConvertedBannerTask?.cancel()
            autoConvertedBannerTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2.4))
                guard !Task.isCancelled else { return }
                self?.autoConvertedNoteBanner = nil
            }
        }
        return extractedCount
    }

    public func appendToActiveNote(_ rawText: String) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if notes.isEmpty {
            let created = NoteEntry(title: "Daily Notepad", body: trimmed)
            notes = [created]
            selectedNoteID = created.id
            persistence.saveNotes(notes)
            return
        }

        let idx = notes.firstIndex(where: { $0.id == selectedNoteID }) ?? 0
        selectedNoteID = notes[idx].id
        let existing = notes[idx].body
        let separator = existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : (existing.hasSuffix("\n") ? "" : "\n")
        let appended = existing + separator + trimmed

        var appendedRTF: Data? = nil
        if let existingRTF = notes[idx].rtfData,
           let mutable = NSMutableAttributedString(rtf: existingRTF, documentAttributes: nil) {
            let suffix = separator + trimmed
            let baseAttrs: [NSAttributedString.Key: Any] = mutable.length > 0
                ? mutable.attributes(at: max(0, mutable.length - 1), effectiveRange: nil)
                : [.font: NSFont.systemFont(ofSize: 12)]
            mutable.append(NSAttributedString(string: suffix, attributes: baseAttrs))
            appendedRTF = try? mutable.data(
                from: NSRange(location: 0, length: mutable.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
        }
        updateNoteBody(notes[idx].id, body: appended, rtfData: appendedRTF)
    }

    public func sendToTranslator(
        _ text: String,
        targetLanguage: String? = nil,
        triggerTranslation: Bool = true
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        devHubService.translationInput = trimmed
        if let targetLanguage, !targetLanguage.isEmpty {
            devHubService.translationTargetLanguage = targetLanguage
        }
        selectedHubSection = .devAI
        activeTab = .hub
        onRequestPanelExpand?(.hub)

        if triggerTranslation {
            let currentSettings = settings
            Task { @MainActor [weak self] in
                await self?.devHubService.translate(settings: currentSettings)
            }
        }
    }

    @discardableResult
    public func executeWorkspaceCommand(_ command: WorkspaceQuickCommand) -> Bool {
        switch command {
        case .appendNote(let text):
            appendToActiveNote(text)
            postTransientLiveActivity(
                TransientLiveActivity(
                    category: .systemHUD,
                    title: "Added to Note",
                    subtitle: text,
                    badgeText: "NOTE",
                    symbolName: "note.text",
                    accentHex: "#B8D0BA",
                    targetTab: .notes
                )
            )
            return true

        case .startFocus(let minutes):
            isAmbientPreviewActive = false
            timer.start(minutes: minutes, phase: .focus)
            syncAmbientAudio()
            postTransientLiveActivity(
                TransientLiveActivity(
                    category: .pomodoro,
                    title: "Focus · \(minutes)m",
                    subtitle: activeFocusTask?.title ?? settings.focusSoundscape.label,
                    badgeText: "FOCUS",
                    symbolName: "flame.fill",
                    accentHex: "#EE9E5B",
                    targetTab: .timer
                )
            )
            onHitRectNeedsUpdate?()
            return true

        case .startMicroTimer(let label, let minutes):
            _ = startMicroTimer(label: label, minutes: minutes)
            return true

        case .translate(let targetLanguage, let text):
            sendToTranslator(text, targetLanguage: targetLanguage, triggerTranslation: true)
            return true

        case .snapWindow(let zone):
            _ = snapWindow(to: zone)
            return true
        }
    }

    // MARK: - Stacked Micro-Timers, Focus Guard & Scroll Gestures (Phase 3)

    private func loadPersistedMicroTimers(now: Date = Date()) {
        let loaded = persistence.loadMicroTimers()
        var active: [MicroTimerItem] = []
        for var item in loaded {
            if item.isPaused {
                if item.remainingSeconds > 0 {
                    active.append(item)
                }
            } else if let end = item.endDate {
                let rem = end.timeIntervalSince(now)
                if rem > 1 {
                    item.remainingSeconds = rem
                    active.append(item)
                }
            }
        }
        microTimers = active
        if active.count != loaded.count {
            persistence.saveMicroTimers(active)
        }
    }

    @discardableResult
    public func startMicroTimer(label: String, minutes: Int, now: Date = Date()) -> MicroTimerItem {
        let clampedMinutes = min(max(1, minutes), 180)
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveLabel = cleanLabel.isEmpty ? "Timer" : cleanLabel

        microTimers.removeAll { $0.label.caseInsensitiveCompare(effectiveLabel) == .orderedSame }
        if microTimers.count >= 5 {
            microTimers.removeLast()
        }

        let item = MicroTimerItem(label: effectiveLabel, minutes: clampedMinutes, now: now)
        microTimers.insert(item, at: 0)
        persistence.saveMicroTimers(microTimers)
        syncMicroTimerTicker()
        onHitRectNeedsUpdate?()

        postTransientLiveActivity(
            TransientLiveActivity(
                category: .pomodoro,
                title: "\(item.label) · \(clampedMinutes)m",
                subtitle: "Micro-timer counting down",
                badgeText: "TIMER",
                symbolName: "timer",
                accentHex: "#38BDF8",
                targetTab: .timer
            ),
            durationSeconds: 3.0
        )
        return item
    }

    public func toggleMicroTimerPause(_ id: UUID, now: Date = Date()) {
        guard let idx = microTimers.firstIndex(where: { $0.id == id }) else { return }
        if microTimers[idx].isPaused {
            microTimers[idx].isPaused = false
            microTimers[idx].endDate = now.addingTimeInterval(microTimers[idx].remainingSeconds)
        } else {
            if let end = microTimers[idx].endDate {
                microTimers[idx].remainingSeconds = max(0, end.timeIntervalSince(now))
            }
            microTimers[idx].isPaused = true
            microTimers[idx].endDate = nil
        }
        persistence.saveMicroTimers(microTimers)
        syncMicroTimerTicker()
    }

    public func dismissMicroTimer(_ id: UUID) {
        microTimers.removeAll { $0.id == id }
        persistence.saveMicroTimers(microTimers)
        syncMicroTimerTicker()
        onHitRectNeedsUpdate?()
    }

    public func clearMicroTimers() {
        microTimers.removeAll()
        persistence.saveMicroTimers([])
        syncMicroTimerTicker()
        onHitRectNeedsUpdate?()
    }

    @discardableResult
    public func tickMicroTimers(now: Date = Date()) -> [MicroTimerItem] {
        guard !microTimers.isEmpty else { return [] }
        var completed: [MicroTimerItem] = []
        var updated: [MicroTimerItem] = []

        for var item in microTimers {
            if !item.isPaused, let end = item.endDate {
                let rem = end.timeIntervalSince(now)
                if rem <= 0 {
                    item.remainingSeconds = 0
                    completed.append(item)
                    continue
                }
                item.remainingSeconds = rem
            }
            updated.append(item)
        }

        microTimers = updated
        if !completed.isEmpty {
            persistence.saveMicroTimers(updated)
            syncMicroTimerTicker()
            if settings.soundEnabled {
                NSSound(named: NSSound.Name("Glass"))?.play()
            }
            for item in completed {
                sendNotification(
                    title: "Timer Complete",
                    body: "\(item.label) finished."
                )
                postTransientLiveActivity(
                    TransientLiveActivity(
                        category: .pomodoro,
                        title: "Done · \(item.label)",
                        subtitle: "\(Int(round(item.totalSeconds / 60)))m micro-timer finished",
                        badgeText: "DONE",
                        symbolName: "checkmark.seal.fill",
                        accentHex: "#21C473",
                        targetTab: .timer
                    ),
                    durationSeconds: 4.5
                )
            }
            triggerMascotPulse()
            onHitRectNeedsUpdate?()
        }
        return completed
    }

    private func syncMicroTimerTicker() {
        let hasRunning = microTimers.contains { !$0.isPaused }
        if hasRunning {
            guard microTimerTickTimer == nil else { return }
            let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.tickMicroTimers()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            microTimerTickTimer = timer
        } else {
            microTimerTickTimer?.invalidate()
            microTimerTickTimer = nil
        }
    }

    @discardableResult
    public func evaluateFocusGuard(now: Date = Date()) -> String? {
        guard timer.phase == .focus, timer.state == .running else { return nil }
        guard let bundleID = screenTimeService.currentFrontmostBundleID,
              let appName = screenTimeService.currentFrontmostAppName,
              let category = screenTimeService.currentFrontmostCategory,
              let enteredAt = screenTimeService.currentFrontmostEnteredAt else {
            return nil
        }

        let dwell = now.timeIntervalSince(enteredAt)
        guard ScreenTimeService.shouldTriggerFocusGuard(
            bundleID: bundleID,
            appName: appName,
            category: category,
            dwellSeconds: dwell,
            isFocusing: true,
            settings: settings,
            now: now,
            snoozedUntil: focusGuardSnoozedUntil,
            lastNudgedAtByBundle: focusGuardLastNudgeByBundle
        ) else {
            return nil
        }

        focusGuardLastNudgeByBundle[bundleID] = now
        let subtitle = activeFocusTask.map { "Return to: \($0.title)" }
            ?? "Focus block active · \(timer.formattedRemaining) left"
        postTransientLiveActivity(
            TransientLiveActivity(
                category: .notifications,
                title: "Focus Guard · \(appName)",
                subtitle: subtitle,
                badgeText: "FOCUS",
                symbolName: "eye.trianglebadge.exclamationmark",
                accentHex: "#EE9E5B",
                targetTab: .today
            ),
            durationSeconds: 4.8
        )
        return appName
    }

    public func snoozeFocusGuard(minutes: Int = 20, now: Date = Date()) {
        focusGuardSnoozedUntil = now.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        if transientLiveActivity?.title.hasPrefix("Focus Guard") == true {
            dismissTransientLiveActivity()
        }
        scheduleNextNudgeWakeup(now: now)
    }

    @discardableResult
    public func handleCollapsedScroll(
        deltaX: Double,
        deltaY: Double,
        hasPreciseDeltas: Bool,
        isMomentumPhase: Bool,
        now: Date = Date()
    ) -> NotchScrollGestureAction? {
        guard settings.scrollWheelGesturesEnabled, !isExpanded else { return nil }

        let isMediaSlotActive =
            (settings.collapsedDisplayMode == .music)
            || (settings.collapsedDisplayMode == .automatic
                && settings.showMediaInNotch
                && mediaService.currentTrack?.isPlaying == true
                && timer.state == .idle)

        guard let action = scrollGestureRecognizer.ingest(
            deltaX: deltaX,
            deltaY: deltaY,
            hasPreciseDeltas: hasPreciseDeltas,
            isMomentumPhase: isMomentumPhase,
            isMediaSlotActive: isMediaSlotActive,
            now: now
        ) else {
            return nil
        }

        switch action {
        case .adjustVolume(let delta):
            let nextVol = min(1.0, max(0.0, systemService.systemVolume + delta))
            systemService.setSystemVolume(nextVol)
            let pct = Int(round(nextVol * 100))
            postTransientLiveActivity(
                TransientLiveActivity(
                    category: .systemHUD,
                    title: pct == 0 ? "Volume Muted" : "Volume · \(pct)%",
                    subtitle: "Scroll vertically over notch to adjust",
                    badgeText: "\(pct)%",
                    symbolName: pct == 0 ? "speaker.slash.fill" : (pct < 45 ? "speaker.wave.1.fill" : "speaker.wave.3.fill"),
                    accentHex: "#38BDF8",
                    targetTab: .hub,
                    targetHubSection: .overview
                ),
                durationSeconds: 1.8
            )

        case .cycleCollapsedMode(let step):
            let modes = CollapsedDisplayMode.allCases
            if let currentIdx = modes.firstIndex(of: settings.collapsedDisplayMode) {
                let count = modes.count
                let nextIdx = ((currentIdx + step) % count + count) % count
                settings.collapsedDisplayMode = modes[nextIdx]
                onHitRectNeedsUpdate?()
            }

        case .skipTrack(let step):
            if step > 0 {
                mediaService.nextTrack()
            } else {
                mediaService.previousTrack()
            }
        }
        return action
    }

    public func resetScrollGestureState() {
        scrollGestureRecognizer.reset()
    }

    @discardableResult
    public func convertNoteLinesToTasks(_ id: UUID) -> Int {
        guard let note = notes.first(where: { $0.id == id }) else { return 0 }
        let lines = note.body
            .components(separatedBy: .newlines)
            .compactMap { rawLine -> String? in
                let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      !trimmed.hasPrefix("[✓]"),
                      !trimmed.hasPrefix("☑"),
                      !trimmed.hasPrefix("[x]"),
                      !trimmed.hasPrefix("[X]") else {
                    return nil
                }
                let cleaned = trimmed
                    .replacingOccurrences(of: #"^(?:[-*•]|!!?|\[[\s]?\]|☐|todo:|/todo|@todo|\d+\.)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.isEmpty ? nil : cleaned
            }

        guard !lines.isEmpty else { return 0 }
        for line in lines.reversed() {
            addParsedTask(line, defaultBucket: .today)
        }
        return lines.count
    }

    public func deleteNote(_ id: UUID) {
        notes.removeAll { $0.id == id }
        if notes.isEmpty {
            let fallback = NoteEntry(title: "Daily Notepad", body: "")
            notes = [fallback]
        }
        if !notes.contains(where: { $0.id == selectedNoteID }) {
            selectedNoteID = notes[0].id
        }
        persistence.saveNotes(notes)
    }

    public func copyNoteToPasteboard(_ note: NoteEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let rtfData = note.rtfData {
            pasteboard.declareTypes([.rtf, .string], owner: nil)
            pasteboard.setData(rtfData, forType: .rtf)
            pasteboard.setString(note.body, forType: .string)
        } else {
            pasteboard.setString(note.body, forType: .string)
        }
    }

    // MARK: - Clips

    public func addDroppedFiles(_ urls: [URL]) {
        var changed = false
        for url in urls where url.isFileURL {
            if let existingIdx = pinnedOrDroppedClips.firstIndex(where: { $0.path == url.path }) {
                pinnedOrDroppedClips[existingIdx].addedAt = Date()
                pinnedOrDroppedClips[existingIdx].isPinned = true
            } else {
                let item = ClipItem(
                    url: url,
                    addedAt: Date(),
                    isPinned: true,
                    isImage: ClipsFilter.isImageFile(url)
                )
                pinnedOrDroppedClips.insert(item, at: 0)
            }
            changed = true
        }
        if changed {
            persistence.savePinnedClips(pinnedOrDroppedClips)
            clips = mergeClips()
        }
    }

    public func toggleClipPin(_ item: ClipItem) {
        if let idx = pinnedOrDroppedClips.firstIndex(where: { $0.path == item.path }) {
            pinnedOrDroppedClips.remove(at: idx)
        } else {
            var pinned = item
            pinned.isPinned = true
            pinnedOrDroppedClips.insert(pinned, at: 0)
        }
        persistence.savePinnedClips(pinnedOrDroppedClips)
        clips = mergeClips()
    }

    public func removeClip(_ item: ClipItem) {
        pinnedOrDroppedClips.removeAll { $0.path == item.path }
        watchedScreenshots.removeAll { $0.path == item.path }
        persistence.savePinnedClips(pinnedOrDroppedClips)
        clips = mergeClips()
    }

    public func refreshClips() {
        clipsWatcher?.scanNow()
        clips = mergeClips()
    }

    public func handleDroppedFilesForActions(_ urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return }
        addDroppedFiles(fileURLs)
        pendingActionURLs = fileURLs
        dropActionFeedback = fileURLs.count == 1
            ? "Staged \(fileURLs[0].lastPathComponent) — pick an action or keep on Shelf"
            : "Staged \(fileURLs.count) items — pick an action or keep on Shelf"
    }

    public func performDropAction(_ action: DropActionKind, on urls: [URL]) async {
        let targets = urls.filter(\.isFileURL)
        guard !targets.isEmpty else { return }
        let message = await DropActionExecutor.execute(
            action,
            urls: targets,
            onAddToShelf: { [weak self] added in
                self?.addDroppedFiles(added)
            }
        )
        dropActionFeedback = message
        if action == .trash {
            let trashedPaths = Set(targets.map(\.path))
            pinnedOrDroppedClips.removeAll { trashedPaths.contains($0.path) }
            watchedScreenshots.removeAll { trashedPaths.contains($0.path) }
            persistence.savePinnedClips(pinnedOrDroppedClips)
            clips = mergeClips()
            pendingActionURLs.removeAll { trashedPaths.contains($0.path) }
        } else if action == .eject {
            pendingActionURLs.removeAll()
        }
    }

    public func dismissDropActionBanner() {
        pendingActionURLs.removeAll()
        dropActionFeedback = nil
    }

    // MARK: - Hub, Weather, Sleep & Wellbeing

    public func refreshWeather(force: Bool = false) {
        if !force, let lastWeatherRefreshAt, Date().timeIntervalSince(lastWeatherRefreshAt) < 15 * 60 {
            return
        }
        lastWeatherRefreshAt = Date()
        weatherService.refresh(city: settings.weatherCity, unit: settings.weatherUnit)
    }

    public func togglePreventSleep() {
        settings.preventSleepEnabled.toggle()
    }

    public func requestWorkspaceInputFocus(seed: String = "") {
        if !seed.isEmpty {
            pendingWorkspaceTypedSeed += seed
        }
        workspaceFocusRequestNonce &+= 1
    }

    public func prepareMeetingHandoff(title: String?, createNote: Bool) {
        if settings.autoPauseMediaOnJoin {
            mediaService.pauseIfPlaying()
            if isAmbientPreviewActive {
                isAmbientPreviewActive = false
                syncAmbientAudio()
            }
        }
        if createNote, let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = openOrCreateMeetingNote(title: title, switchToNotes: false)
        }
    }

    public func joinMeeting(url: URL, title: String? = nil, openPrepNote: Bool? = nil) {
        prepareMeetingHandoff(title: title, createNote: openPrepNote ?? settings.createMeetingNoteOnJoin)
        NSWorkspace.shared.open(url)
    }

    public func toggleDarkModeWithHUD() {
        systemService.toggleDarkMode()
        postTransientLiveActivity(
            TransientLiveActivity(
                category: .systemHUD,
                title: "Appearance Updated",
                subtitle: "Toggled macOS Dark Mode",
                badgeText: "HUD",
                symbolName: "circle.lefthalf.filled",
                accentHex: "#38BDF8",
                targetTab: .hub,
                targetHubSection: .overview
            )
        )
    }

    @discardableResult
    public func toggleMicMuteWithHUD() -> Bool {
        systemService.refreshMicState()
        guard systemService.hasAudioInputDevice else {
            postTransientLiveActivity(
                TransientLiveActivity(
                    category: .systemHUD,
                    title: "No Microphone",
                    subtitle: "No active audio input device detected",
                    badgeText: "AUDIO",
                    symbolName: "mic.slash",
                    accentHex: "#FA7070",
                    targetTab: .hub,
                    targetHubSection: .overview
                )
            )
            return false
        }

        let muted = systemService.toggleMicMute()
        postTransientLiveActivity(
            TransientLiveActivity(
                category: .systemHUD,
                title: muted ? "Mic Muted" : "Mic Live",
                subtitle: muted ? "Default input muted · ⌥M to unmute" : "Default microphone active",
                badgeText: muted ? "MUTED" : "LIVE",
                symbolName: muted ? "mic.slash.fill" : "mic.fill",
                accentHex: muted ? "#FA7070" : "#B8D0BA",
                targetTab: .hub,
                targetHubSection: .overview
            )
        )
        onHitRectNeedsUpdate?()
        return muted
    }

    @discardableResult
    public func snapWindow(to zone: SnapZone) -> Result<String, SnapError> {
        let result = snapService.snapFrontmostWindow(to: zone)
        if case .success(let message) = result {
            postTransientLiveActivity(
                TransientLiveActivity(
                    category: .systemHUD,
                    title: "Window Snapped",
                    subtitle: message,
                    badgeText: zone.title,
                    symbolName: "macwindow.split.2x2",
                    accentHex: "#38BDF8",
                    targetTab: .hub,
                    targetHubSection: .snap
                )
            )
        }
        return result
    }

    public func postTransientLiveActivity(
        _ activity: TransientLiveActivity,
        durationSeconds: Double = 3.8
    ) {
        guard settings.showLiveActivityNudge, settings.showTransientLiveActivities else { return }
        transientDismissTask?.cancel()
        transientLiveActivity = activity
        onHitRectNeedsUpdate?()

        let expectedID = activity.id
        transientDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(max(1.0, durationSeconds) * 1000)))
            guard !Task.isCancelled, let self else { return }
            if self.transientLiveActivity?.id == expectedID {
                self.transientLiveActivity = nil
                self.onHitRectNeedsUpdate?()
            }
        }
    }

    public func dismissTransientLiveActivity() {
        transientDismissTask?.cancel()
        transientDismissTask = nil
        if transientLiveActivity != nil {
            transientLiveActivity = nil
            onHitRectNeedsUpdate?()
        }
    }

    public func triggerLiveActivityPreview() {
        let nextEventTitle = eventKit.upcomingEvents.first?.title
        let summary = nextEventTitle.map { "\(openTaskCount) open · Next: \($0)" }
            ?? "\(openTaskCount) open tasks · Focus ready"
        postTransientLiveActivity(
            TransientLiveActivity(
                category: .notifications,
                title: "Live Activity Active",
                subtitle: summary,
                badgeText: "LIVE",
                symbolName: "bell.badge.fill",
                accentHex: "#C3D3BD",
                targetTab: .hub,
                targetHubSection: .overview
            ),
            durationSeconds: 4.5
        )
    }

    public func dayProgressFraction(now: Date = Date()) -> Double {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: now)
        let currentMinutes = Double((comps.hour ?? 9) * 60 + (comps.minute ?? 0))
        let startMinutes = 8.0 * 60.0
        let endMinutes = Double(max(12, min(24, settings.bedtimeHour))) * 60.0
        guard endMinutes > startMinutes else { return 0.5 }
        return min(1.0, max(0.0, (currentMinutes - startMinutes) / (endMinutes - startMinutes)))
    }

    public func shutdown() {
        transientDismissTask?.cancel()
        transientDismissTask = nil
        if let screenUnlockObserver {
            DistributedNotificationCenter.default().removeObserver(screenUnlockObserver)
            self.screenUnlockObserver = nil
        }
        cameraMirror.stop()
        audioEngine.stop()
        voiceCapture.stopRecording()
        mediaService.stopMonitoring()
        clipboardService.stopMonitoring()
        systemService.stopMonitoring()
        screenTimeService.stopTracking()
        healthService.stop()
        snapService.stop()
        clipsWatcher?.stop()
        hotKeyManager?.unregister()
        nudgeRefreshTimer?.invalidate()
        nudgeRefreshTimer = nil
        nudgeWakeTimer?.invalidate()
        nudgeWakeTimer = nil
        microTimerTickTimer?.invalidate()
        microTimerTickTimer = nil
    }

    private func mergeClips() -> [ClipItem] {
        var seenPaths: Set<String> = []
        var merged: [ClipItem] = []

        for item in pinnedOrDroppedClips {
            if FileManager.default.fileExists(atPath: item.path), seenPaths.insert(item.path).inserted {
                merged.append(item)
            }
        }
        for item in watchedScreenshots {
            if FileManager.default.fileExists(atPath: item.path), seenPaths.insert(item.path).inserted {
                merged.append(item)
            }
        }
        return merged.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            return lhs.addedAt > rhs.addedAt
        }
    }

    // MARK: - Camera & Travel Time

    public func updateMirrorActivation() {
        if isExpanded && activeTab == .mirror {
            Task { await cameraMirror.requestAndStart() }
        } else {
            cameraMirror.stop()
        }
    }

    public func refreshTravelTimes() {
        travelTimeService.estimateTravelTimesIfPossible(for: eventKit.upcomingEvents) { [weak self] location, mins in
            self?.eventKit.updateTravelTime(minutes: mins, forLocation: location)
        }
    }

    // MARK: - Private Setup & Side Effects

    private func setupIntegrations() {
        eventKit.onEventsRefreshed = { [weak self] _ in
            self?.refreshTravelTimes()
            self?.nudgeClockRevision &+= 1
            self?.onHitRectNeedsUpdate?()
            self?.scheduleNextNudgeWakeup()
        }
        eventKit.refreshEvents()

        let watcher = ClipsWatcher { [weak self] items in
            self?.watchedScreenshots = items
            if let self {
                self.clips = self.mergeClips()
            }
        }
        self.clipsWatcher = watcher
        if settings.watchScreenshots {
            watcher.start()
        }

        let hk = GlobalHotKeyManager { [weak self] in
            self?.onRequestPanelToggle?()
        }
        self.hotKeyManager = hk
        if settings.globalShortcutEnabled {
            hk.register(style: settings.shortcutStyle)
        }

        // Refresh timer state, weather, and live nudge window periodically
        let refreshTimer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.ensureTodayDailyNote()
                self.refreshLiveActivityState()
                if self.timer.state != self.lastObservedTimerState {
                    self.lastObservedTimerState = self.timer.state
                    self.syncAmbientAudio()
                }
                self.refreshWeather(force: false)
            }
        }
        RunLoop.main.add(refreshTimer, forMode: .common)
        nudgeRefreshTimer = refreshTimer
        scheduleNextNudgeWakeup()

        healthService.onEyeBreakDue = { [weak self] in
            guard let self else { return }
            self.onHitRectNeedsUpdate?()
            self.sendNotification(
                title: "20-20-20 Eye Break",
                body: "Look at something 20 feet away for 20 seconds."
            )
        }
        healthService.setEyeBreakReminder(enabled: settings.eyeBreakReminderEnabled)
        mediaService.preferredPlayer = settings.preferredMusicPlayer
        mediaService.onTrackChanged = { [weak self] track in
            guard let self else { return }
            guard track.isPlaying, self.timer.state == .idle else { return }
            guard self.settings.collapsedDisplayMode == .automatic || self.settings.collapsedDisplayMode == .music else {
                return
            }
            self.postTransientLiveActivity(
                TransientLiveActivity(
                    category: .media,
                    title: track.title,
                    subtitle: track.artist.isEmpty ? track.appName : "\(track.artist) · \(track.appName)",
                    badgeText: track.appName,
                    symbolName: "music.note",
                    accentHex: "#EE9E5B",
                    targetTab: .hub,
                    targetHubSection: .overview
                )
            )
        }
        mediaService.startMonitoring()

        systemService.onBluetoothEvent = { [weak self] dev, isLow in
            self?.postTransientLiveActivity(
                TransientLiveActivity(
                    category: .bluetooth,
                    title: isLow ? "\(dev.name) Low" : "\(dev.name) Connected",
                    subtitle: isLow ? "Accessory battery at \(dev.percent)%" : "Battery \(dev.percent)%",
                    badgeText: "\(dev.percent)%",
                    symbolName: dev.systemImage,
                    accentHex: isLow ? "#FA7070" : "#38BDF8",
                    targetTab: .hub,
                    targetHubSection: .overview
                ),
                durationSeconds: 4.2
            )
        }
        systemService.onLowBattery = { [weak self] pct in
            self?.postTransientLiveActivity(
                TransientLiveActivity(
                    category: .systemHUD,
                    title: "Low Mac Battery",
                    subtitle: "\(pct)% remaining — plug in power adapter",
                    badgeText: "\(pct)%",
                    symbolName: "battery.25",
                    accentHex: "#FA7070",
                    targetTab: .hub,
                    targetHubSection: .overview
                ),
                durationSeconds: 4.5
            )
        }
        systemService.startMonitoring()
        if settings.clipboardHistoryEnabled {
            clipboardService.startMonitoring()
        }
        systemService.setPreventSleep(settings.preventSleepEnabled)
        screenTimeService.onSampleRecorded = { [weak self] in
            self?.evaluateFocusGuard()
        }
        screenTimeService.startTracking()
        syncMicroTimerTicker()
        snapService.updateTopEdgeDragSnap(enabled: settings.snapOnTopEdgeDrag)
        onPrivacyModeChanged?(settings.hideInScreenCapture)
        refreshWeather(force: true)

        screenUnlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let nextMeeting = self.eventKit.upcomingEvents.first?.title
                let subtitle = nextMeeting.map { "\(self.openTaskCount) open · Next: \($0)" }
                    ?? "\(self.openTaskCount) open tasks ready"
                self.postTransientLiveActivity(
                    TransientLiveActivity(
                        category: .sessionLock,
                        title: "Welcome Back",
                        subtitle: subtitle,
                        badgeText: "UNLOCKED",
                        symbolName: "lock.open.fill",
                        accentHex: "#C3D3BD",
                        targetTab: .today
                    ),
                    durationSeconds: 4.0
                )
            }
        }
    }

    private func applySettingsSideEffects(from old: AppSettings) {
        if old.watchScreenshots != settings.watchScreenshots {
            if settings.watchScreenshots {
                clipsWatcher?.start()
            } else {
                clipsWatcher?.stop()
                watchedScreenshots = []
                clips = mergeClips()
            }
        }
        if old.clipboardHistoryEnabled != settings.clipboardHistoryEnabled {
            if settings.clipboardHistoryEnabled {
                clipboardService.startMonitoring()
            } else {
                clipboardService.stopMonitoring()
            }
        }
        if old.globalShortcutEnabled != settings.globalShortcutEnabled || old.shortcutStyle != settings.shortcutStyle {
            if settings.globalShortcutEnabled {
                hotKeyManager?.register(style: settings.shortcutStyle)
            } else {
                hotKeyManager?.unregister()
            }
        }
        if old.focusMinutes != settings.focusMinutes && timer.state == .idle && timer.phase == .focus {
            timer.configure(minutes: settings.focusMinutes, phase: .focus)
        }
        if old.focusSoundscape != settings.focusSoundscape || old.focusSoundVolume != settings.focusSoundVolume {
            syncAmbientAudio()
        }
        if old.collapsedWidth != settings.collapsedWidth
            || old.displayMode != settings.displayMode
            || old.isWideDrawer != settings.isWideDrawer {
            onLayoutSettingsChanged?()
        }
        if old.showLiveActivityNudge != settings.showLiveActivityNudge
            || old.showTransientLiveActivities != settings.showTransientLiveActivities
            || old.showMediaInNotch != settings.showMediaInNotch
            || old.showMicIndicatorInNotch != settings.showMicIndicatorInNotch
            || old.collapsedDisplayMode != settings.collapsedDisplayMode
            || old.expandedCountdownStyle != settings.expandedCountdownStyle
            || old.showExpandedVitals != settings.showExpandedVitals {
            if !settings.showLiveActivityNudge || !settings.showTransientLiveActivities {
                dismissTransientLiveActivity()
            } else if old.collapsedDisplayMode != settings.collapsedDisplayMode,
                      settings.collapsedDisplayMode != .automatic && settings.collapsedDisplayMode != .music,
                      transientLiveActivity?.category == .media {
                dismissTransientLiveActivity()
            }
            onHitRectNeedsUpdate?()
        }
        if old.preferredMusicPlayer != settings.preferredMusicPlayer {
            mediaService.preferredPlayer = settings.preferredMusicPlayer
            postTransientLiveActivity(
                TransientLiveActivity(
                    category: .media,
                    title: "Music Player: \(settings.preferredMusicPlayer.label)",
                    subtitle: settings.preferredMusicPlayer == .youTubeMusic
                        ? "Tracking Chrome / Safari music.youtube.com"
                        : "Source updated",
                    badgeText: settings.preferredMusicPlayer.shortLabel,
                    symbolName: "music.note",
                    accentHex: "#EE9E5B",
                    targetTab: .hub,
                    targetHubSection: .overview
                )
            )
            onHitRectNeedsUpdate?()
        }
        if old.hideInScreenCapture != settings.hideInScreenCapture {
            onPrivacyModeChanged?(settings.hideInScreenCapture)
            postTransientLiveActivity(
                TransientLiveActivity(
                    category: .systemHUD,
                    title: settings.hideInScreenCapture ? "Screen Privacy On" : "Screen Privacy Off",
                    subtitle: settings.hideInScreenCapture ? "Notch hidden from screen recordings" : "Visible in screen recordings",
                    badgeText: settings.hideInScreenCapture ? "HIDDEN" : "VISIBLE",
                    symbolName: settings.hideInScreenCapture ? "eye.slash.fill" : "eye.fill",
                    accentHex: "#B5ADE2",
                    targetTab: .settings
                )
            )
        }
        if old.preventSleepEnabled != settings.preventSleepEnabled {
            systemService.setPreventSleep(settings.preventSleepEnabled)
            postTransientLiveActivity(
                TransientLiveActivity(
                    category: .systemHUD,
                    title: settings.preventSleepEnabled ? "Never Sleep On" : "Never Sleep Off",
                    subtitle: settings.preventSleepEnabled ? "Mac display kept awake" : "Normal sleep schedule restored",
                    badgeText: settings.preventSleepEnabled ? "AWAKE" : "OFF",
                    symbolName: "cup.and.saucer.fill",
                    accentHex: "#FAC03D",
                    targetTab: .hub,
                    targetHubSection: .overview
                )
            )
        }
        if old.eyeBreakReminderEnabled != settings.eyeBreakReminderEnabled {
            healthService.setEyeBreakReminder(enabled: settings.eyeBreakReminderEnabled)
            onHitRectNeedsUpdate?()
        }
        if old.snapOnTopEdgeDrag != settings.snapOnTopEdgeDrag {
            snapService.updateTopEdgeDragSnap(enabled: settings.snapOnTopEdgeDrag)
        }
        if old.weatherCity != settings.weatherCity || old.weatherUnit != settings.weatherUnit {
            refreshWeather(force: true)
        }
    }

    private func handleTimerCompleted(phase: TimerPhase, minutes: Int) {
        if phase == .focus {
            let today = DailyFocusStats.todayKey()
            if focusStats.dayKey != today {
                focusStats = DailyFocusStats(dayKey: today)
            }
            focusStats.completedSessions += 1
            focusStats.focusedMinutes += minutes
            persistence.saveStats(focusStats)

            let currentHour = Calendar.current.component(.hour, from: Date())
            updateTodayActivityRecord { record in
                record.focusedMinutes += minutes
                record.hourlyFocusMinutes[currentHour, default: 0] += minutes
            }

            if let activeFocusTaskID,
               let idx = tasks.firstIndex(where: { $0.id == activeFocusTaskID }) {
                tasks[idx].focusedMinutes += minutes
                taskRemainingSeconds.removeValue(forKey: activeFocusTaskID)
                persistence.saveTasks(tasks)
            }
            activeCountdownSourceIsReminder = false
        }

        if settings.soundEnabled {
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
        sendNotification(
            title: phase == .focus ? "Focus session complete" : "Break finished",
            body: phase == .focus
                ? "Great work — \(minutes)m focus block finished. Take a quick break."
                : "Ready for your next focus session."
        )
        postTransientLiveActivity(
            TransientLiveActivity(
                category: .pomodoro,
                title: phase == .focus ? "Focus Complete" : "Break Finished",
                subtitle: phase == .focus ? "\(minutes)m block logged to Insights" : "Ready for your next block",
                badgeText: "DONE",
                symbolName: "checkmark.seal.fill",
                accentHex: "#21C473",
                targetTab: .insights
            ),
            durationSeconds: 4.5
        )

        let nextPhase: TimerPhase = (phase == .focus) ? .shortBreak : .focus
        let nextMinutes = (nextPhase == .focus) ? settings.focusMinutes : settings.shortBreakMinutes
        timer.configure(minutes: nextMinutes, phase: nextPhase)
        syncAmbientAudio()
        triggerMascotPulse()
    }

    private func recordTaskCompletion(delta: Int) {
        updateTodayActivityRecord { record in
            record.completedTasks = max(0, record.completedTasks + delta)
        }
    }

    private func updateTodayActivityRecord(_ mutate: (inout DailyActivityRecord) -> Void) {
        let key = DailyFocusStats.todayKey()
        if let idx = activityHistory.firstIndex(where: { $0.dayKey == key }) {
            mutate(&activityHistory[idx])
        } else {
            var record = DailyActivityRecord(dayKey: key)
            mutate(&record)
            activityHistory.append(record)
        }
        if activityHistory.count > 60 {
            activityHistory = Array(activityHistory.sorted { $0.dayKey < $1.dayKey }.suffix(60))
        }
        persistence.saveActivityHistory(activityHistory)
    }

    private func sendNotification(title: String, body: String) {
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.bundleIdentifier != nil
        else {
            return
        }
        Self.deliverLocalNotification(title: title, body: body)
    }

    nonisolated private static func deliverLocalNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request)
        }
    }

    private func triggerMascotPulse() {
        lastTaskCompletedPulse = true
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            lastTaskCompletedPulse = false
        }
    }
}
