import Foundation

/// Navigation sections displayed in the expanded notch drawer.
public enum NotchTab: String, CaseIterable, Codable, Sendable, Identifiable {
    case today
    case week
    case hub
    case timer
    case notes
    case insights
    case clips
    case mirror
    case settings

    public var id: String { rawValue }

    /// Tabs rendered in the top-right segmented switcher.
    public static var primaryTabs: [NotchTab] {
        [.today, .week, .hub, .timer, .notes, .insights]
    }

    public var title: String {
        switch self {
        case .today: return "Workspace"
        case .week: return "Week"
        case .hub: return "Hub"
        case .timer: return "Focus"
        case .notes: return "Notes"
        case .insights: return "Insights"
        case .clips: return "Clips"
        case .mirror: return "Mirror"
        case .settings: return "Settings"
        }
    }

    public var systemImage: String {
        switch self {
        case .today: return "square.grid.2x2"
        case .week: return "calendar.day.timeline.left"
        case .hub: return "squares.leading.rectangle"
        case .timer: return "timer"
        case .notes: return "note.text"
        case .insights: return "chart.bar.xaxis"
        case .clips: return "photo.on.rectangle.angled"
        case .mirror: return "camera.aperture"
        case .settings: return "gearshape"
        }
    }
}

public enum HubSection: String, CaseIterable, Codable, Sendable, Identifiable {
    case overview
    case health
    case screenTime
    case devAI
    case snap

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: return "Dashboard"
        case .health: return "Health"
        case .screenTime: return "Screen Time"
        case .devAI: return "Dev & AI"
        case .snap: return "Snap Zones"
        }
    }

    public var systemImage: String {
        switch self {
        case .overview: return "rectangle.grid.2x2"
        case .health: return "heart.circle"
        case .screenTime: return "hourglass"
        case .devAI: return "terminal"
        case .snap: return "macwindow.split.2x2"
        }
    }
}

public enum TaskBucket: String, Codable, CaseIterable, Sendable, Identifiable {
    case inbox
    case today
    case tomorrow
    case upcoming

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .inbox: return "Inbox"
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .upcoming: return "Upcoming"
        }
    }
}

public enum WeekPlanColumn: Identifiable, Hashable, Sendable {
    case inbox
    case day(dayKey: String, date: Date, offset: Int)
    case later

    public var id: String {
        switch self {
        case .inbox: return "inbox"
        case .day(let dayKey, _, _): return "day-\(dayKey)"
        case .later: return "later"
        }
    }

    public var bucket: TaskBucket {
        switch self {
        case .inbox: return .inbox
        case .day(_, _, let offset):
            if offset == 0 { return .today }
            if offset == 1 { return .tomorrow }
            return .upcoming
        case .later: return .upcoming
        }
    }

    public var dayKey: String? {
        if case .day(let key, _, _) = self {
            return key
        }
        return nil
    }
}

public enum TaskRecurrence: String, Codable, CaseIterable, Sendable {
    case none
    case daily
    case weekdays
    case weekly

    public var label: String? {
        switch self {
        case .none: return nil
        case .daily: return "Daily"
        case .weekdays: return "Weekdays"
        case .weekly: return "Weekly"
        }
    }
}

public enum TaskPriority: String, Codable, Sendable, CaseIterable {
    case normal
    case high
}

public struct TaskItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var isCompleted: Bool
    public var createdAt: Date
    public var completedAt: Date?
    public var reminderIdentifier: String?
    public var priority: TaskPriority
    public var scheduledBucket: TaskBucket
    public var scheduledDayKey: String?
    public var dueDate: Date?
    public var projectTag: String?
    public var recurrence: TaskRecurrence
    public var snoozedUntil: Date?
    public var focusedMinutes: Int

    public init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        reminderIdentifier: String? = nil,
        priority: TaskPriority = .normal,
        scheduledBucket: TaskBucket = .today,
        scheduledDayKey: String? = nil,
        dueDate: Date? = nil,
        projectTag: String? = nil,
        recurrence: TaskRecurrence = .none,
        snoozedUntil: Date? = nil,
        focusedMinutes: Int = 0
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.reminderIdentifier = reminderIdentifier
        self.priority = priority
        self.scheduledBucket = scheduledBucket
        self.scheduledDayKey = scheduledDayKey ?? dueDate.map { DailyFocusStats.todayKey(for: $0) }
        self.dueDate = dueDate
        self.projectTag = projectTag
        self.recurrence = recurrence
        self.snoozedUntil = snoozedUntil
        self.focusedMinutes = focusedMinutes
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case isCompleted
        case createdAt
        case completedAt
        case reminderIdentifier
        case priority
        case scheduledBucket
        case scheduledDayKey
        case dueDate
        case projectTag
        case recurrence
        case snoozedUntil
        case focusedMinutes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        reminderIdentifier = try container.decodeIfPresent(String.self, forKey: .reminderIdentifier)
        priority = try container.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .normal
        scheduledBucket = try container.decodeIfPresent(TaskBucket.self, forKey: .scheduledBucket) ?? .today
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        scheduledDayKey = try container.decodeIfPresent(String.self, forKey: .scheduledDayKey)
            ?? dueDate.map { DailyFocusStats.todayKey(for: $0) }
        projectTag = try container.decodeIfPresent(String.self, forKey: .projectTag)
        recurrence = try container.decodeIfPresent(TaskRecurrence.self, forKey: .recurrence) ?? .none
        snoozedUntil = try container.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        focusedMinutes = try container.decodeIfPresent(Int.self, forKey: .focusedMinutes) ?? 0
    }

    public func formattedDueTime() -> String? {
        guard let dueDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: dueDate)
    }

    public var detectedMeetingURL: URL? {
        MeetingLinkExtractor.extractMeetingURL(explicitURL: nil, location: nil, notes: title)
    }
}

public struct NoteEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var body: String
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String = "Daily Notepad",
        body: String = "",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.updatedAt = updatedAt
    }
}

public struct CalendarEventItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var calendarTitle: String
    public var colorHex: String
    public var location: String?
    public var meetingURL: URL?
    public var travelTimeMinutes: Int?

    public init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendarTitle: String,
        colorHex: String,
        location: String? = nil,
        meetingURL: URL? = nil,
        travelTimeMinutes: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.calendarTitle = calendarTitle
        self.colorHex = colorHex
        self.location = location
        self.meetingURL = meetingURL
        self.travelTimeMinutes = travelTimeMinutes
    }

    public func isOngoing(at now: Date) -> Bool {
        !isAllDay && startDate <= now && endDate > now
    }

    public var leaveByDate: Date? {
        guard let travelTimeMinutes, travelTimeMinutes > 0, !isAllDay else { return nil }
        return startDate.addingTimeInterval(-TimeInterval(travelTimeMinutes * 60))
    }

    public var durationMinutes: Int {
        max(1, Int(round(endDate.timeIntervalSince(startDate) / 60)))
    }

    public var meetingServiceLabel: String? {
        guard let meetingURL else { return nil }
        return MeetingLinkExtractor.serviceLabel(for: meetingURL)
    }

    public func statusLabel(relativeTo now: Date) -> String {
        if isAllDay {
            return "All day"
        }
        if isOngoing(at: now) {
            let mins = max(1, Int(ceil(endDate.timeIntervalSince(now) / 60)))
            return "Now · \(mins)m left"
        }
        let delta = Int(round(startDate.timeIntervalSince(now) / 60))
        if delta <= 0 {
            return "Starting"
        }
        if delta < 60 {
            return "in \(delta)m"
        }
        let hours = delta / 60
        let rem = delta % 60
        return rem == 0 ? "in \(hours)h" : "in \(hours)h \(rem)m"
    }
}

public struct ClipItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var path: String
    public var name: String
    public var addedAt: Date
    public var isPinned: Bool
    public var isImage: Bool

    public var url: URL {
        URL(fileURLWithPath: path)
    }

    public init(
        id: UUID = UUID(),
        url: URL,
        addedAt: Date = Date(),
        isPinned: Bool = false,
        isImage: Bool = false
    ) {
        self.id = id
        self.path = url.path
        self.name = url.lastPathComponent
        self.addedAt = addedAt
        self.isPinned = isPinned
        self.isImage = isImage
    }
}

public enum DisplaySelectionMode: String, Codable, CaseIterable, Sendable {
    case activeMouseScreen
    case primaryScreen

    public var label: String {
        switch self {
        case .activeMouseScreen: return "Display with Cursor"
        case .primaryScreen: return "Primary Display"
        }
    }
}

public enum FocusSoundscape: String, Codable, CaseIterable, Sendable, Identifiable {
    case none
    case rain
    case brownNoise
    case ocean
    case cafe

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .none: return "Off"
        case .rain: return "Rain"
        case .brownNoise: return "Brown"
        case .ocean: return "Ocean"
        case .cafe: return "Cafe"
        }
    }

    public var systemImage: String {
        switch self {
        case .none: return "speaker.slash"
        case .rain: return "cloud.rain.fill"
        case .brownNoise: return "waveform"
        case .ocean: return "water.waves"
        case .cafe: return "cup.and.saucer.fill"
        }
    }
}

public enum GlobalShortcutStyle: String, Codable, CaseIterable, Sendable {
    case optionSpace
    case optionN

    public var label: String {
        switch self {
        case .optionSpace: return "⌥ Space"
        case .optionN: return "⌥ N"
        }
    }
}

public struct DailyFocusStats: Codable, Equatable, Sendable {
    public var dayKey: String
    public var completedSessions: Int
    public var focusedMinutes: Int

    public init(dayKey: String = DailyFocusStats.todayKey(), completedSessions: Int = 0, focusedMinutes: Int = 0) {
        self.dayKey = dayKey
        self.completedSessions = completedSessions
        self.focusedMinutes = focusedMinutes
    }

    public static func todayKey(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    public static func date(fromDayKey key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }
}

public struct DailyActivityRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: String { dayKey }
    public var dayKey: String
    public var completedTasks: Int
    public var focusedMinutes: Int
    public var hourlyFocusMinutes: [Int: Int]

    public init(
        dayKey: String,
        completedTasks: Int = 0,
        focusedMinutes: Int = 0,
        hourlyFocusMinutes: [Int: Int] = [:]
    ) {
        self.dayKey = dayKey
        self.completedTasks = completedTasks
        self.focusedMinutes = focusedMinutes
        self.hourlyFocusMinutes = hourlyFocusMinutes
    }
}

public enum WeatherUnit: String, Codable, CaseIterable, Sendable {
    case fahrenheit
    case celsius

    public var label: String {
        switch self {
        case .fahrenheit: return "°F"
        case .celsius: return "°C"
        }
    }
}

public enum TranslatorProvider: String, Codable, CaseIterable, Sendable {
    case ollama
    case openAI

    public var label: String {
        switch self {
        case .ollama: return "Ollama (Local)"
        case .openAI: return "OpenAI"
        }
    }
}

public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case system, en, fr, de, es, ptBR, it, ja, nl, ko, pl, zhHans

    public var label: String {
        switch self {
        case .system: return "System"
        case .en: return "English"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .es: return "Español"
        case .ptBR: return "Português (Brasil)"
        case .it: return "Italiano"
        case .ja: return "日本語"
        case .nl: return "Nederlands"
        case .ko: return "한국어"
        case .pl: return "Polski"
        case .zhHans: return "简体中文"
        }
    }
}

public enum SnapZone: String, CaseIterable, Sendable, Identifiable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case leftThird
    case centerThird
    case rightThird
    case topLeftQuarter
    case topRightQuarter
    case bottomLeftQuarter
    case bottomRightQuarter
    case maximize
    case center

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .leftThird: return "Left 1/3"
        case .centerThird: return "Center 1/3"
        case .rightThird: return "Right 1/3"
        case .topLeftQuarter: return "Top Left"
        case .topRightQuarter: return "Top Right"
        case .bottomLeftQuarter: return "Bottom Left"
        case .bottomRightQuarter: return "Bottom Right"
        case .maximize: return "Maximize"
        case .center: return "Center 70%"
        }
    }
}

public enum DropActionKind: String, CaseIterable, Sendable, Identifiable {
    case shelf
    case airDrop
    case zip
    case convertPNG
    case convertJPG
    case reveal
    case trash
    case eject

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .shelf: return "Shelf"
        case .airDrop: return "AirDrop"
        case .zip: return "Zip"
        case .convertPNG: return "To PNG"
        case .convertJPG: return "To JPG"
        case .reveal: return "Finder"
        case .trash: return "Trash"
        case .eject: return "Eject"
        }
    }

    public var systemImage: String {
        switch self {
        case .shelf: return "tray.and.arrow.down.fill"
        case .airDrop: return "dot.radiowaves.left.and.right"
        case .zip: return "doc.zipper"
        case .convertPNG: return "photo"
        case .convertJPG: return "photo.fill"
        case .reveal: return "folder"
        case .trash: return "trash"
        case .eject: return "eject.fill"
        }
    }
}

public struct DailyHealthStats: Codable, Equatable, Sendable {
    public var dayKey: String
    public var waterGlasses: Int
    public var waterGoal: Int
    public var breaksTaken: Int
    public var breaksGoal: Int
    public var mindfulMinutes: Int
    public var mindfulGoal: Int
    public var lastBreakAt: Date?
    public var streakDays: Int

    public init(
        dayKey: String = DailyFocusStats.todayKey(),
        waterGlasses: Int = 0,
        waterGoal: Int = 8,
        breaksTaken: Int = 0,
        breaksGoal: Int = 6,
        mindfulMinutes: Int = 0,
        mindfulGoal: Int = 15,
        lastBreakAt: Date? = nil,
        streakDays: Int = 0
    ) {
        self.dayKey = dayKey
        self.waterGlasses = waterGlasses
        self.waterGoal = waterGoal
        self.breaksTaken = breaksTaken
        self.breaksGoal = breaksGoal
        self.mindfulMinutes = mindfulMinutes
        self.mindfulGoal = mindfulGoal
        self.lastBreakAt = lastBreakAt
        self.streakDays = streakDays
    }
}

public struct ScreenTimeDailyStats: Codable, Equatable, Sendable {
    public var dayKey: String
    public var secondsByBundleID: [String: Int]
    public var appNamesByBundleID: [String: String]
    public var categoriesByBundleID: [String: String]
    public var appSwitches: Int

    public init(
        dayKey: String = DailyFocusStats.todayKey(),
        secondsByBundleID: [String: Int] = [:],
        appNamesByBundleID: [String: String] = [:],
        categoriesByBundleID: [String: String] = [:],
        appSwitches: Int = 0
    ) {
        self.dayKey = dayKey
        self.secondsByBundleID = secondsByBundleID
        self.appNamesByBundleID = appNamesByBundleID
        self.categoriesByBundleID = categoriesByBundleID
        self.appSwitches = appSwitches
    }

    public var totalSeconds: Int {
        secondsByBundleID.values.reduce(0, +)
    }
}

public enum LiveActivityCategory: String, Sendable {
    case media
    case notifications
    case calendar
    case tasks
    case bluetooth
    case systemHUD
    case pomodoro
    case sessionLock
}

public struct TransientLiveActivity: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let category: LiveActivityCategory
    public let title: String
    public let subtitle: String
    public let badgeText: String?
    public let symbolName: String
    public let accentHex: String
    public let targetTab: NotchTab?
    public let targetHubSection: HubSection?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        category: LiveActivityCategory,
        title: String,
        subtitle: String,
        badgeText: String? = nil,
        symbolName: String,
        accentHex: String = "#EE9E5B",
        targetTab: NotchTab? = nil,
        targetHubSection: HubSection? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.subtitle = subtitle
        self.badgeText = badgeText
        self.symbolName = symbolName
        self.accentHex = accentHex
        self.targetTab = targetTab
        self.targetHubSection = targetHubSection
        self.createdAt = createdAt
    }
}

public enum MusicPlayerPreference: String, Codable, CaseIterable, Sendable, Identifiable {
    case automatic
    case youTubeMusic
    case spotify
    case appleMusic

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .automatic: return "Auto"
        case .youTubeMusic: return "YouTube Music"
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        }
    }

    public var shortLabel: String {
        switch self {
        case .automatic: return "Auto"
        case .youTubeMusic: return "YT Music"
        case .spotify: return "Spotify"
        case .appleMusic: return "Music"
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var hoverToExpand: Bool
    public var hoverDelayMs: Int
    public var collapsedWidth: Double
    public var isWideDrawer: Bool
    public var showTimerInNotch: Bool
    public var showNextEventInNotch: Bool
    public var showLiveActivityNudge: Bool
    public var showTransientLiveActivities: Bool
    public var showMediaInNotch: Bool
    public var preferredMusicPlayer: MusicPlayerPreference
    public var hideInScreenCapture: Bool
    public var preventSleepEnabled: Bool
    public var owlAnimationEnabled: Bool
    public var globalShortcutEnabled: Bool
    public var shortcutStyle: GlobalShortcutStyle
    public var syncReminders: Bool
    public var watchScreenshots: Bool
    public var focusMinutes: Int
    public var shortBreakMinutes: Int
    public var focusSoundscape: FocusSoundscape
    public var focusSoundVolume: Double
    public var soundEnabled: Bool
    public var displayMode: DisplaySelectionMode
    public var weatherCity: String
    public var weatherUnit: WeatherUnit
    public var eyeBreakReminderEnabled: Bool
    public var bedtimeHour: Int
    public var appLanguage: AppLanguage
    public var snapOnTopEdgeDrag: Bool
    public var githubToken: String
    public var githubRepos: String
    public var jiraBaseURL: String
    public var jiraEmail: String
    public var jiraToken: String
    public var jiraJQL: String
    public var translatorProvider: TranslatorProvider
    public var translatorEndpoint: String
    public var translatorModel: String
    public var openAIKey: String

    public init(
        hoverToExpand: Bool = true,
        hoverDelayMs: Int = 240,
        collapsedWidth: Double = 188,
        isWideDrawer: Bool = false,
        showTimerInNotch: Bool = true,
        showNextEventInNotch: Bool = true,
        showLiveActivityNudge: Bool = true,
        showTransientLiveActivities: Bool = true,
        showMediaInNotch: Bool = true,
        preferredMusicPlayer: MusicPlayerPreference = .automatic,
        hideInScreenCapture: Bool = false,
        preventSleepEnabled: Bool = false,
        owlAnimationEnabled: Bool = true,
        globalShortcutEnabled: Bool = true,
        shortcutStyle: GlobalShortcutStyle = .optionSpace,
        syncReminders: Bool = false,
        watchScreenshots: Bool = true,
        focusMinutes: Int = 25,
        shortBreakMinutes: Int = 5,
        focusSoundscape: FocusSoundscape = .rain,
        focusSoundVolume: Double = 0.45,
        soundEnabled: Bool = true,
        displayMode: DisplaySelectionMode = .activeMouseScreen,
        weatherCity: String = "",
        weatherUnit: WeatherUnit = .fahrenheit,
        eyeBreakReminderEnabled: Bool = false,
        bedtimeHour: Int = 22,
        appLanguage: AppLanguage = .system,
        snapOnTopEdgeDrag: Bool = false,
        githubToken: String = "",
        githubRepos: String = "",
        jiraBaseURL: String = "",
        jiraEmail: String = "",
        jiraToken: String = "",
        jiraJQL: String = "assignee = currentUser() AND statusCategory != Done",
        translatorProvider: TranslatorProvider = .ollama,
        translatorEndpoint: String = "http://localhost:11434",
        translatorModel: String = "llama3.2",
        openAIKey: String = ""
    ) {
        self.hoverToExpand = hoverToExpand
        self.hoverDelayMs = hoverDelayMs
        self.collapsedWidth = collapsedWidth
        self.isWideDrawer = isWideDrawer
        self.showTimerInNotch = showTimerInNotch
        self.showNextEventInNotch = showNextEventInNotch
        self.showLiveActivityNudge = showLiveActivityNudge
        self.showTransientLiveActivities = showTransientLiveActivities
        self.showMediaInNotch = showMediaInNotch
        self.preferredMusicPlayer = preferredMusicPlayer
        self.hideInScreenCapture = hideInScreenCapture
        self.preventSleepEnabled = preventSleepEnabled
        self.owlAnimationEnabled = owlAnimationEnabled
        self.globalShortcutEnabled = globalShortcutEnabled
        self.shortcutStyle = shortcutStyle
        self.syncReminders = syncReminders
        self.watchScreenshots = watchScreenshots
        self.focusMinutes = focusMinutes
        self.shortBreakMinutes = shortBreakMinutes
        self.focusSoundscape = focusSoundscape
        self.focusSoundVolume = focusSoundVolume
        self.soundEnabled = soundEnabled
        self.displayMode = displayMode
        self.weatherCity = weatherCity
        self.weatherUnit = weatherUnit
        self.eyeBreakReminderEnabled = eyeBreakReminderEnabled
        self.bedtimeHour = bedtimeHour
        self.appLanguage = appLanguage
        self.snapOnTopEdgeDrag = snapOnTopEdgeDrag
        self.githubToken = githubToken
        self.githubRepos = githubRepos
        self.jiraBaseURL = jiraBaseURL
        self.jiraEmail = jiraEmail
        self.jiraToken = jiraToken
        self.jiraJQL = jiraJQL
        self.translatorProvider = translatorProvider
        self.translatorEndpoint = translatorEndpoint
        self.translatorModel = translatorModel
        self.openAIKey = openAIKey
    }

    enum CodingKeys: String, CodingKey {
        case hoverToExpand
        case hoverDelayMs
        case collapsedWidth
        case isWideDrawer
        case showTimerInNotch
        case showNextEventInNotch
        case showLiveActivityNudge
        case showTransientLiveActivities
        case showMediaInNotch
        case preferredMusicPlayer
        case hideInScreenCapture
        case preventSleepEnabled
        case owlAnimationEnabled
        case globalShortcutEnabled
        case shortcutStyle
        case syncReminders
        case watchScreenshots
        case focusMinutes
        case shortBreakMinutes
        case focusSoundscape
        case focusSoundVolume
        case soundEnabled
        case displayMode
        case weatherCity
        case weatherUnit
        case eyeBreakReminderEnabled
        case bedtimeHour
        case appLanguage
        case snapOnTopEdgeDrag
        case githubToken
        case githubRepos
        case jiraBaseURL
        case jiraEmail
        case jiraToken
        case jiraJQL
        case translatorProvider
        case translatorEndpoint
        case translatorModel
        case openAIKey
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hoverToExpand = try c.decodeIfPresent(Bool.self, forKey: .hoverToExpand) ?? true
        hoverDelayMs = try c.decodeIfPresent(Int.self, forKey: .hoverDelayMs) ?? 240
        collapsedWidth = try c.decodeIfPresent(Double.self, forKey: .collapsedWidth) ?? 188
        isWideDrawer = try c.decodeIfPresent(Bool.self, forKey: .isWideDrawer) ?? false
        showTimerInNotch = try c.decodeIfPresent(Bool.self, forKey: .showTimerInNotch) ?? true
        showNextEventInNotch = try c.decodeIfPresent(Bool.self, forKey: .showNextEventInNotch) ?? true
        showLiveActivityNudge = try c.decodeIfPresent(Bool.self, forKey: .showLiveActivityNudge) ?? true
        showTransientLiveActivities = try c.decodeIfPresent(Bool.self, forKey: .showTransientLiveActivities) ?? true
        showMediaInNotch = try c.decodeIfPresent(Bool.self, forKey: .showMediaInNotch) ?? true
        preferredMusicPlayer = try c.decodeIfPresent(MusicPlayerPreference.self, forKey: .preferredMusicPlayer) ?? .automatic
        hideInScreenCapture = try c.decodeIfPresent(Bool.self, forKey: .hideInScreenCapture) ?? false
        preventSleepEnabled = try c.decodeIfPresent(Bool.self, forKey: .preventSleepEnabled) ?? false
        owlAnimationEnabled = try c.decodeIfPresent(Bool.self, forKey: .owlAnimationEnabled) ?? true
        globalShortcutEnabled = try c.decodeIfPresent(Bool.self, forKey: .globalShortcutEnabled) ?? true
        shortcutStyle = try c.decodeIfPresent(GlobalShortcutStyle.self, forKey: .shortcutStyle) ?? .optionSpace
        syncReminders = try c.decodeIfPresent(Bool.self, forKey: .syncReminders) ?? false
        watchScreenshots = try c.decodeIfPresent(Bool.self, forKey: .watchScreenshots) ?? true
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 25
        shortBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? 5
        focusSoundscape = try c.decodeIfPresent(FocusSoundscape.self, forKey: .focusSoundscape) ?? .rain
        focusSoundVolume = try c.decodeIfPresent(Double.self, forKey: .focusSoundVolume) ?? 0.45
        soundEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        displayMode = try c.decodeIfPresent(DisplaySelectionMode.self, forKey: .displayMode) ?? .activeMouseScreen
        weatherCity = try c.decodeIfPresent(String.self, forKey: .weatherCity) ?? ""
        weatherUnit = try c.decodeIfPresent(WeatherUnit.self, forKey: .weatherUnit) ?? .fahrenheit
        eyeBreakReminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .eyeBreakReminderEnabled) ?? false
        bedtimeHour = try c.decodeIfPresent(Int.self, forKey: .bedtimeHour) ?? 22
        appLanguage = try c.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? .system
        snapOnTopEdgeDrag = try c.decodeIfPresent(Bool.self, forKey: .snapOnTopEdgeDrag) ?? false
        githubToken = try c.decodeIfPresent(String.self, forKey: .githubToken) ?? ""
        githubRepos = try c.decodeIfPresent(String.self, forKey: .githubRepos) ?? ""
        jiraBaseURL = try c.decodeIfPresent(String.self, forKey: .jiraBaseURL) ?? ""
        jiraEmail = try c.decodeIfPresent(String.self, forKey: .jiraEmail) ?? ""
        jiraToken = try c.decodeIfPresent(String.self, forKey: .jiraToken) ?? ""
        jiraJQL = try c.decodeIfPresent(String.self, forKey: .jiraJQL) ?? "assignee = currentUser() AND statusCategory != Done"
        translatorProvider = try c.decodeIfPresent(TranslatorProvider.self, forKey: .translatorProvider) ?? .ollama
        translatorEndpoint = try c.decodeIfPresent(String.self, forKey: .translatorEndpoint) ?? "http://localhost:11434"
        translatorModel = try c.decodeIfPresent(String.self, forKey: .translatorModel) ?? "llama3.2"
        openAIKey = try c.decodeIfPresent(String.self, forKey: .openAIKey) ?? ""
    }
}
