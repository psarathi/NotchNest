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

public enum TaskSortMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case manual
    case priority
    case dueTime
    case duration

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .manual: return "Default"
        case .priority: return "Priority"
        case .dueTime: return "Due Time"
        case .duration: return "Duration"
        }
    }
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
    public var targetMinutes: Int?
    public var reminderLeadMinutes: Int?

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
        focusedMinutes: Int = 0,
        targetMinutes: Int? = nil,
        reminderLeadMinutes: Int? = nil
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
        self.targetMinutes = targetMinutes
        self.reminderLeadMinutes = reminderLeadMinutes
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
        case targetMinutes
        case reminderLeadMinutes
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
        targetMinutes = try container.decodeIfPresent(Int.self, forKey: .targetMinutes)
        reminderLeadMinutes = try container.decodeIfPresent(Int.self, forKey: .reminderLeadMinutes)
    }

    public func reminderWindowStartDate() -> Date? {
        guard !isCompleted, let dueDate, let lead = reminderLeadMinutes, lead >= 0 else { return nil }
        return dueDate.addingTimeInterval(-TimeInterval(lead * 60))
    }

    public func formattedReminderLead() -> String? {
        guard let lead = reminderLeadMinutes, lead >= 0 else { return nil }
        return lead == 0 ? "At due" : "\(lead)m before"
    }

    public func formattedDueTime() -> String? {
        guard let dueDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: dueDate)
    }

    public func formattedTargetDuration() -> String? {
        guard let targetMinutes, targetMinutes > 0 else { return nil }
        return "\(targetMinutes)m"
    }

    public func dueCountdownLabel(relativeTo now: Date = Date()) -> String? {
        guard !isCompleted, let dueDate else { return nil }
        let deltaSeconds = dueDate.timeIntervalSince(now)
        guard deltaSeconds >= -300 && deltaSeconds <= 4 * 3600 else { return nil }
        let mins = Int(ceil(deltaSeconds / 60))
        if mins <= 0 {
            return "due now"
        }
        if mins < 60 {
            return "in \(mins)m"
        }
        let hrs = mins / 60
        let rem = mins % 60
        return rem == 0 ? "in \(hrs)h" : "in \(hrs)h \(rem)m"
    }

    public var detectedMeetingURL: URL? {
        MeetingLinkExtractor.extractMeetingURL(explicitURL: nil, location: nil, notes: title)
    }
}

public struct NoteEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var body: String
    public var rtfData: Data?
    public var updatedAt: Date
    public var dailyDayKey: String?

    public init(
        id: UUID = UUID(),
        title: String = "Daily Notepad",
        body: String = "",
        rtfData: Data? = nil,
        updatedAt: Date = Date(),
        dailyDayKey: String? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.rtfData = rtfData
        self.updatedAt = updatedAt
        self.dailyDayKey = dailyDayKey
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case rtfData
        case updatedAt
        case dailyDayKey
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        rtfData = try container.decodeIfPresent(Data.self, forKey: .rtfData)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        dailyDayKey = try container.decodeIfPresent(String.self, forKey: .dailyDayKey)
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
    case copyText
    case compressImage
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
        case .copyText: return "Copy Text"
        case .compressImage: return "Compress"
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
        case .copyText: return "text.viewfinder"
        case .compressImage: return "arrow.down.right.and.arrow.up.left"
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

public struct ClipboardEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var addedAt: Date
    public var isPinned: Bool
    public var isURL: Bool

    public init(
        id: UUID = UUID(),
        text: String,
        addedAt: Date = Date(),
        isPinned: Bool = false,
        isURL: Bool? = nil
    ) {
        self.id = id
        self.text = text
        self.addedAt = addedAt
        self.isPinned = isPinned
        if let isURL {
            self.isURL = isURL
        } else {
            self.isURL = Self.detectHTTPURL(from: text) != nil
        }
    }

    public var detectedURL: URL? {
        Self.detectHTTPURL(from: text)
    }

    public static func detectHTTPURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace),
              trimmed.count <= 2048,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            return nil
        }
        return url
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

public enum CollapsedDisplayMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case automatic
    case music
    case countdown
    case meeting
    case vitals
    case minimal

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .automatic: return "Auto (Smart)"
        case .music: return "Music Player"
        case .countdown: return "Task Countdown"
        case .meeting: return "Next Meeting"
        case .vitals: return "Mac Vitals"
        case .minimal: return "Minimal (Owl)"
        }
    }
}

public enum ExpandedCountdownStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case bottomRail
    case hudStrip
    case headerPill

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .bottomRail: return "Bottom Rail (Default)"
        case .hudStrip: return "Slim HUD Strip"
        case .headerPill: return "Header Pill"
        }
    }
}

public struct MicroTimerItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var label: String
    public var totalSeconds: TimeInterval
    public var remainingSeconds: TimeInterval
    public var endDate: Date?
    public var isPaused: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        label: String,
        minutes: Int,
        now: Date = Date()
    ) {
        let clampedMinutes = min(max(1, minutes), 180)
        let seconds = TimeInterval(clampedMinutes * 60)
        self.id = id
        self.label = label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Timer" : label.trimmingCharacters(in: .whitespacesAndNewlines)
        self.totalSeconds = seconds
        self.remainingSeconds = seconds
        self.endDate = now.addingTimeInterval(seconds)
        self.isPaused = false
        self.createdAt = now
    }

    public var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(max((totalSeconds - remainingSeconds) / totalSeconds, 0), 1)
    }

    public var formattedRemaining: String {
        let total = max(0, Int(ceil(remainingSeconds)))
        let hours = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%02d:%02d", mins, secs)
    }
}

public enum NotchScrollGestureAction: Equatable, Sendable {
    case adjustVolume(delta: Double)
    case cycleCollapsedMode(step: Int)
    case skipTrack(step: Int)
}

/// Damped scroll-wheel gesture recognizer for the narrow collapsed notch bar.
/// Drops inertial trackpad momentum and enforces per-swipe hysteresis on horizontal swipes.
public struct NotchScrollGestureRecognizer: Sendable {
    private var accumulatedY: Double = 0
    private var accumulatedX: Double = 0
    private var lastHorizontalFireAt: Date = .distantPast

    public init() {}

    public mutating func reset() {
        accumulatedY = 0
        accumulatedX = 0
    }

    public mutating func ingest(
        deltaX: Double,
        deltaY: Double,
        hasPreciseDeltas: Bool,
        isMomentumPhase: Bool,
        isMediaSlotActive: Bool,
        now: Date = Date()
    ) -> NotchScrollGestureAction? {
        // Ignore inertial coasting frames from macOS trackpads so flicks do not overshoot.
        if isMomentumPhase {
            return nil
        }

        let verticalScale = hasPreciseDeltas ? 1.0 : 12.0
        let horizontalScale = hasPreciseDeltas ? 1.0 : 14.0
        let dy = deltaY * verticalScale
        let dx = deltaX * horizontalScale

        let absY = abs(dy)
        let absX = abs(dx)

        if absY >= 0.4 && absY >= absX * 1.15 {
            accumulatedX = 0
            accumulatedY += dy
            let stepThreshold = 14.0
            if abs(accumulatedY) >= stepThreshold {
                let direction: Double = accumulatedY > 0 ? 1.0 : -1.0
                accumulatedY = 0
                return .adjustVolume(delta: direction * 0.05)
            }
            return nil
        }

        if absX >= 0.6 && absX > absY * 1.15 {
            accumulatedY = 0
            guard now.timeIntervalSince(lastHorizontalFireAt) >= 0.55 else {
                return nil
            }
            accumulatedX += dx
            let swipeThreshold = 26.0
            if abs(accumulatedX) >= swipeThreshold {
                let step = accumulatedX < 0 ? 1 : -1
                accumulatedX = 0
                lastHorizontalFireAt = now
                return isMediaSlotActive ? .skipTrack(step: step) : .cycleCollapsedMode(step: step)
            }
        }

        return nil
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
    public var showMicIndicatorInNotch: Bool
    public var collapsedDisplayMode: CollapsedDisplayMode
    public var expandedCountdownStyle: ExpandedCountdownStyle
    public var showExpandedVitals: Bool
    public var scrollWheelGesturesEnabled: Bool
    public var focusGuardEnabled: Bool
    public var focusGuardDelaySeconds: Int
    public var focusGuardIncludeBrowsers: Bool
    public var focusGuardAllowlist: String
    public var preferredMusicPlayer: MusicPlayerPreference
    public var autoPauseMediaOnJoin: Bool
    public var createMeetingNoteOnJoin: Bool
    public var hideInScreenCapture: Bool
    public var preventSleepEnabled: Bool
    public var owlAnimationEnabled: Bool
    public var globalShortcutEnabled: Bool
    public var shortcutStyle: GlobalShortcutStyle
    public var syncReminders: Bool
    public var watchScreenshots: Bool
    public var clipboardHistoryEnabled: Bool
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
        showMicIndicatorInNotch: Bool = true,
        collapsedDisplayMode: CollapsedDisplayMode = .automatic,
        expandedCountdownStyle: ExpandedCountdownStyle = .bottomRail,
        showExpandedVitals: Bool = true,
        scrollWheelGesturesEnabled: Bool = true,
        focusGuardEnabled: Bool = true,
        focusGuardDelaySeconds: Int = 45,
        focusGuardIncludeBrowsers: Bool = false,
        focusGuardAllowlist: String = "Terminal, Xcode, Cursor, Antigravity, Notes, NotchNest",
        preferredMusicPlayer: MusicPlayerPreference = .automatic,
        autoPauseMediaOnJoin: Bool = true,
        createMeetingNoteOnJoin: Bool = false,
        hideInScreenCapture: Bool = false,
        preventSleepEnabled: Bool = false,
        owlAnimationEnabled: Bool = true,
        globalShortcutEnabled: Bool = true,
        shortcutStyle: GlobalShortcutStyle = .optionSpace,
        syncReminders: Bool = false,
        watchScreenshots: Bool = true,
        clipboardHistoryEnabled: Bool = true,
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
        self.showMicIndicatorInNotch = showMicIndicatorInNotch
        self.collapsedDisplayMode = collapsedDisplayMode
        self.expandedCountdownStyle = expandedCountdownStyle
        self.showExpandedVitals = showExpandedVitals
        self.scrollWheelGesturesEnabled = scrollWheelGesturesEnabled
        self.focusGuardEnabled = focusGuardEnabled
        self.focusGuardDelaySeconds = focusGuardDelaySeconds
        self.focusGuardIncludeBrowsers = focusGuardIncludeBrowsers
        self.focusGuardAllowlist = focusGuardAllowlist
        self.preferredMusicPlayer = preferredMusicPlayer
        self.autoPauseMediaOnJoin = autoPauseMediaOnJoin
        self.createMeetingNoteOnJoin = createMeetingNoteOnJoin
        self.hideInScreenCapture = hideInScreenCapture
        self.preventSleepEnabled = preventSleepEnabled
        self.owlAnimationEnabled = owlAnimationEnabled
        self.globalShortcutEnabled = globalShortcutEnabled
        self.shortcutStyle = shortcutStyle
        self.syncReminders = syncReminders
        self.watchScreenshots = watchScreenshots
        self.clipboardHistoryEnabled = clipboardHistoryEnabled
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
        case showMicIndicatorInNotch
        case collapsedDisplayMode
        case expandedCountdownStyle
        case showExpandedVitals
        case scrollWheelGesturesEnabled
        case focusGuardEnabled
        case focusGuardDelaySeconds
        case focusGuardIncludeBrowsers
        case focusGuardAllowlist
        case preferredMusicPlayer
        case autoPauseMediaOnJoin
        case createMeetingNoteOnJoin
        case hideInScreenCapture
        case preventSleepEnabled
        case owlAnimationEnabled
        case globalShortcutEnabled
        case shortcutStyle
        case syncReminders
        case watchScreenshots
        case clipboardHistoryEnabled
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
        showMicIndicatorInNotch = try c.decodeIfPresent(Bool.self, forKey: .showMicIndicatorInNotch) ?? true
        collapsedDisplayMode = try c.decodeIfPresent(CollapsedDisplayMode.self, forKey: .collapsedDisplayMode) ?? .automatic
        expandedCountdownStyle = try c.decodeIfPresent(ExpandedCountdownStyle.self, forKey: .expandedCountdownStyle) ?? .bottomRail
        showExpandedVitals = try c.decodeIfPresent(Bool.self, forKey: .showExpandedVitals) ?? true
        scrollWheelGesturesEnabled = try c.decodeIfPresent(Bool.self, forKey: .scrollWheelGesturesEnabled) ?? true
        focusGuardEnabled = try c.decodeIfPresent(Bool.self, forKey: .focusGuardEnabled) ?? true
        focusGuardDelaySeconds = try c.decodeIfPresent(Int.self, forKey: .focusGuardDelaySeconds) ?? 45
        focusGuardIncludeBrowsers = try c.decodeIfPresent(Bool.self, forKey: .focusGuardIncludeBrowsers) ?? false
        focusGuardAllowlist = try c.decodeIfPresent(String.self, forKey: .focusGuardAllowlist)
            ?? "Terminal, Xcode, Cursor, Antigravity, Notes, NotchNest"
        preferredMusicPlayer = try c.decodeIfPresent(MusicPlayerPreference.self, forKey: .preferredMusicPlayer) ?? .automatic
        autoPauseMediaOnJoin = try c.decodeIfPresent(Bool.self, forKey: .autoPauseMediaOnJoin) ?? true
        createMeetingNoteOnJoin = try c.decodeIfPresent(Bool.self, forKey: .createMeetingNoteOnJoin) ?? false
        hideInScreenCapture = try c.decodeIfPresent(Bool.self, forKey: .hideInScreenCapture) ?? false
        preventSleepEnabled = try c.decodeIfPresent(Bool.self, forKey: .preventSleepEnabled) ?? false
        owlAnimationEnabled = try c.decodeIfPresent(Bool.self, forKey: .owlAnimationEnabled) ?? true
        globalShortcutEnabled = try c.decodeIfPresent(Bool.self, forKey: .globalShortcutEnabled) ?? true
        shortcutStyle = try c.decodeIfPresent(GlobalShortcutStyle.self, forKey: .shortcutStyle) ?? .optionSpace
        syncReminders = try c.decodeIfPresent(Bool.self, forKey: .syncReminders) ?? false
        watchScreenshots = try c.decodeIfPresent(Bool.self, forKey: .watchScreenshots) ?? true
        clipboardHistoryEnabled = try c.decodeIfPresent(Bool.self, forKey: .clipboardHistoryEnabled) ?? true
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
